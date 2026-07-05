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
    final totalSubs =
        state.remoteItems.fold<int>(0, (a, it) => a + it.subs);

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
          subtitle: state.engine == 'steamworks'
              ? (state.steamReady
                  ? 'Steamworks 引擎 · 开着 Steam 即可发布,免账号免密码'
                  : '未找到 Steamworks 助手 —— 请使用完整发行包,或到设置页切换引擎')
              : (state.steamReady
                  ? '${state.steamUser} · steamcmd 已找到 · 凭据依赖本机缓存'
                  : '到设置页配置 steamcmd 路径与 Steam 账号'),
          trailing: Icon(
            state.steamReady ? Icons.check_circle : Icons.error_outline,
            color: state.steamReady ? sem.success : scheme.error,
          ),
          child: Row(
            children: [
              _Stat(label: '本地文件夹', value: '${state.mods.length}'),
              _Stat(label: '名下工坊条目', value: '${state.remoteItems.length}'),
              _Stat(
                  label: '总订阅', value: '${totalSubs}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '快速开始',
          subtitle: '发布目标与内容文件夹在发布页各自选择,无需预先绑定',
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => state.goto(AppState.publishPageIndex),
                icon: const Icon(Icons.upload),
                label: const Text('去发布'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => state.goto(1),
                icon: const Icon(Icons.public),
                label: const Text('查看名下条目'),
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
