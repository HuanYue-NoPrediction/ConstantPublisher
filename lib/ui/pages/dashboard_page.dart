import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets/bits.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final dirty = state.mods.where((m) => m.dirty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text('仪表盘', style: Theme.of(context).textTheme.headlineSmall),
        Text('Steam 工坊发布环境一览',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        // 环境状态卡
        SectionCard(
          title: state.steamReady ? '发布环境就绪' : '发布环境未配置',
          subtitle: state.steamReady
              ? '${state.steamUser} · steamcmd 已找到 · 凭据依赖本机缓存'
              : '到设置页配置 steamcmd 路径与 Steam 账号',
          trailing: Icon(
            state.steamReady ? Icons.check_circle : Icons.error_outline,
            color: state.steamReady ? sem.success : scheme.error,
          ),
          child: Row(
            children: [
              _Stat(label: '本地模组', value: '${state.mods.length}'),
              _Stat(
                  label: '已关联工坊',
                  value: '${state.mods.where((m) => m.linked).length}'),
              _Stat(label: '待发布', value: '${dirty.length}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 待发布列表
        SectionCard(
          title: '待发布',
          subtitle: '本地版本比上次发布新、或从未发布的模组',
          child: dirty.isEmpty
              ? Text('全部同步,无事可做 🎉',
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final m in dirty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.info.name.isEmpty
                            ? m.folderName
                            : m.info.name),
                        subtitle: Text(
                          m.linked
                              ? '${m.pub.lastPublishedVersion ?? '?'} → ${m.info.version}'
                              : '首次发布 · v${m.info.version}',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => state.selectAndGoPublish(m),
                          child: Text(m.linked ? '去发布' : '首次发布'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        if (state.busy && state.progress != null)
          SectionCard(
            title: '发布进行中',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.progress!.stage),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: state.progress!.progress),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600)),
            Text(label,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
