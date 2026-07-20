import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/mod.dart';
import '../../services/draft_store.dart';
import '../../services/stager.dart';
import '../../services/steamcmd.dart';
import '../../services/workshop_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets/bbcode.dart';
import '../widgets/bits.dart';

class PublishPage extends StatefulWidget {
  const PublishPage({super.key});

  @override
  State<PublishPage> createState() => _PublishPageState();
}

/// Steam 工坊支持的语言(码 → 中文名),简介/标题可按语言分开填。
const Map<String, String> kSteamLangs = {
  'schinese': '简体中文',
  'english': 'English',
  'tchinese': '繁體中文',
  'koreana': '한국어',
  'japanese': '日本語',
  'russian': 'Русский',
};

class _PublishPageState extends State<PublishPage> {
  final _verCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  int _visibility = 0;
  List<String> _tags = [];
  bool _descPreview = false;
  final Set<String> _parts = {
    'content',
    'text',
    'preview',
    'tags',
    'visibility'
  };

  // 多语言:每种语言各自的标题/简介;当前编辑的语言由 _curLang 指定
  String _curLang = 'schinese';
  final Map<String, String> _titles = {};
  final Map<String, String> _descs = {};

  String _loadedKey = ''; // '内容路径|目标id',变化时重载表单
  String _contentPath = '';
  String? _loadedTargetId; // 当前草稿归属的发布目标
  Timer? _debounce;
  String? _draftStamp;
  StagePlan? _plan;
  final Set<String> _expandedDirs = {};

  @override
  void dispose() {
    // 有待落盘的草稿就先冲刷保存(同步读控件,异步写盘),否则切页会丢最后 500ms 的编辑
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _saveDraft();
    }
    _debounce?.cancel();
    _verCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // 把当前语言的输入回存到映射
  void _stashCurrentLang() {
    _titles[_curLang] = _titleCtrl.text;
    _descs[_curLang] = _descCtrl.text;
  }

  // 切换编辑语言:先回存当前,再载入目标语言
  void _switchLang(String lang) {
    _stashCurrentLang();
    _curLang = lang;
    _titleCtrl.text = _titles[lang] ?? '';
    _descCtrl.text = _descs[lang] ?? '';
    setState(() {});
  }

  // 收集所有非空语言,主语言(当前有内容者优先,再退简体中文/首个)排第一
  List<LangEntry> _collectLangs() {
    _stashCurrentLang();
    final entries = <LangEntry>[];
    for (final code in kSteamLangs.keys) {
      final t = (_titles[code] ?? '').trim();
      final d = (_descs[code] ?? '').trim();
      if (t.isNotEmpty || d.isNotEmpty) entries.add(LangEntry(code, t, d));
    }
    if (entries.isEmpty) return [];
    // 当前正在编辑且有内容的语言作为主语言(带内容上传)
    entries.sort((a, b) {
      if (a.lang == _curLang) return -1;
      if (b.lang == _curLang) return 1;
      return 0;
    });
    return entries;
  }

  /// 内容文件夹或发布目标变化时:重置默认值,再叠加草稿。
  Future<void> _loadFor(Mod mod, WorkshopItemRemote? target) async {
    _contentPath = mod.path;
    _loadedTargetId = target?.id;
    _verCtrl.text = mod.info.version;
    _noteCtrl.text = '';
    _tags = target != null
        ? target.tags.where((t) => !t.startsWith('version:')).toList()
        : List.of(mod.pub.tags);
    _visibility = target != null && target.visibility >= 0
        ? target.visibility
        : mod.pub.visibility;
    _plan = null;
    _expandedDirs.clear();

    // 多语言默认:主语言(简体中文)标题=modinfo 名,简介=工坊现有/本地
    _titles.clear();
    _descs.clear();
    _curLang = 'schinese';
    _titles['schinese'] = mod.info.name;
    _descs['schinese'] = (target != null && target.description.isNotEmpty)
        ? target.description
        : mod.info.description;

    final d = await DraftStore.load(mod.path, target?.id);
    if (d != null) {
      _verCtrl.text = d.version.isEmpty ? _verCtrl.text : d.version;
      _visibility = d.visibility;
      _tags = List.of(d.tags);
      if (d.changeNote.isNotEmpty) _noteCtrl.text = d.changeNote;
      // 优先用草稿里的多语言映射;老草稿只有单份 description 则并入主语言
      if (d.titles.isNotEmpty || d.descs.isNotEmpty) {
        _titles
          ..clear()
          ..addAll(d.titles);
        _descs
          ..clear()
          ..addAll(d.descs);
        if (d.curLang.isNotEmpty) _curLang = d.curLang;
      } else if (d.description.isNotEmpty) {
        _descs['schinese'] = d.description;
      }
      _draftStamp = mounted
          ? AppLocalizations.of(context).pubDraftRestored(_fmtTime(d.savedAt))
          : null;
    } else {
      _draftStamp = null;
    }
    _titleCtrl.text = _titles[_curLang] ?? '';
    _descCtrl.text = _descs[_curLang] ?? '';
    _refreshPlan(mod);
    // 更新已发布条目时,后台按语言拉取各语言底稿,填进尚为空的语言槽
    if (target != null) _fetchLangBases(target.id, mod.path, target.id);
    if (mounted) setState(() {});
  }

