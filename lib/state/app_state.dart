import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mod.dart';
import '../services/stager.dart';
import '../services/steamcmd.dart';
import '../services/updater.dart';
import '../version.dart';
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
  ThemeMode themeMode = ThemeMode.dark; // 与首帧一致,防启动白闪

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
    notifyListeners();
    unawaited(_warmup()); // 磁盘扫描/远端拉取放后台,init 只负责快速读偏好
  }

  Future<void> _warmup() async {
    if (modsDir.isNotEmpty) await scanMods();
    if (engine == 'steamworks' && steamReady) {
      // 后台预拉名下条目:发布页封面对比、工坊页、绑定下拉都依赖它
      unawaited(refreshRemote());
    }
    unawaited(checkUpdates());
  }

  UpdateInfo? update;

  Future<void> checkUpdates({bool manual = false}) async {
    final u = await checkWorkshopUpdate(modsDir) ?? await checkGithubUpdate();
    update = u;
    if (u != null) {
      log(LogLevel.info, '发现新版本 v${u.version}(${u.source}),当前 v$kAppVersion');
    } else if (manual) {
      log(LogLevel.info, '已是最新版本 v$kAppVersion');
    }
    notifyListeners();
  }

  void dismissUpdate() {
    update = null;
    notifyListeners();
  }

  Future<void> startUpdate() async {
    final u = update;
    if (u == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      var zip = u.zipPath;
      if (zip == null && u.downloadUrl != null) {
        log(LogLevel.info, '正在从 ${u.source} 下载 v${u.version}…');
        zip = await downloadZip(u.downloadUrl!);
      }
      if (zip == null) {
        log(LogLevel.error, '更新包获取失败,稍后重试');
        return;
      }
      log(LogLevel.info, '应用更新中,即将自动重启…');
      final err = await applyUpdate(zip);
      if (err != null) log(LogLevel.error, '更新失败:$err');
    } finally {
      busy = false;
      notifyListeners();
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
    notifyListeners(); // 立即刷新路径显示,不等后面较慢的扫描
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
      Platform.isWindows ? 'CpSteamHelper.exe' : 'CpSteamHelper');

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
        try {
          final mod = await Mod.load(ent);
          if (mod != null) mods.add(mod);
        } catch (e) {
          // 单个坏模组不能中断整轮扫描
          log(LogLevel.warn, '跳过无法读取的模组 ${ent.path}:$e');
        }
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
    required List<LangEntry> languages, // 至少一条;第一条为主语言(带内容)
    required String changeNote,
    required int visibility,
    required List<String> tags,
    Set<String> parts = const {'content', 'text', 'preview', 'tags', 'visibility'},
  }) async {
    final isNew = targetId == null;
    final upContent = isNew || parts.contains('content');
    final upText = isNew || parts.contains('text');
    final upPreview = isNew || parts.contains('preview');
    final upTags = isNew || parts.contains('tags');
    final upVisibility = isNew || parts.contains('visibility');
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
      var contentFolder = mod.path;
      if (upContent) {
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
          // SteamPipe 工坊无固定体积硬上限(100MB 是老 Steam Cloud 通道的限制),
          // 超大包只提示不拦截,真被拒会由 Steam 返回 EResult
          log(LogLevel.warn,
              '内容 ${(plan.totalSize / 1048576).toStringAsFixed(1)} MB 较大,上传耗时会变长;若被 Steam 拒绝请检查是否含无关大文件');
        }
        final staged = await materialize(mod, plan);
        log(LogLevel.info,
            '已暂存 ${plan.kept.length} 项(忽略 ${plan.dropped.length} 项)→ ${staged.path}');
        contentFolder = staged.path;
      } else {
        log(LogLevel.info, '本次不更新内容文件,跳过版本校验与暂存');
      }

      String? preview;
      if (upPreview) {
        final pv = mod.preview;
        if (pv != null) {
          final len = await pv.length();
          if (len >= 1024 * 1024) {
            throw Exception(
                '预览图 ${(len / 1024).round()} KB ≥ 1MB 上限,Steam 会拒收');
          }
          preview = pv.path;
        }
      }

      // 标签 = 类型标签(modinfo 派生)+ 发布页里的用户标签;
      // version: 由 helper 注入。UI 已从远端种子标签,故不再并入远端
      // ——否则用户删掉的标签会在发布时复活
      final tagSet = <String>{mod.info.typeTag, ...tags};
      tagSet.removeWhere((t) => t.startsWith('version:'));

      final primary = languages.isNotEmpty
          ? languages.first
          : LangEntry('english', mod.info.name, '');
      final req = PublishRequest(
        appId: mod.pub.appId,
        publishedFileId: targetId,
        contentFolder: contentFolder,
        previewFile: preview,
        title: primary.title,
        description: primary.desc,
        changeNote: changeNote,
        visibility: visibility,
        tags: tagSet.toList(),
        version: version,
        languages: languages,
        updateContent: upContent,
        updateText: upText,
        updatePreview: upPreview,
        updateTags: upTags,
        updateVisibility: upVisibility,
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
      mod.pub.tags = List.of(tags); // 类型/版本标签每次发布自动生成,不落盘
      await mod.savePub();
      publishTargetId = resultId; // 会话内:新建后再次发布即更新该条目
      if (resultId != null) _itemLangsCache.remove(resultId); // 简介已变,缓存失效
      log(LogLevel.info,
          '✔ 已发布 ${mod.info.name} v$version(条目 ${resultId ?? '?'})· 更新记录已写入');
      // 本地先行更新列表(即时反映),不马上起 list 助手 ——
      // 刚发布完 Steam 会话尚未释放,立刻查询会撞车;延后 4 秒再拉一次
      if (resultId != null) _upsertLocal(resultId, mod, version, visibility);
      Timer(const Duration(seconds: 4), () => unawaited(refreshRemote()));
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
  /// 发布成功后本地即时更新列表条目(避免立刻起 list 助手撞 Steam 会话)。
  void _upsertLocal(String id, Mod mod, String version, int visibility) {
    final idx = remoteItems.indexWhere((x) => x.id == id);
    if (idx >= 0) {
      final old = remoteItems[idx];
      remoteItems[idx] = WorkshopItemRemote(
        id: id,
        title: mod.info.name,
        subs: old.subs,
        favorites: old.favorites,
        comments: old.comments,
        views: old.views,
        votesUp: old.votesUp,
        votesDown: old.votesDown,
        score: old.score,
        updated: DateTime.now(),
        tags: old.tags,
        version: version,
        previewUrl: old.previewUrl,
        description: old.description,
      );
    } else {
      remoteItems = [
        WorkshopItemRemote(
            id: id,
            title: mod.info.name,
            subs: 0,
            updated: DateTime.now(),
            version: version),
        ...remoteItems,
      ];
    }
    notifyListeners();
  }

  bool _refreshing = false; // 单飞:同一时刻只允许一个 list 助手,避免多进程抢 Steam 会话

  /// 各条目多语言底稿的会话缓存:同一条目只对 Steam 查一次,
  /// 发布成功后失效(内容可能已变)。
  final Map<String, List<LangEntry>> _itemLangsCache = {};

  /// 取某条目各语言的标题/简介(多语言底稿)。仅 Steamworks 引擎可用。
  Future<List<LangEntry>> fetchItemLangs(String id) async {
    final cached = _itemLangsCache[id];
    if (cached != null) return cached;
    if (engine != 'steamworks' || !File(helperPath).existsSync()) return [];
    final out = <LangEntry>[];
    try {
      final proc = await Process.start(helperPath, ['desc', id]);
      await proc.stdin.close();
      final killer = Timer(const Duration(seconds: 60), () => proc.kill());
      await for (final line in proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['event'] == 'lang') {
            out.add(LangEntry(j['lang'] as String? ?? '',
                j['title'] as String? ?? '', j['desc'] as String? ?? ''));
          }
        } catch (_) {}
      }
      await proc.exitCode;
      killer.cancel();
    } catch (_) {}
    if (out.isNotEmpty) _itemLangsCache[id] = out;
    return out;
  }

  Future<void> refreshRemote() async {
    if (_refreshing) return; // 已有拉取在进行,直接返回,不再起第二个助手
    _refreshing = true;
    try {
      await _refreshRemoteInner();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshRemoteInner() async {
    // 首选:Steamworks 助手直查(QueryUserUGC,零配置,官方工具同款机制)
    if (engine == 'steamworks' && File(helperPath).existsSync()) {
      Process? proc;
      try {
        proc = await Process.start(helperPath, ['list', '322330']);
        await proc.stdin.close();
        final p = proc;
        // 40 秒兜底:助手内部 30 秒查询超时若没生效,这里强杀,避免僵尸进程
        final killTimer = Timer(const Duration(seconds: 40), () => p.kill());
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
              final tags = (j['tags'] as String? ?? '')
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              // 版本优先取本工具写入的 metadata;老模组无 metadata 时,
              // 回退解析 DST 的 version:X 标签(官方工具留下的)
              var ver = versionFromMeta(j['meta'] as String?);
              if (ver.isEmpty) {
                final vt = tags.firstWhere((t) => t.startsWith('version:'),
                    orElse: () => '');
                if (vt.isNotEmpty) ver = vt.substring('version:'.length);
              }
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
                tags: tags,
                version: ver,
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
        killTimer.cancel();
        if (ok) {
          remoteItems = items;
          log(
              LogLevel.info,
              items.isEmpty
                  ? 'QueryUserUGC → 0 个条目:该账号尚未发布过工坊模组(功能正常)'
                  : 'QueryUserUGC → ${items.length} 个条目(零配置,来自 Steam 会话)');
        } else {
          // Steam 的 breakpad/minidump/API 等 stderr 属正常输出,不当错误刷屏
          final noise = RegExp(r'minidump|breakpad|API loaded|SetMinidump');
          for (final line in errLines) {
            if (!noise.hasMatch(line)) log(LogLevel.warn, '[helper] $line');
          }
          log(LogLevel.warn,
              '拉取名下条目失败:${error ?? '助手退出($code)'} —— 不影响发布,稍后自动重试');
        }
      } catch (e) {
        proc?.kill();
        log(LogLevel.warn, '拉取名下条目出错:$e —— 不影响发布');
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
