import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

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
  final Set<String> _parts = {'content', 'text', 'preview', 'tags', 'visibility'};

  // 多语言:每种语言各自的标题/简介;当前编辑的语言由 _curLang 指定
  String _curLang = 'schinese';
  final Map<String, String> _titles = {};
  final Map<String, String> _descs = {};

  String _loadedKey = ''; // '内容路径|目标id',变化时重载表单
  String _contentPath = '';
  String? _loadedTargetId; // 当前草稿归属的发布目标
  Timer? _debounce;
  String _draftStamp = '编辑内容会自动保存为草稿 —— 上传失败也不会丢';
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
      _draftStamp = '草稿已恢复(保存于 ${_fmtTime(d.savedAt)})';
    } else {
      _draftStamp = '编辑内容会自动保存为草稿 —— 上传失败也不会丢';
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
                color:
                    kept > 0 ? scheme.onSurfaceVariant : scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$dir/',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  decoration:
                      kept == 0 ? TextDecoration.lineThrough : null,
                  color: kept == 0
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            Text(
              kept == 0
                  ? '全部忽略'
                  : kept == files.length
                      ? '${files.length} 个文件 · ${humanSize(keptSize)}'
                      : '$kept/${files.length} 个上传 · ${humanSize(keptSize)}',
              style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color:
                      kept == 0 ? scheme.error : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: kept > 0 ? '忽略整个文件夹' : '恢复整个文件夹',
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
                decoration:
                    e.skipped ? TextDecoration.lineThrough : null,
                color: e.skipped
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
              ),
            ),
          ),
          Text(
            e.skipped ? (e.reason ?? '') : humanSize(e.size),
            style: TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color:
                    e.skipped ? scheme.error : scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
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
      setState(() => _draftStamp = '已自动保存 ${_fmtTime(d.savedAt)}');
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
            Text('先选择要上传的内容文件夹',
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
              label: const Text('选择文件夹…'),
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
        Text('发布', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        // 发布目标
        DropdownButtonFormField<String>(
          initialValue: targetId ?? '__new__',
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: '发布目标',
              border: OutlineInputBorder(),
              isDense: true),
          items: [
            const DropdownMenuItem(
              value: '__new__',
              child: Row(children: [
                Icon(Icons.add_circle_outline, size: 20),
                SizedBox(width: 10),
                Text('新建工坊条目'),
              ]),
            ),
            for (final it in state.remoteItems)
              DropdownMenuItem(
                value: it.id,
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: it.previewUrl.isEmpty
                        ? Icon(Icons.cloud_outlined,
                            size: 20, color: scheme.onSurfaceVariant)
                        : Image.network(it.previewUrl,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.cloud_off_outlined,
                                size: 20,
                                color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${it.title}  ·  v${it.version.isEmpty ? '?' : it.version}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
          ],
          onChanged: (v) =>
              state.setPublishTarget(v == '__new__' ? null : v),
        ),
        if (!isNew) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: '本次更新哪些内容',
            subtitle: '未勾选的部分保持工坊现状不变;只改简介时取消勾选内容文件,几秒就能发完',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (k, label, icon) in const [
                  ('content', '内容文件', Icons.folder_zip_outlined),
                  ('text', '标题与简介', Icons.description_outlined),
                  ('preview', '封面图', Icons.image_outlined),
                  ('tags', '标签', Icons.sell_outlined),
                  ('visibility', '可见性', Icons.visibility_outlined),
                ])
                  FilterChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _parts.contains(k),
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
        const SizedBox(height: 12),
        // 内容文件夹
        Row(
          children: [
            Expanded(
              child: DropdownMenu<String>(
                key: ValueKey(mod.path),
                initialSelection: mod.path,
                leadingIcon: const Icon(Icons.folder_outlined),
                label: const Text('内容文件夹'),
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                requestFocusOnTap: true,
                dropdownMenuEntries: [
                  for (final m in state.mods)
                    DropdownMenuEntry(
                      value: m.path,
                      label:
                          '${m.info.name.isEmpty ? m.folderName : m.info.name} · ${m.folderName}',
                      labelWidget: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.info.name.isEmpty
                                ? m.folderName
                                : m.info.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
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
                        ],
                      ),
                    ),
                ],
                onSelected: (v) {
                  final m =
                      state.mods.where((x) => x.path == v).firstOrNull;
                  if (m != null) {
                    state.startPublish(
                        content: m, targetId: targetId, goto: false);
                  }
                },
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
              label: const Text('其他文件夹…'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.save_outlined, size: 15, color: sem.success),
            const SizedBox(width: 6),
            Text(_draftStamp,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
    final bumpBase = wsVersion.isEmpty ? null : wsVersion;
    return Column(
      children: [
        SectionCard(
          title: '版本',
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
                child: Text('自增 → ${suggestBump(_verCtrl.text, bumpBase)}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isNew
                      ? '✓ 新建工坊条目'
                      : wsVersion.isEmpty
                          ? '⚠ 工坊版本未知(老条目无版本元数据)—— 请确认大于线上版本;本次发布后将自动记录'
                          : verOk
                              ? '✓ 大于工坊当前 $wsVersion'
                              : '✕ 需大于工坊当前 $wsVersion(自增按两者较高版本计算)',
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
          title: '工坊页面',
          subtitle: '标题与简介按语言分开填,发布时各语言分别提交(留空的语言不提交)',
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
                  labelText: '标题 · ${kSteamLangs[_curLang]}',
                  hintText: '工坊显示名(默认取 modinfo 的 name)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              // 简介(BBCode,按语言)
              Row(
                children: [
                  Text('简介(BBCode)· ${kSteamLangs[_curLang]}',
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  SegmentedButton<bool>(
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: false, label: Text('编写')),
                      ButtonSegment(value: true, label: Text('预览')),
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
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            _bbBtn('B', '[b]', '[/b]'),
                            _bbBtn('I', '[i]', '[/i]'),
                            _bbBtn('U', '[u]', '[/u]'),
                            _bbBtn('S', '[strike]', '[/strike]'),
                            _bbBtn('H1', '[h1]', '[/h1]'),
                            _bbBtn('H2', '[h2]', '[/h2]'),
                            _bbBtn('H3', '[h3]', '[/h3]'),
                            _bbBtn('列表', '[list]\n[*]', '\n[/list]'),
                            _bbBtn('序号', '[olist]\n[*]', '\n[/olist]'),
                            _bbBtn('链接', '[url=https://]', '[/url]'),
                            _bbBtn('图片', '[img]', '[/img]'),
                            _bbBtn('视频', '[previewyoutube=',
                                ';full][/previewyoutube]'),
                            _bbBtn('引用', '[quote=作者]', '[/quote]'),
                            _bbBtn('代码', '[code]', '[/code]'),
                            _bbBtn(
                                '表格',
                                '[table]\n[tr][th]表头[/th][th]表头[/th][/tr]\n'
                                    '[tr][td]内容[/td][td]内容[/td][/tr]\n[/table]',
                                ''),
                            _bbBtn('剧透', '[spoiler]', '[/spoiler]'),
                            _bbBtn('原文', '[noparse]', '[/noparse]'),
                            _bbBtn('分隔线', '[hr][/hr]\n', ''),
                          ],
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
          title: '更新日志',
          subtitle: '写入工坊更新记录,订阅者可见',
          child: TextField(
            controller: _noteCtrl,
            onChanged: (_) => _saveDraftSoon(),
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '这个版本改了什么…'),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '可见性',
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('公开')),
              ButtonSegment(value: 3, label: Text('不公开')),
              ButtonSegment(value: 1, label: Text('好友')),
              ButtonSegment(value: 2, label: Text('私密')),
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
          title: '标签',
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
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '输入标签后回车'),
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
    const group = XTypeGroup(
        label: '图片', extensions: ['jpg', 'jpeg', 'png', 'gif']);
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
      toast(context, '预览图已更新为 $name');
    }
  }

  Widget _bbBtn(String label, String open, String close) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(36, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact),
      onPressed: () {
        final sel = _descCtrl.selection;
        final text = _descCtrl.text;
        final start = sel.isValid ? sel.start : text.length;
        final end = sel.isValid ? sel.end : text.length;
        final inner = text.substring(start, end);
        _descCtrl.value = TextEditingValue(
          text: text.substring(0, start) +
              open +
              inner +
              close +
              text.substring(end),
          selection: TextSelection(
              baseOffset: start + open.length,
              extentOffset: start + open.length + inner.length),
        );
        _saveDraftSoon();
      },
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildSide(Mod mod, WorkshopItemRemote? target, String? targetId,
      bool isNew, String wsVersion, bool verOk) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final plan = _plan;

    return Column(
      children: [
        SectionCard(
          title: '预览图',
          subtitle: 'JPG/PNG/GIF · 小于 1 MB',
          trailing: TextButton(
            onPressed: () => _pickPreview(mod),
            child: const Text('更换…'),
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
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant)),
                  ],
                );

            Widget placeholder(IconData icon) => Container(
                  width: 64,
                  height: 64,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(icon,
                      size: 20, color: scheme.onSurfaceVariant),
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
                '工坊当前',
              ));
              slots.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward,
                    size: 16, color: scheme.onSurfaceVariant),
              ));
            }

            if (pv == null) {
              slots.add(slot(placeholder(Icons.image_not_supported_outlined),
                  '本地(缺失)'));
              return Row(children: [
                ...slots,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '未找到本地预览图 —— 放一张 preview.jpg 进模组文件夹,或点右上「更换…」',
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
              '本地(将上传)',
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
                        okSize ? '✓ 小于 1 MB 上限' : '✗ 超过 1 MB,Steam 会拒收',
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
          title: '将要上传',
          subtitle: '点击文件可切换上传/忽略,选择存入 dstpub.json',
          trailing: IconButton(
            tooltip: '重新扫描',
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
                      '${humanSize(plan.totalSize)} · ${plan.kept.length} 项'
                      ' · 忽略 ${plan.dropped.length} 项'
                      '${plan.overLimit ? ' · 体积较大,上传耗时较长' : ''}',
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
          title: '发布',
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
                          toast(context, '至少给主语言填一个标题');
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
                                    _draftStamp = '已发布 · 草稿已清除');
                                toast(context,
                                    '已发布 ${mod.info.name} v${_verCtrl.text}');
                              }
                            }
                          },
                icon: const Icon(Icons.upload),
                label: Text(state.busy
                    ? '发布中…'
                    : isNew ? '发布(新建条目)' : '更新到创意工坊'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed:
                    state.busy ? null : () => state.dryRun(mod),
                child: const Text('Dry-run:只演练,不上传'),
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
                    '上传失败:${state.failNote}\n'
                    '所有编辑内容与草稿完好,修复后直接重试。',
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
                  '等效命令行:\ndstpub upload ./${mod.folderName} '
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