  // 后台拉取该条目各语言底稿,只填当前仍为空的语言槽(不覆盖草稿/已填内容)
  Future<void> _fetchLangBases(
      String id, String contentPath, String? targetId) async {
    final langs = await context.read<AppState>().fetchItemLangs(id);
    if (!mounted || langs.isEmpty) return;
    // 若期间已切走(内容或目标变了),放弃
    if (_contentPath != contentPath || _loadedTargetId != targetId) return;
    var changed = false;
    for (final e in langs) {
      if (!kSteamLangs.containsKey(e.lang)) continue;
      if ((_titles[e.lang] ?? '').trim().isEmpty && e.title.isNotEmpty) {
        _titles[e.lang] = e.title;
        changed = true;
      }
      if ((_descs[e.lang] ?? '').trim().isEmpty && e.desc.isNotEmpty) {
        _descs[e.lang] = e.desc;
        changed = true;
      }
    }
    if (changed && mounted) {
      // 若当前正编辑的语言底稿刚被填上,同步到输入框
      if ((_titleCtrl.text).isEmpty) _titleCtrl.text = _titles[_curLang] ?? '';
      if ((_descCtrl.text).isEmpty) _descCtrl.text = _descs[_curLang] ?? '';
      setState(() {});
      // 把拉到的各语言底稿并入草稿:下次进页直接秒出,与主语言一致
      _saveDraftSoon();
    }
  }

  Future<void> _refreshPlan(Mod mod) async {
    final plan = await planStage(mod);
    if (mounted && _contentPath == mod.path) setState(() => _plan = plan);
  }

  Future<void> _toggleEntry(Mod mod, StagedEntry e) async {
    if (mod.pub.ignore.contains(e.rel)) {
      mod.pub.ignore.remove(e.rel);
    } else if (mod.pub.keep.contains(e.rel)) {
      mod.pub.keep.remove(e.rel);
    } else if (e.skipped) {
      mod.pub.keep.add(e.rel);
    } else {
      mod.pub.ignore.add(e.rel);
    }
    await mod.savePub();
    await _refreshPlan(mod);
  }

  Future<void> _toggleFolder(Mod mod, String dir, bool anyKept) async {
    if (mod.pub.ignore.contains(dir)) {
      mod.pub.ignore.remove(dir);
    } else if (mod.pub.keep.contains(dir)) {
      mod.pub.keep.remove(dir);
    } else if (anyKept) {
      mod.pub.ignore.add(dir);
    } else {
      mod.pub.keep.add(dir);
    }
    await mod.savePub();
    await _refreshPlan(mod);
  }

