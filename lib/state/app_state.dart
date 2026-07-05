import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mod.dart';
import '../services/stager.dart';
import '../services/steamcmd.dart';
import '../services/steamworks_engine.dart';
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
  String engine = 'steamworks'; // steamworks(默认,零配置)| steamcmd(CI/无桌面)
  String modsDir = '';
  String steamcmdPath = '';
  String steamUser = '';
  String webApiKey = '';
  String steamId64 = '';
  String seed = 'purple';
  ThemeMode themeMode = ThemeMode.system;

  // ---------- 数据 ----------
  List<Mod> mods = [];
  Mod? current; // 当前内容文件夹
  String? publishTargetId; // 发布目标:工坊条目 id,null = 新建条目
  final List<LogEntry> logs = [];
  List<WorkshopItemRemote> remoteItems = [];

  // ---------- 发布状态 ----------
  bool busy = false;
  PublishProgress? progress;
  String? failNote;

  int navIndex = 0;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    engine = sp.getString('engine') ?? 'steamworks';
    modsDir = sp.getString('modsDir') ?? '';
    steamcmdPath = sp.getString('steamcmdPath') ?? '';
    steamUser = sp.getString('steamUser') ?? '';
    webApiKey = sp.getString('webApiKey') ?? '';
    steamId64 = sp.getString('steamId64') ?? '';
    seed = sp.getString('seed') ?? 'purple';
    // 首次启动(未存过偏好)默认深色
    themeMode = ThemeMode.values[sp.getInt('themeMode') ?? ThemeMode.dark.index];
    if (modsDir.isNotEmpty) await scanMods();
    notifyListeners();
    if (engine == 'steamworks' && steamReady) {
      // 后台预拉名下条目:发布页封面对比、工坊页、绑定下拉都依赖它
      unawaited(refreshRemote());
    }
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
  Future<void> setEngine(String e) async {
    engine = e;
    await _persist('engine', e);
    notifyListeners();
  }

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

  /// Steamworks 助手随发行包放在主程序旁的 helper/ 目录。
  String get helperPath => p.join(
      File(Platform.resolvedExecutable).parent.path,
      'helper',
      'CpSteamHelper.exe');

  bool get steamReady => engine == 'steamworks'
      ? File(helperPath).existsSync()
      : (steamcmdPath.isNotEmpty &&
          File(steamcmdPath).existsSync() &&
          steamUser.isNotEmpty);

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

  /// 加载 mods 目录之外的模组文件夹(发布页「其他文件夹」/工坊行更新时用)。
  Future<Mod?> addExternalFolder(String dir) async {
    final existing = mods.where((m) => m.path == dir).firstOrNull;
    if (existing != null) return existing;
    final mod = await Mod.load(Directory(dir));
    if (mod == null) {
      log(LogLevel.error, '$dir 里没有有效的 modinfo.lua,无法作为模组文件夹');
      return null;
    }
    mods.add(mod);
    mods.sort((a, b) => a.info.name.compareTo(b.info.name));
    log(LogLevel.info, '已加入外部文件夹 ${mod.folderName}/(${mod.info.name})');
    notifyListeners();
    return mod;
  }

  static const int publishPageIndex = 2; // 导航:仪表盘0/工坊1/发布2/日志3/设置4

  /// 发起一次发布:内容文件夹与目标条目相互独立,任一为空则保留当前值。
  void startPublish({Mod? content, String? targetId, bool goto = true}) {
    if (content != null) current = content;
    publishTargetId = targetId;
    if (goto) navIndex = publishPageIndex;
    notifyListeners();
  }

  void setPublishTarget(String? id) {
    publishTargetId = id;
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
    required String? targetId, // null = 新建条目
    required String version,
    required String description,
    required String changeNote,
    required int visibility,
    required List<String> tags,
  }) async {
    if (busy) return false;
    if (!steamReady) {
      log(
          LogLevel.error,
          engine == 'steamworks'
              ? '发布环境未就绪:未找到 Steamworks 助手(helper\\CpSteamHelper.exe),请使用完整发行包'
              : '发布环境未就绪:检查 steamcmd 路径与账号(设置页)');
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
      final wsVersion = targetId == null
          ? ''
          : (remoteItems
                  .where((x) => x.id == targetId)
                  .firstOrNull
                  ?.version ??
              '');
      if (wsVersion.isNotEmpty && cmpVer(version, wsVersion) <= 0) {
        throw Exception('版本 $version 需大于工坊当前 $wsVersion');
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
      final pv = mod.preview;
      if (pv != null) {
        final len = await pv.length();
        if (len >= 1024 * 1024) {
          throw Exception(
              '预览图 ${(len / 1024).round()} KB ≥ 1MB 上限,Steam 会拒收');
        }
        preview = pv.path;
      }

      final req = PublishRequest(
        appId: mod.pub.appId,
        publishedFileId: targetId,
        contentFolder: staged.path,
        previewFile: preview,
        title: mod.info.name,
        description: description,
        changeNote: changeNote,
        visibility: visibility,
        tags: tags,
        version: version,
      );
      final Stream<PublishEvent> events = engine == 'steamworks'
          ? SteamworksEngine(helperPath: helperPath).publish(req)
          : SteamcmdEngine(steamcmdPath: steamcmdPath, username: steamUser)
              .publish(req);

      String? newId;
      String? error;
      await for (final ev in events) {
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

      final resultId =
          (newId != null && newId.isNotEmpty) ? newId : targetId;
      // 只持久化内容设置(可见性/标签);发布目标是会话态,不写入文件夹
      mod.pub.visibility = visibility;
      mod.pub.tags = List.of(tags);
      await mod.savePub();
      publishTargetId = resultId; // 会话内:新建后再次发布即更新该条目
      log(LogLevel.info,
          '✔ 已发布 ${mod.info.name} v$version(条目 ${resultId ?? '?'})· 更新记录已写入');
      unawaited(refreshRemote()); // 刷新列表,新版本/新条目立即反映
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
    // 首选:Steamworks 助手直查(QueryUserUGC,零配置,官方工具同款机制)
    if (engine == 'steamworks' && File(helperPath).existsSync()) {
      try {
        final proc = await Process.start(helperPath, ['list', '322330']);
        await proc.stdin.close();
        final errFuture = proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final items = <WorkshopItemRemote>[];
        String? error;
        var ok = false;
        await for (final line in proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          try {
            final j = jsonDecode(line) as Map<String, dynamic>;
            if (j['event'] == 'item') {
              items.add(WorkshopItemRemote(
                id: j['id'].toString(),
                title: j['title'] as String? ?? '(无标题)',
                subs: (j['subs'] as num?)?.toInt() ?? 0,
                favorites: (j['favorites'] as num?)?.toInt() ?? 0,
                comments: (j['comments'] as num?)?.toInt() ?? 0,
                views: (j['views'] as num?)?.toInt() ?? 0,
                votesUp: (j['votesUp'] as num?)?.toInt() ?? 0,
                votesDown: (j['votesDown'] as num?)?.toInt() ?? 0,
                score: (j['score'] as num?)?.toDouble() ?? 0,
                updated: j['updated'] != null && (j['updated'] as num) > 0
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (j['updated'] as num).toInt() * 1000)
                    : null,
                tags: (j['tags'] as String? ?? '')
                    .split(',')
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .toList(),
                version: versionFromMeta(j['meta'] as String?),
                previewUrl: j['preview'] as String? ?? '',
                description: j['desc'] as String? ?? '',
              ));
            } else if (j['event'] == 'result') {
              ok = j['ok'] == true;
              if (!ok) error = j['error']?.toString();
            }
          } catch (_) {/* 非 JSON 行忽略 */}
        }
        final errLines = await errFuture;
        final code = await proc.exitCode;
        if (ok) {
          remoteItems = items;
          log(
              LogLevel.info,
              items.isEmpty
                  ? 'QueryUserUGC → 0 个条目:该账号尚未发布过工坊模组(功能正常)'
                  : 'QueryUserUGC → ${items.length} 个条目(零配置,来自 Steam 会话)');
        } else {
          for (final line in errLines) {
            log(LogLevel.error, '[helper] $line');
          }
          log(LogLevel.error,
              '拉取名下条目失败:${error ?? '助手异常退出(exit $code),详见上方 [helper] 日志'}');
        }
      } catch (e) {
        log(LogLevel.error, '拉取名下条目失败:$e');
      }
      notifyListeners();
      return;
    }

    // 备用:Steam Web API(steamcmd 引擎 / 无助手环境)
    if (webApiKey.isEmpty || steamId64.isEmpty) {
      log(LogLevel.warn,
          'steamcmd 引擎下拉取名下条目需配置 Web API Key / SteamID64(设置页);切回 Steamworks 引擎则零配置');
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
