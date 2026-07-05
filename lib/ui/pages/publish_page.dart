import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/mod.dart';
import '../../services/draft_store.dart';
import '../../services/stager.dart';
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

class _PublishPageState extends State<PublishPage> {
  final _verCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  String _channel = 'release';
  bool _manualChannel = false;
  int _visibility = 0;
  List<String> _tags = [];
  bool _descPreview = false;

  String _loadedKey = ''; // '内容路径|目标id',变化时重载表单
  String _contentPath = '';
  Timer? _debounce;
  String _draftStamp = '编辑内容会自动保存为草稿 —— 上传失败也不会丢';
  StagePlan? _plan;

  @override
  void dispose() {
    _debounce?.cancel();
    _verCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  /// 内容文件夹或发布目标变化时:重置默认值,再叠加草稿。
  Future<void> _loadFor(Mod mod, WorkshopItemRemote? target) async {
    _contentPath = mod.path;
    _verCtrl.text = mod.info.version;
    // 更新已发布条目时,简介默认取工坊现有全文(在其基础上改),否则用本地 modinfo
    _descCtrl.text = (target != null && target.description.isNotEmpty)
        ? target.description
        : mod.info.description;
    _noteCtrl.text = '';
    _tags = List.of(mod.pub.tags);
    _visibility = mod.pub.visibility;
    _manualChannel = false;
    _channel = detectChannel(mod.info.version);
    _plan = null;

    final d = await DraftStore.load(mod.path);
    if (d != null) {
      _verCtrl.text = d.version.isEmpty ? _verCtrl.text : d.version;
      _channel = d.channel;
      _manualChannel = d.manualChannel;
      _visibility = d.visibility;
      _tags = List.of(d.tags);
      if (d.changeNote.isNotEmpty) _noteCtrl.text = d.changeNote;
      if (d.description.isNotEmpty) _descCtrl.text = d.description;
      _draftStamp =
          '草稿已恢复(保存于 ${_fmtTime(d.savedAt)})';
    } else {
      _draftStamp = '编辑内容会自动保存为草稿 —— 上传失败也不会丢';
    }
    _refreshPlan(mod);
    if (mounted) setState(() {});
  }

  Future<void> _refreshPlan(Mod mod) async {
    final plan = await planStage(mod);
    if (mounted && _contentPath == mod.path) setState(() => _plan = plan);
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
    final d = Draft(
      version: _verCtrl.text,
      channel: _channel,
      visibility: _visibility,
      tags: _tags,
      changeNote: _noteCtrl.text,
      description: _descCtrl.text,
      manualChannel: _manualChannel,
    );
    await DraftStore.save(path, d);
    if (mounted) {
      setState(() => _draftStamp = '已自动保存 ${_fmtTime(d.savedAt)}');
    }
  }

  void _onVersionChanged(String v) {
    if (!_manualChannel) {
      setState(() => _channel = detectChannel(v));
    }
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
                          '${m.info.name.isEmpty ? m.folderName : m.info.name} · ${m.folderName}/ (v${m.info.version})',
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
          title: '发布通道',
          subtitle: '由版本号自动判定,可手动覆盖',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'release', label: Text('正式版')),
              ButtonSegment(value: 'beta', label: Text('Beta')),
              ButtonSegment(value: 'alpha', label: Text('Alpha')),
            ],
            selected: {_channel},
            onSelectionChanged: (s) {
              setState(() {
                _channel = s.first;
                _manualChannel = true;
              });
              _saveDraftSoon();
            },
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '简介',
          subtitle: '工坊详情页正文 · 支持 BBCode',
          trailing: SegmentedButton<bool>(
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
          child: _descPreview
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
                        _bbBtn('列表', '[list]\n[*]', '\n[/list]'),
                        _bbBtn('链接', '[url=https://]', '[/url]'),
                        _bbBtn('图片', '[img]', '[/img]'),
                        _bbBtn('剧透', '[spoiler]', '[/spoiler]'),
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
    await File(f.path).copy(p.join(mod.path, name));
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
          subtitle: '已应用忽略规则',
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
                            for (final e in plan.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2.5),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(
                                      e.rel,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        decoration: e.skipped
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: e.skipped
                                            ? scheme.onSurfaceVariant
                                            : scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    e.skipped
                                        ? (e.reason ?? '')
                                        : humanSize(e.size),
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontFamily: 'monospace',
                                        color: e.skipped
                                            ? scheme.error
                                            : scheme.onSurfaceVariant),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${humanSize(plan.totalSize)} · ${plan.kept.length} 项'
                      ' · 忽略 ${plan.dropped.length} 项 · 上限 100 MB',
                      style: TextStyle(
                          fontSize: 12,
                          color: plan.overLimit
                              ? scheme.error
                              : scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: (plan.totalSize / StagePlan.steamLimit)
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
                onPressed:
                    state.busy || (!isNew && wsVersion.isNotEmpty && !verOk)
                        ? null
                        : () async {
                            final ok = await state.publish(
                              mod: mod,
                              targetId: targetId,
                              version: _verCtrl.text.trim(),
                              description: _descCtrl.text,
                              changeNote: _noteCtrl.text,
                              visibility: _visibility,
                              tags: List.of(_tags),
                            );
                            if (ok) {
                              await DraftStore.clear(mod.path);
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
                  '--set-version ${_verCtrl.text} --channel $_channel --yes',
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