  List<Widget> _buildPlanRows(Mod mod, StagePlan plan) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final rootFiles = <StagedEntry>[];
    final dirs = <String, List<StagedEntry>>{};
    for (final e in plan.entries) {
      final i = e.rel.indexOf('/');
      if (i < 0) {
        rootFiles.add(e);
      } else {
        dirs.putIfAbsent(e.rel.substring(0, i), () => []).add(e);
      }
    }
    final rows = <Widget>[];
    for (final dir in dirs.keys.toList()..sort()) {
      final files = dirs[dir]!;
      final kept = files.where((e) => !e.skipped).length;
      final keptSize =
          files.where((e) => !e.skipped).fold<int>(0, (a, e) => a + e.size);
      final expanded = _expandedDirs.contains(dir);
      rows.add(InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() {
          expanded ? _expandedDirs.remove(dir) : _expandedDirs.add(dir);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Icon(Icons.folder_outlined,
                size: 14,
                color: kept > 0 ? scheme.onSurfaceVariant : scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$dir/',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  decoration: kept == 0 ? TextDecoration.lineThrough : null,
                  color: kept == 0 ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
            ),
            Text(
              kept == 0
                  ? t.planAllIgnored
                  : kept == files.length
                      ? t.planFolderAll(
                          '${files.length}', humanSize(keptSize))
                      : t.planFolderPart('$kept', '${files.length}',
                          humanSize(keptSize)),
              style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: kept == 0 ? scheme.error : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: kept > 0 ? t.planIgnoreFolder : t.planRestoreFolder,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _toggleFolder(mod, dir, kept > 0),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    kept > 0
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ));
      if (expanded) {
        for (final e in files) {
          rows.add(Padding(
            padding: const EdgeInsets.only(left: 20),
            child: _fileRow(mod, e),
          ));
        }
      }
    }
    for (final e in rootFiles) {
      rows.add(_fileRow(mod, e));
    }
    return rows;
  }

  Widget _fileRow(Mod mod, StagedEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _toggleEntry(mod, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Icon(
            e.skipped
                ? Icons.remove_circle_outline
                : Icons.check_circle_outline,
            size: 14,
            color: e.skipped ? scheme.error : sem.success,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.rel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                decoration: e.skipped ? TextDecoration.lineThrough : null,
                color: e.skipped ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
          Text(
            e.skipped ? (e.reason ?? '') : humanSize(e.size),
            style: TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: e.skipped ? scheme.error : scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickContentFolder(
      AppState state, Mod current, String? targetId) async {
    final picked = await showDialog<Mod>(
      context: context,
      builder: (_) =>
          _FolderPickDialog(mods: state.mods, currentPath: current.path),
    );
    if (picked != null && mounted) {
      state.startPublish(content: picked, targetId: targetId, goto: false);
    }
  }

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  void _saveDraftSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final path = _contentPath;
    if (path.isEmpty) return;
    _stashCurrentLang();
    final d = Draft(
      version: _verCtrl.text,
      visibility: _visibility,
      tags: _tags,
      changeNote: _noteCtrl.text,
      curLang: _curLang,
      titles: Map.of(_titles),
      descs: Map.of(_descs),
    );
    await DraftStore.save(path, _loadedTargetId, d);
    if (mounted) {
      setState(() => _draftStamp =
          AppLocalizations.of(context).pubDraftSaved(_fmtTime(d.savedAt)));
    }
  }

  void _onVersionChanged(String v) {
    _saveDraftSoon();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final t = AppLocalizations.of(context);
    final mod = state.current;
    final targetId = state.publishTargetId;
    final target = targetId == null
        ? null
        : state.remoteItems.where((x) => x.id == targetId).firstOrNull;

    if (mod == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.pubPickFolderFirst,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () async {
                final dir = await getDirectoryPath();
                if (dir == null) return;
                final m = await state.addExternalFolder(dir);
                if (m != null) {
                  state.startPublish(
                      content: m, targetId: targetId, goto: false);
                }
              },
              icon: const Icon(Icons.folder_open),
              label: Text(t.pubPickFolderBtn),
            ),
          ],
        ),
      );
    }

