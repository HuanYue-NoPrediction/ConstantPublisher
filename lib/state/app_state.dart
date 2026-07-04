import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mod.dart';
import '../services/stager.dart';
import '../services/steamcmd.dart';
import '../services/workshop_api.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final DateTime time;
  LogEntry(this.level, this.message) : time = DateTime.now();
}

/// 发布进行中的可视状态(发布页与仪表盘共用)。
class PublishProgress {
  final String stage;
  final double progress;
  const PublishProgress(this.stage, this.progress);
}

class AppState extends ChangeNotifier {
  // ---------- 设置 ----------
  String modsDir = '';
  String steamcmdPath = '';
  String steamUser = '';
  String webApiKey = '';
  String steamId64 = '';
  String seed = 'purple';
  ThemeMode themeMode = ThemeMode.system;

  // ---------- 数据 ----------
  List<Mod> mods = [];
  Mod? current;
  final List<LogEntry> logs = [];
  List<WorkshopItemRemote> remoteItems = [];

  // ---------- 发布状态 ----------
  bool busy = false;
  PublishProgress? progress;
  String? failNote;

  int navIndex = 0;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    modsDir = sp.getString('modsDir') ?? '';
    steamcmdPath = sp.getString('steamcmdPath') ?? '';
    steamUser = sp.getString('steamUser') ?? '';
    webApiKey = sp.getString('webApiKey') ?? '';
    steamId64 = sp.getString('steamId64') ?? '';
    seed = sp.getString('seed') ?? 'purple';
    themeMode = ThemeMode
        .values[sp.getInt('themeMode') ?? ThemeMode.system.index];
    if (modsDir.isNotEmpty) await scanMods();
    notifyListeners();
  }

  Future<void> _persist(String key, String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(key, value);
  }

  void log(LogLevel lv, String msg) {
    logs.insert(0, LogEntry(lv, msg));
    if (logs.length > 500) logs.removeLast();
    notifyListeners();
  }

  void goto(int index) {
    navIndex = index;
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ---------- 设置修改 ----------
  Future<void> setModsDir(String dir) async {
    modsDir = dir;
    await _persist('modsDir', dir);
    await scanMods();
  }

  Future<void> setSteamcmdPath(String path) async {
    steamcmdPath = path;
    await _persist('steamcmdPath', path);
    notifyListeners();
  }

  Future<void> setSteamUser(String u) async {
    steamUser = u;
    await _persist('steamUser', u);
    notifyListeners();
  }

  Future<void> setWebApi(String key, String sid) async {
    webApiKey = key;
    steamId64 = sid;
    await _persist('webApiKey', key);
    await _persist('steamId64', sid);
    notifyListeners();
  }

  Future<void> setSeed(String s) async {
    seed = s;
    await _persist('seed', s);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('themeMode', m.index);
    notifyListeners();
  }

  bool get steamReady =>
      steamcmdPath.isNotEmpty &&
      File(steamcmdPath).existsSync() &&
      steamUser.isNotEmpty;

  // ---------- 模组 ----------
  Future<void> scanMods() async {
    mods = [];
    final root = Directory(modsDir);
    if (await root.exists()) {
      await for (final ent in root.list(followLinks: false)) {
        if (ent is! Directory) continue;
        final mod = await Mod.load(ent);
        if (mod != null) mods.add(mod);
      }
      mods.sort((a, b) => a.info.name.compareTo(b.info.name));
      log(LogLevel.info, '扫描 $modsDir → ${mods.length} 个模组');
    }
    if (current != null &&
        !mods.any((m) => m.path == current!.path)) {
      current = null;
    }
    current ??= mods.isNotEmpty ? mods.first : null;
    notifyListeners();
  }

  void select(Mod mod) {
    current = mod;
    notifyListeners();
  }

  void selectAndGoPublish(Mod mod) {
    current = mod;
    navIndex = 3; // 发布页
    notifyListeners();
  }

  /// 把工坊条目 id 绑定到任意本地文件夹 —— "新建文件夹更新老条目"走这里。
  Future<void> bindItem(Mod mod, String publishedFileId,
      {String? knownVersion}) async {
    for (final other in mods) {
      if (other != mod && other.pub.publishedFileId == publishedFileId) {
        other.pub.publishedFileId = null;
        other.pub.lastPublishedVersion = null;
        await other.savePub();
        log(LogLevel.info, '已解除 ${other.folderName}/ 对条目 $publishedFileId 的旧绑定');
      }
    }
    mod.pub.publishedFileId = publishedFileId;
    if (knownVersion != null) mod.pub.lastPublishedVersion = knownVersion;
    await mod.savePub();
    log(LogLevel.info,
        '已将 ${mod.folderName}/ 关联到工坊条目 $publishedFileId(写入 dstpub.json)');
    notifyListeners();
  }

  Future<void> unbindItem(Mod mod) async {
    mod.pub.publishedFileId = null;
    mod.pub.lastPublishedVersion = null;
    await mod.savePub();
    log(LogLevel.info, '已解除 ${mod.folderName}/ 的工坊绑定');
    notifyListeners();
  }

  // ---------- Dry-run ----------
  Future<StagePlan> dryRun(Mod mod) async {
    final plan = await planStage(mod);
    log(LogLevel.info,
        'Dry-run(${mod.info.name}):${plan.kept.length} 项 · '
        '${(plan.totalSize / 1048576).toStringAsFixed(2)} MB · '
        '${plan.dropped.length} 项被忽略 · 未上传');
    return plan;
  }

  // ---------- 发布 ----------
  Future<bool> publish({
    required Mod mod,
    required String version,
    required String description,
    required String changeNote,
    required int visibility,
  }) async {
    if (busy) return false;
    if (!steamReady) {
      log(LogLevel.error, '发布环境未就绪:检查 steamcmd 路径与账号(设置页)');
      return false;
    }
    busy = true;
    failNote = null;
    progress = const PublishProgress('校验 modinfo.lua', .02);
    notifyListeners();

    try {
      if (!mod.info.valid) {
        throw Exception('modinfo.lua 无效:缺少 name 或 version');
      }
      final last = mod.pub.lastPublishedVersion;
      if (last != null && cmpVer(version, last) <= 0) {
        throw Exception('版本 $version 需大于上次发布的 $last');
      }

      // 版本写回 modinfo.lua
      if (version != mod.info.version) {
        await mod.writeVersion(version);
        log(LogLevel.info, 'modinfo.lua version → $version');
      }

      progress = const PublishProgress('暂存清洗副本', .1);
      notifyListeners();
      final plan = await planStage(mod);
      if (plan.overLimit) {
        throw Exception(
            '内容 ${(plan.totalSize / 1048576).toStringAsFixed(1)} MB 超过工坊 100MB 上限');
      }
      final staged = await materialize(mod, plan);
      log(LogLevel.info,
          '已暂存 ${plan.kept.length} 项(忽略 ${plan.dropped.length} 项)→ ${staged.path}');

      String? preview;
      if (await mod.previewFile.exists()) {
        final len = await mod.previewFile.length();
        if (len >= 1024 * 1024) {
          throw Exception('preview.jpg ${(len / 1024).round()} KB ≥ 1MB 上限');
        }
        preview = mod.previewFile.path;
      }

      final engine = SteamcmdEngine(
          steamcmdPath: steamcmdPath, username: steamUser);
      final req = PublishRequest(
        appId: mod.pub.appId,
        publishedFileId: mod.pub.publishedFileId,
        contentFolder: staged.path,
        previewFile: preview,
        title: mod.info.name,
        description: description,
        changeNote: changeNote,
        visibility: visibility,
      );

      String? newId;
      String? error;
      await for (final ev in engine.publish(req)) {
        if (ev.logLine != null) log(LogLevel.info, '[steamcmd] ${ev.logLine}');
        if (ev.stage != null) {
          progress = PublishProgress(ev.stage!, ev.progress ?? 0);
          notifyListeners();
        }
        if (ev.done) {
          error = ev.error;
          newId = ev.publishedFileId;
        }
      }
      if (error != null) throw Exception(error);

      if (newId != null && newId.isNotEmpty) {
        mod.pub.publishedFileId = newId;
      }
      mod.pub.lastPublishedVersion = version;
      mod.pub.visibility = visibility;
      await mod.savePub();
      log(LogLevel.info,
          '✔ 已发布 ${mod.info.name} v$version(条目 ${mod.pub.publishedFileId ?? '?'})· 更新记录已写入');
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      failNote = msg;
      log(LogLevel.error, '发布失败:$msg —— 表单内容与草稿完好,修复后直接重试');
      return false;
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  // ---------- 工坊巡检 ----------
  Future<void> refreshRemote() async {
    if (webApiKey.isEmpty || steamId64.isEmpty) {
      log(LogLevel.warn, '未配置 Steam Web API Key / SteamID64,无法拉取名下条目(不影响发布)');
      return;
    }
    try {
      remoteItems =
          await fetchUserItems(apiKey: webApiKey, steamId64: steamId64);
      log(LogLevel.info, 'GetUserFiles → ${remoteItems.length} 个条目');
    } catch (e) {
      log(LogLevel.error, '拉取工坊条目失败:$e');
    }
    notifyListeners();
  }
}
