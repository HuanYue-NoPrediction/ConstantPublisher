import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/mod.dart';
import '../../state/app_state.dart';
import '../widgets/bits.dart';

class ModsPage extends StatelessWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final dir = await getDirectoryPath();
          if (dir != null) await state.setModsDir(dir);
        },
        icon: const Icon(Icons.folder_open),
        label: const Text('选择 mods 目录'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 90),
        children: [
          Text('模组', style: Theme.of(context).textTheme.headlineSmall),
          Text(
            state.modsDir.isEmpty
                ? '尚未选择 mods 目录 —— 点右下角选择(例如 …\\Don\'t Starve Together\\mods)'
                : '${state.modsDir} · ${state.mods.length} 个模组',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (final m in state.mods) ...[
            _ModCard(mod: m),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ModCard extends StatelessWidget {
  final Mod mod;
  const _ModCard({required this.mod});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final badge = !mod.linked
        ? const StatusBadge('未发布', BadgeKind.muted)
        : mod.dirty
            ? const StatusBadge('本地已改', BadgeKind.warn)
            : const StatusBadge('已同步', BadgeKind.ok);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.extension),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mod.info.name.isEmpty ? mod.folderName : mod.info.name,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${mod.folderName}/ · v${mod.info.version}'
                    '${mod.linked ? ' · 工坊 ${mod.pub.publishedFileId}' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            badge,
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: () => state.selectAndGoPublish(mod),
              child: Text(mod.linked ? '发布' : '首次发布'),
            ),
            PopupMenuButton<String>(
              onSelected: (act) async {
                switch (act) {
                  case 'dry':
                    await state.dryRun(mod);
                    if (context.mounted) {
                      toast(context, 'Dry-run 完成,清单见日志页');
                    }
                  case 'workshop':
                    if (mod.linked) {
                      launchUrl(Uri.parse(
                          'https://steamcommunity.com/sharedfiles/filedetails/?id=${mod.pub.publishedFileId}'));
                    }
                  case 'unbind':
                    await state.unbindItem(mod);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'dry', child: Text('Dry-run(不上传)')),
                if (mod.linked)
                  const PopupMenuItem(
                      value: 'workshop', child: Text('在工坊查看')),
                if (mod.linked)
                  const PopupMenuItem(value: 'unbind', child: Text('解除工坊绑定')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