    final key = '${mod.path}|$targetId';
    if (key != _loadedKey) {
      _loadedKey = key;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadFor(mod, target));
    }

    final isNew = targetId == null;
    final wsVersion = target?.version ?? '';
    final verOk = _verCtrl.text.isNotEmpty &&
        (isNew || wsVersion.isEmpty || cmpVer(_verCtrl.text, wsVersion) > 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text(t.pubTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        // 发布目标
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Tooltip(
                  message: isNew ? t.targetTipNew : t.targetTipUpdate,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.targetTitle,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.info_outline,
                          size: 14, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: targetId ?? '__new__',
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    selectedItemBuilder: (context) => [
                      Row(children: [
                        Icon(Icons.add_circle_outline,
                            size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(t.targetNew,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ]),
                      for (final it in state.remoteItems)
                        Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: it.previewUrl.isEmpty
                                ? Icon(Icons.cloud_outlined,
                                    size: 18, color: scheme.onSurfaceVariant)
                                : Image.network(it.previewUrl,
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                        Icons.cloud_off_outlined,
                                        size: 18,
                                        color: scheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${it.title} · v${it.version.isEmpty ? '?' : it.version}',
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                    ],
                    items: [
                      DropdownMenuItem(
                        value: '__new__',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.add,
                                  size: 20, color: scheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.targetNew,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600)),
                                  Text(t.targetNewSub,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                      for (final it in state.remoteItems)
                        DropdownMenuItem(
                          value: it.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: it.previewUrl.isEmpty
                                    ? Container(
                                        width: 36,
                                        height: 36,
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.cloud_outlined,
                                            size: 18,
                                            color: scheme.onSurfaceVariant))
                                    : Image.network(it.previewUrl,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                            width: 36,
                                            height: 36,
                                            color: scheme
                                                .surfaceContainerHighest)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      t.targetItemSub(
                                          it.version.isEmpty
                                              ? '?'
                                              : it.version,
                                          _fmtCount(it.subs)),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        state.setPublishTarget(v == '__new__' ? null : v),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isNew) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Tooltip(
                    message: t.partsTip,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.partsTitle,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Icon(Icons.info_outline,
                            size: 14, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final (k, label, icon) in [
                          ('content', t.partContent,
                              Icons.folder_zip_outlined),
                          ('text', t.partText, Icons.description_outlined),
                          ('preview', t.partPreview, Icons.image_outlined),
                          ('tags', t.partTags, Icons.sell_outlined),
                          ('visibility', t.partVisibility,
                              Icons.visibility_outlined),
                        ])
                          FilterChip(
                            avatar: Icon(icon, size: 15),
                            label: Text(label,
                                style: const TextStyle(fontSize: 12)),
                            selected: _parts.contains(k),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _parts.add(k);
                              } else if (_parts.length > 1) {
                                _parts.remove(k);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 内容文件夹
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Text(t.folderTitle,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _pickContentFolder(state, mod, targetId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.folder_outlined,
                            size: 17, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            mod.folderName,
                            style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            mod.info.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down,
                            color: scheme.onSurfaceVariant),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final dir = await getDirectoryPath();
                    if (dir == null) return;
                    final m = await state.addExternalFolder(dir);
                    if (m != null) {
                      state.startPublish(
                          content: m, targetId: targetId, goto: false);
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(t.otherFolderBtn),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.save_outlined, size: 15, color: sem.success),
            const SizedBox(width: 6),
            Text(_draftStamp ?? t.pubDraftHint,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
        ),

        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > 980;
          final form = _buildForm(mod, isNew, wsVersion, verOk);
          final side =
              _buildSide(mod, target, targetId, isNew, wsVersion, verOk);
          if (!wide) {
            return Column(children: [form, const SizedBox(height: 14), side]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: form),
              const SizedBox(width: 16),
              SizedBox(width: 360, child: side),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildForm(Mod mod, bool isNew, String wsVersion, bool verOk) {
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final t = AppLocalizations.of(context);
    final bumpBase = wsVersion.isEmpty ? null : wsVersion;
    return Column(
      children: [
        SectionCard(
          title: t.verTitle,
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _verCtrl,
                  onChanged: _onVersionChanged,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {
                  _verCtrl.text = suggestBump(_verCtrl.text, bumpBase);
                  _onVersionChanged(_verCtrl.text);
                },
                child: Text(t.verBump(suggestBump(_verCtrl.text, bumpBase))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isNew
                      ? t.verNew
                      : wsVersion.isEmpty
                          ? t.verUnknown
                          : verOk
                              ? t.verOkAbove(wsVersion)
                              : t.verNeedAbove(wsVersion),
                  style: TextStyle(
                      fontSize: 12.5,
                      color: isNew
                          ? sem.success
                          : wsVersion.isEmpty
                              ? sem.warn
                              : verOk
                                  ? sem.success
                                  : scheme.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.wsPageTitle,
          subtitle: t.wsPageSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 语言切换:有内容的语言标 ●
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in kSteamLangs.entries)
                    ChoiceChip(
                      label: Text(
                        ((_titles[e.key]?.trim().isNotEmpty ?? false) ||
                                (_descs[e.key]?.trim().isNotEmpty ?? false))
                            ? '● ${e.value}'
                            : e.value,
                      ),
                      selected: _curLang == e.key,
                      onSelected: (_) => _switchLang(e.key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // 标题(工坊显示名,按语言)
              TextField(
                controller: _titleCtrl,
                onChanged: (_) => _saveDraftSoon(),
                decoration: InputDecoration(
                  labelText: t.titleLabel(kSteamLangs[_curLang]!),
                  hintText: t.titleHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              // 简介(BBCode,按语言)
              Row(
                children: [
                  Text(t.descLabel(kSteamLangs[_curLang]!),
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  SegmentedButton<bool>(
                    style:
                        const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(value: false, label: Text(t.editTab)),
                      ButtonSegment(value: true, label: Text(t.previewTab)),
                    ],
                    selected: {_descPreview},
                    onSelectionChanged: (s) =>
                        setState(() => _descPreview = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _descPreview
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: BBCodePreview(_descCtrl.text),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Wrap(
                            spacing: 0,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _bbIcon(Icons.format_bold, t.bbBold, '[b]',
                                  '[/b]'),
                              _bbIcon(Icons.format_italic, t.bbItalic, '[i]',
                                  '[/i]'),
                              _bbIcon(Icons.format_underlined, t.bbUnderline,
                                  '[u]', '[/u]'),
                              _bbIcon(Icons.strikethrough_s, t.bbStrike,
                                  '[strike]', '[/strike]'),
                              _bbDiv(),
                              _bbTxt('H1', t.bbH1, '[h1]', '[/h1]'),
                              _bbTxt('H2', t.bbH2, '[h2]', '[/h2]'),
                              _bbTxt('H3', t.bbH3, '[h3]', '[/h3]'),
                              _bbDiv(),
                              _bbIcon(Icons.format_list_bulleted, t.bbList,
                                  '[list]\n[*]', '\n[/list]'),
                              _bbIcon(Icons.format_list_numbered, t.bbOlist,
                                  '[olist]\n[*]', '\n[/olist]'),
                              _bbDiv(),
                              _bbIcon(Icons.link, t.bbLink, '[url=https://]',
                                  '[/url]'),
                              _bbIcon(Icons.image_outlined, t.bbImage,
                                  '[img]', '[/img]'),
                              _bbIcon(
                                  Icons.smart_display_outlined,
                                  t.bbVideo,
                                  '[previewyoutube=',
                                  ';full][/previewyoutube]'),
                              _bbDiv(),
                              _bbIcon(Icons.format_quote, t.bbQuote,
                                  '[quote=${t.bbQuoteAuthor}]', '[/quote]'),
                              _bbIcon(Icons.code, t.bbCode, '[code]',
                                  '[/code]'),
                              _bbIcon(
                                  Icons.table_chart_outlined,
                                  t.bbTable,
                                  '[table]\n[tr][th]${t.bbTableHeader}[/th][th]${t.bbTableHeader}[/th][/tr]\n'
                                      '[tr][td]${t.bbTableCell}[/td][td]${t.bbTableCell}[/td][/tr]\n[/table]',
                                  ''),
                              _bbDiv(),
                              _bbIcon(Icons.visibility_off_outlined,
                                  t.bbSpoiler, '[spoiler]', '[/spoiler]'),
                              _bbIcon(Icons.format_clear, t.bbNoparse,
                                  '[noparse]', '[/noparse]'),
                              _bbIcon(Icons.horizontal_rule, t.bbHr,
                                  '[hr][/hr]\n', ''),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descCtrl,
                          onChanged: (_) => _saveDraftSoon(),
                          maxLines: 8,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(
                              border: OutlineInputBorder()),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.noteTitle,
          subtitle: t.noteSubtitle,
          child: TextField(
            controller: _noteCtrl,
            onChanged: (_) => _saveDraftSoon(),
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
                border: const OutlineInputBorder(), hintText: t.noteHint),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.visTitle,
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(t.visPublic)),
              ButtonSegment(value: 3, label: Text(t.visUnlisted)),
              ButtonSegment(value: 1, label: Text(t.visFriends)),
              ButtonSegment(value: 2, label: Text(t.visPrivate)),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) {
              setState(() => _visibility = s.first);
              _saveDraftSoon();
            },
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.tagsTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in _tags)
                    InputChip(
                      label: Text(t),
                      onDeleted: () {
                        setState(() => _tags.remove(t));
                        _saveDraftSoon();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tagCtrl,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: t.tagsHint),
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isNotEmpty && !_tags.contains(t)) {
                    setState(() => _tags.add(t));
                    _saveDraftSoon();
                  }
                  _tagCtrl.clear();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickPreview(Mod mod) async {
    final group = XTypeGroup(
        label: AppLocalizations.of(context).imgGroupLabel,
        extensions: const ['jpg', 'jpeg', 'png', 'gif']);
    final f = await openFile(acceptedTypeGroups: [group]);
    if (f == null) return;
    final ext = p.extension(f.path).toLowerCase();
    final name = ext == '.png'
        ? 'preview.png'
        : ext == '.gif'
            ? 'preview.gif'
            : 'preview.jpg';
    final target = File(p.join(mod.path, name));
    // 换图前先把现有预览备份到 .preview_backup/(绝不直接删除,防误伤)
    final backupDir = Directory(p.join(mod.path, '.preview_backup'));
    for (final old in ['preview.jpg', 'preview.png', 'preview.gif']) {
      final of = File(p.join(mod.path, old));
      if (await of.exists()) {
        await backupDir.create(recursive: true);
        final ts = DateTime.now().millisecondsSinceEpoch;
        await of.rename(p.join(backupDir.path, '${ts}_$old'));
      }
    }
    await File(f.path).copy(target.path);
    // 关键:Image.file 按路径缓存解码结果,同名替换后必须清缓存才会重画
    await FileImage(target).evict();
    if (mounted) {
      setState(() {});
      toast(context, AppLocalizations.of(context).previewUpdated(name));
    }
  }

  void _wrapSel(String open, String close) {
    final sel = _descCtrl.selection;
    final text = _descCtrl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final inner = text.substring(start, end);
    _descCtrl.value = TextEditingValue(
      text:
          text.substring(0, start) + open + inner + close + text.substring(end),
      selection: TextSelection(
          baseOffset: start + open.length,
          extentOffset: start + open.length + inner.length),
    );
    _saveDraftSoon();
  }

  Widget _bbIcon(IconData icon, String tip, String open, String close) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _wrapSel(open, close),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(icon, size: 17),
        ),
      ),
    );
  }

  Widget _bbTxt(String label, String tip, String open, String close) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _wrapSel(open, close),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.1)),
        ),
      ),
    );
  }

  Widget _bbDiv() {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildSide(Mod mod, WorkshopItemRemote? target, String? targetId,
      bool isNew, String wsVersion, bool verOk) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final t = AppLocalizations.of(context);
    final plan = _plan;

    return Column(
      children: [
        SectionCard(
          title: t.previewTitle,
          subtitle: t.previewSubtitle,
          trailing: TextButton(
            onPressed: () => _pickPreview(mod),
            child: Text(t.previewChange),
          ),
          child: Builder(builder: (context) {
            final pv = mod.preview;
            final wsItem = target;

            Widget slot(Widget img, String label) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10), child: img),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                );

            Widget placeholder(IconData icon) => Container(
                  width: 64,
                  height: 64,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                );

            final slots = <Widget>[];
            if (!isNew) {
              slots.add(slot(
                wsItem != null && wsItem.previewUrl.isNotEmpty
                    ? Image.network(wsItem.previewUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            placeholder(Icons.cloud_off_outlined))
                    : placeholder(Icons.cloud_outlined),
                t.previewRemote,
              ));
              slots.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward,
                    size: 16, color: scheme.onSurfaceVariant),
              ));
            }

            if (pv == null) {
              slots.add(slot(
                  placeholder(Icons.image_not_supported_outlined),
                  t.previewLocalMissing));
              return Row(children: [
                ...slots,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.previewNotFound,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ),
              ]);
            }

            final stat = pv.statSync();
            final kb = (stat.size / 1024).round();
            final okSize = stat.size < 1024 * 1024;
            slots.add(slot(
              Image.file(
                pv,
                key: ValueKey('${pv.path}-${stat.modified}'),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    placeholder(Icons.broken_image_outlined),
              ),
              t.previewLocalUpload,
            ));

            return Row(
              children: [
                ...slots,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.basename(pv.path),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('$kb KB',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        okSize ? t.previewSizeOk : t.previewSizeBad,
                        style: TextStyle(
                            fontSize: 12,
                            color: okSize ? sem.success : scheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.uploadTitle,
          subtitle: t.uploadSubtitle,
          trailing: IconButton(
            tooltip: t.rescan,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => _refreshPlan(mod),
          ),
          child: plan == null
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          children: [
                            ..._buildPlanRows(mod, plan),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.uploadSummary(
                          humanSize(plan.totalSize),
                          '${plan.kept.length}',
                          '${plan.dropped.length}',
                          plan.overLimit ? t.uploadSummaryBig : ''),
                      style: TextStyle(
                          fontSize: 12,
                          color: plan.overLimit
                              ? sem.warn
                              : scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: (plan.totalSize / StagePlan.sizeReference)
                          .clamp(0.0, 1.0),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: t.publishCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: state.busy ||
                        (!isNew &&
                            _parts.contains('content') &&
                            wsVersion.isNotEmpty &&
                            !verOk)
                    ? null
                    : () async {
                        final langs = _collectLangs();
                        if ((isNew || _parts.contains('text')) &&
                            (langs.isEmpty || langs.first.title.isEmpty)) {
                          toast(context, t.needTitleToast);
                          return;
                        }
                        final ok = await state.publish(
                          mod: mod,
                          targetId: targetId,
                          version: _verCtrl.text.trim(),
                          languages: langs,
                          changeNote: _noteCtrl.text,
                          visibility: _visibility,
                          tags: List.of(_tags),
                          parts: Set.of(_parts),
                        );
                        if (ok) {
                          await DraftStore.clear(mod.path, targetId);
                          if (mounted) {
                            setState(() =>
                                _draftStamp = t.pubDraftCleared);
                            toast(
                                context,
                                t.publishedToast(
                                    mod.info.name, _verCtrl.text));
                          }
                        }
                      },
                icon: const Icon(Icons.upload),
                label: Text(state.busy
                    ? t.publishing
                    : isNew
                        ? t.publishNew
                        : t.publishUpdate),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: state.busy ? null : () => state.dryRun(mod),
                child: Text(t.dryRunBtn),
              ),
              if (state.busy && state.progress != null) ...[
                const SizedBox(height: 12),
                Text(state.progress!.stage,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: state.progress!.progress),
              ],
              if (state.failNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t.failNote(state.failNote ?? ''),
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${t.cliEquiv}\ndstpub upload ./${mod.folderName} '
                  '--set-version ${_verCtrl.text} --yes',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderPickDialog extends StatefulWidget {
  final List<Mod> mods;
  final String currentPath;
  const _FolderPickDialog({required this.mods, required this.currentPath});

  @override
  State<_FolderPickDialog> createState() => _FolderPickDialogState();
}

class _FolderPickDialogState extends State<_FolderPickDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _q.toLowerCase();
    final list = widget.mods
        .where((m) =>
            q.isEmpty ||
            m.folderName.toLowerCase().contains(q) ||
            m.info.name.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: Text(AppLocalizations.of(context).pickDialogTitle),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: AppLocalizations.of(context).pickDialogHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(AppLocalizations.of(context).pickNoMatch,
                        style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final m = list[i];
                      final selected = m.path == widget.currentPath;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(context).pop(m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 7),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                m.folderName,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer),
                              ),
                            ),
                            const Spacer(),
                            if (selected)
                              Icon(Icons.check,
                                  size: 17, color: scheme.primary),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).cancel),
        ),
      ],
    );
  }
}
