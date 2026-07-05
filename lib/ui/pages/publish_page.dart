import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/mod.dart';
import '../../services/draft_store.dart';
import '../../services/stager.dart';
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

  String? _modPath; // 当前表单对应的模组
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

  /// 模组切换时:重置为该模组默认值,再叠加草稿。
  Future<void> _loadFor(Mod mod) async {
    _modPath = mod.path;
    _verCtrl.text = mod.info.version;
    _descCtrl.text = mod.info.description;
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
    if (mounted && _modPath == mod.path) setState(() => _plan = plan);
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  void _saveDraftSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final path = _modPath;
    if (path == null) return;
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

    if (mod == null) {
      return Center(
        child: Text('先到「模组」页选择 mods 目录',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    if (_modPath != mod.path) {
      // 切换了模组:异步加载默认值+草稿
      _modPath = mod.path;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFor(mod));
    }

    final last = mod.pub.lastPublishedVersion;
    final verOk = _verCtrl.text.isNotEmpty &&
        (last == null || cmpVer(_verCtrl.text, last) > 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text('发布', style: Theme.of(context).textTheme.headlineSmall),
        Text(
          '${mod.folderName}/modinfo.lua · 本地 v${mod.info.version}'
          '${mod.linked ? ' · 条目 ${mod.pub.publishedFileId}(上次 v${last ?? '?'})' : ' · 未发布(将 CreateItem)'}',
          style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        // 模组切换 chips + 草稿状态
        Row(
          children: [
            Expanded(
              child: DropdownMenu<String>(
                key: ValueKey(mod.path),
                initialSelection: mod.path,
                leadingIcon: const Icon(Icons.extension_outlined),
                label: const Text('模组'),
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
                  if (m != null) state.select(m);
                },
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final dir = await getDirectoryPath();
                if (dir == null) return;
                final m = await state.addExternalFolder(dir);
                if (m != null) state.select(m);
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
          final form = _buildForm(mod, verOk, last);
          final side = _buildSide(mod, verOk);
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

  Widget _buildForm(Mod mod, bool verOk, String? last) {
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    return Column(
      children: [
        SectionCard(
          title: '版本',
          subtitle: '自动写回 modinfo.lua 的 version 字段',
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
                  _verCtrl.text = suggestBump(_verCtrl.text, last);
                  _onVersionChanged(_verCtrl.text);
                },
                child: Text('自增 → ${suggestBump(_verCtrl.text, last)}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  !mod.linked
                      ? '✓ 首次发布,将新建工坊条目'
                      : last == null
                          ? '⚠ 更新条目 ${mod.pub.publishedFileId},但工坊版本未知(老条目无版本元数据)—— 请确认大于线上版本;本次发布后将自动记录'
                          : verOk
                              ? '✓ 大于工坊当前 $last'
                              : '✕ 需大于工坊当前 $last(自增按两者较高版本计算)',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: !mod.linked
                          ? sem.success
                          : last == null
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
          subtitle: '由版本号自动判定(含 beta/rc/alpha 字样时切换),可手动覆盖 —— 映射为工坊标签',
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
          title: '简介(工坊详情页)',
          subtitle: 'BBCode 排版,写入 SetItemDescription —— 与更新日志是两回事',
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
          subtitle: '随 SubmitItemUpdate 写入 Steam「更新记录」,订阅者可见 —— 官方工具没有',
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
          subtitle: 'ERemoteStoragePublishedFileVisibility',
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
          subtitle: 'Steamworks 引擎走 SetItemTags,可靠生效;steamcmd 引擎下不保证',
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

  Widget _buildSide(Mod mod, bool verOk) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final plan = _plan;

    return Column(
      children: [
        SectionCard(
          title: '预览图',
          subtitle: '工坊封面 · JPG/PNG/GIF · 需小于 1 MB',
          trailing: TextButton(
            onPressed: () => _pickPreview(mod),
            child: const Text('更换…'),
          ),
          child: Builder(builder: (context) {
            final pv = mod.preview;
            final wsItem = mod.linked
                ? state.remoteItems
                    .where((x) => x.id == mod.pub.publishedFileId)
                    .firstOrNull
                : null;

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
            if (mod.linked) {
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
          subtitle: '干净暂存副本 · .modignore 与默认规则已生效',
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
                onPressed: state.busy || !verOk && mod.linked
                    ? null
                    : () async {
                        final ok = await state.publish(
                          mod: mod,
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
                label: Text(state.busy ? '发布中…' : '发布到创意工坊'),
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
