import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/mod.dart';
import '../../state/app_state.dart';
import '../widgets/bits.dart';

/// 工坊页:巡检 + 绑定管理。
/// 原则:此列表只是视图,发布真相源是每个模组文件夹里的 dstpub.json。
class WorkshopPage extends StatefulWidget {
  const WorkshopPage({super.key});

  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage> {
  var _autoFetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoFetched) {
      _autoFetched = true;
      final state = context.read<AppState>();
      if (state.engine == 'steamworks' &&
          state.steamReady &&
          state.remoteItems.isEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => state.refreshRemote());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final linked = state.mods.where((m) => m.linked).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('工坊条目',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text('绑定关系以本地 dstpub.json 为准;远端列表仅用于巡检与导入',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: state.refreshRemote,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('从 Steam 拉取'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '已绑定',
          subtitle: '这些文件夹的 dstpub.json 里有条目 id',
          child: linked.isEmpty
              ? Text('还没有绑定任何条目 —— 首次发布会自动建立,或用下方手动绑定',
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final m in linked)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link),
                        title: Text(m.info.name),
                        subtitle: Text(
                            '条目 ${m.pub.publishedFileId} ← ${m.folderName}/ · 上次发布 v${m.pub.lastPublishedVersion ?? '?'}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => launchUrl(Uri.parse(
                                  'https://steamcommunity.com/sharedfiles/filedetails/?id=${m.pub.publishedFileId}')),
                              child: const Text('查看'),
                            ),
                            FilledButton.tonal(
                              onPressed: () => state.selectAndGoPublish(m),
                              child: const Text('更新'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        // 手动绑定:新文件夹更新老条目的入口
        SectionCard(
          title: '绑定 / 换绑',
          subtitle:
              '从名下条目里直接选,绑到任意本地文件夹 —— 重写版、换机器后的新目录都走这里;旧绑定会自动解除',
          child: const _BindForm(),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '账号名下条目(远端巡检)',
          subtitle: 'Steamworks 引擎下零配置直查(开着 Steam 即可);steamcmd 引擎才需要 Web API Key',
          child: state.remoteItems.isEmpty
              ? Text('尚未拉取,或未配置 API Key',
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final it in state.remoteItems)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_outlined),
                        title: Text(it.title),
                        subtitle: Text(
                            'id ${it.id} · 订阅 ${it.subs}'
                            '${it.updated != null ? ' · 更新于 ${it.updated!.toLocal().toString().substring(0, 16)}' : ''}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12)),
                        trailing: state.mods.any(
                                (m) => m.pub.publishedFileId == it.id)
                            ? const StatusBadge('已绑定', BadgeKind.ok)
                            : const StatusBadge('未绑定本地', BadgeKind.warn),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BindForm extends StatefulWidget {
  const _BindForm();

  @override
  State<_BindForm> createState() => _BindFormState();
}

class _BindFormState extends State<_BindForm> {
  final _idCtrl = TextEditingController();
  String? _selectedId;
  String? _targetPath;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final remote = state.remoteItems;
    // 值用 String(id / 路径)而非对象引用,列表重建后选中项依然有效
    if (_selectedId != null && !remote.any((it) => it.id == _selectedId)) {
      _selectedId = null;
    }
    if (_targetPath != null && !state.mods.any((m) => m.path == _targetPath)) {
      _targetPath = null;
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: remote.isEmpty
              ? TextField(
                  controller: _idCtrl,
                  decoration: const InputDecoration(
                    labelText: '工坊条目 id(点「从 Steam 拉取」后可直接下拉选)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )
              : DropdownButtonFormField<String>(
                  value: _selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '选择工坊条目',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final it in remote)
                      DropdownMenuItem(
                        value: it.id,
                        child: Text(
                          '${state.mods.any((m) => m.pub.publishedFileId == it.id) ? '〔已绑定〕' : ''}'
                          '${it.title} · ${it.subs} 订阅',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedId = v),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: _targetPath,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '绑定到本地文件夹',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final m in state.mods)
                DropdownMenuItem(
                  value: m.path,
                  child: Text('${m.folderName}/ (v${m.info.version})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _targetPath = v),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () async {
            final id = remote.isEmpty ? _idCtrl.text.trim() : (_selectedId ?? '');
            final target = state.mods
                .where((m) => m.path == _targetPath)
                .firstOrNull;
            if (id.isEmpty || int.tryParse(id) == null || target == null) {
              toast(context, '请选择工坊条目和本地文件夹');
              return;
            }
            await state.bindItem(target, id);
            if (context.mounted) {
              toast(context, '已绑定,「发布」即上传该文件夹内容到条目 $id');
            }
          },
          child: const Text('绑定'),
        ),
      ],
    );
  }
}
