import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/workshop_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../version.dart';
import '../widgets/bits.dart';

const List<(String, String)> kQqGroups = [
  ('饥荒MOD动画_Anim研究所', '1018104063'),
  ('饥荒mod制作-五年一班', '620984175'),
];

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    // 进入即自动拉取(数据为空且环境就绪时),无需手点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.remoteItems.isEmpty && state.steamReady && !state.busy) {
        state.refreshRemote();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final items = state.remoteItems;
    final top = [...items]..sort((a, b) => b.subs.compareTo(a.subs));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text('仪表盘', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (state.update != null) ...[
          SectionCard(
            title: '发现新版本 v${state.update!.version}',
            subtitle:
                '来源:${state.update!.source} · 当前 v$kAppVersion · 更新完成后自动重启',
            trailing: Icon(Icons.system_update, color: scheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  FilledButton.icon(
                    onPressed: state.busy ? null : state.startUpdate,
                    icon: const Icon(Icons.download),
                    label: const Text('立即更新'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: state.dismissUpdate,
                    child: const Text('本次忽略'),
                  ),
                ]),
                if (state.updateStage != null) ...[
                  const SizedBox(height: 12),
                  Text(state.updateStage!,
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: state.updateProgress),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 环境状态
        SectionCard(
          title: state.steamReady ? '发布环境就绪' : '发布环境未配置',
          subtitle: state.engine == 'steamworks'
              ? (state.steamReady
                  ? 'Steamworks 引擎 · 开着 Steam 即可发布'
                  : '未找到 Steamworks 助手 —— 请使用完整发行包,或到设置页切换引擎')
              : (state.steamReady
                  ? '${state.steamUser} · steamcmd 已配置'
                  : '到设置页配置 steamcmd 路径与 Steam 账号'),
          trailing: Icon(
            state.steamReady ? Icons.check_circle : Icons.error_outline,
            color: state.steamReady ? sem.success : scheme.error,
          ),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => state.goto(AppState.publishPageIndex),
                icon: const Icon(Icons.upload),
                label: const Text('去发布'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: state.refreshRemote,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新数据'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 公告栏:饥荒官方动态(游戏更新往往意味着模组要适配)
        SectionCard(
          title: '公告栏 · 饥荒官方动态',
          subtitle: '游戏更新可能影响模组兼容;点击在 Steam 中查看',
          child: state.news.isEmpty
              ? Text('动态加载中…(拉取不到时检查网络)',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final n in state.news.take(5))
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => openSteamPage(n.url),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Icon(Icons.campaign_outlined,
                                size: 15, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_ago(n.date),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
                          ]),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        SectionCard(
          title: '交流群',
          subtitle: '点击复制群号,到 QQ 搜索加入',
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final (name, num) in kQqGroups)
                ActionChip(
                  avatar: ClipOval(
                    child: Image.network(
                      'https://p.qlogo.cn/gh/$num/$num/100',
                      width: 18,
                      height: 18,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.groups_outlined, size: 16),
                    ),
                  ),
                  label: Text('$name · $num'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: num));
                    toast(context, '群号已复制:$num');
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (items.isEmpty)
          SectionCard(
            title: '模组排行',
            child: Text(
              state.steamReady
                  ? '点上方「刷新数据」拉取名下工坊条目'
                  : '连接 Steam 后即可查看名下模组数据',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SectionCard(
            title: '模组排行',
            subtitle: '按订阅数,共 ${items.length} 个',
            child: Column(
              children: [
                for (final it in top.take(6))
                  _RankRow(item: it, scheme: scheme, sem: sem),
              ],
            ),
          ),

        if (state.busy && state.progress != null) ...[
          const SizedBox(height: 14),
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
      ],
    );
  }

}

String _fmt(int n) {
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inDays >= 30) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
  if (d.inDays >= 1) return '${d.inDays} 天前';
  if (d.inHours >= 1) return '${d.inHours} 小时前';
  return '刚刚';
}

class _RankRow extends StatelessWidget {
  final WorkshopItemRemote item;
  final ColorScheme scheme;
  final SemanticColors sem;
  const _RankRow(
      {required this.item, required this.scheme, required this.sem});

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: item.previewUrl.isEmpty
                ? Container(
                    width: 38,
                    height: 38,
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.cloud_outlined,
                        size: 18, color: scheme.onSurfaceVariant))
                : Image.network(item.previewUrl,
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 38,
                        height: 38,
                        color: scheme.surfaceContainerHighest)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          _stat(Icons.people_alt_outlined, _fmt(item.subs), dim),
          const SizedBox(width: 12),
          _stat(Icons.mode_comment_outlined, _fmt(item.comments), dim),
          const SizedBox(width: 12),
          if (item.votesUp + item.votesDown > 0)
            _stat(
                Icons.thumb_up_outlined,
                '${(item.votesUp / (item.votesUp + item.votesDown) * 100).round()}%',
                dim),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '在工坊查看评论',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_new, size: 16),
            onPressed: () => openSteamPage(
                'https://steamcommunity.com/sharedfiles/filedetails/comments/${item.id}'),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String v, TextStyle style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: style.color),
          const SizedBox(width: 3),
          Text(v, style: style),
        ],
      );
}
