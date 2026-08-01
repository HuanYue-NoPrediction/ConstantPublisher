import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/gen/app_localizations.dart';
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
        state.refreshRemote().then((_) => state.fetchTrending());
      } else if (state.trending.isEmpty && state.steamReady && !state.busy) {
        state.fetchTrending();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final t = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text(t.dashTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (state.update != null) ...[
          SectionCard(
            icon: Icons.system_update_alt,
            title: t.updateFoundTitle(state.update!.version),
            subtitle: t.updateFoundSubtitle(
                state.srcName(state.update!.source), kAppVersion),
            trailing: Icon(Icons.system_update, color: scheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  FilledButton.icon(
                    onPressed: state.busy ? null : state.startUpdate,
                    icon: const Icon(Icons.download),
                    label: Text(t.updateNow),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: state.dismissUpdate,
                    child: Text(t.updateDismiss),
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
          title: state.steamReady ? t.envReady : t.envNotReady,
          subtitle: state.engine == 'steamworks'
              ? (state.steamReady ? t.envSwOk : t.envSwMissing)
              : (state.steamReady
                  ? t.envCmdOk(state.steamUser)
                  : t.envCmdNeed),
          trailing: Icon(
            state.steamReady ? Icons.check_circle : Icons.error_outline,
            color: state.steamReady ? sem.success : scheme.error,
          ),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => state.goto(AppState.publishPageIndex),
                icon: const Icon(Icons.upload),
                label: Text(t.goPublish),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  state.refreshRemote().then((_) => state.fetchTrending());
                  if (state.news.isEmpty) state.fetchNews();
                },
                icon: const Icon(Icons.refresh),
                label: Text(t.refreshData),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 公告栏:饥荒官方动态(游戏更新往往意味着模组要适配)
        SectionCard(
          icon: Icons.campaign_outlined,
          title: t.newsTitle,
          hint: t.newsSubtitle,
          child: state.news.isEmpty
              ? Text(t.newsLoading,
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
                            Text(_ago(t, n.date),
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
          icon: Icons.groups_2_outlined,
          title: t.groupsTitle,
          subtitle: t.groupsSubtitle,
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final (name, num) in kQqGroups)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: num));
                    toast(context, t.groupCopied(num));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipOval(
                          child: Image.network(
                            'https://p.qlogo.cn/gh/$num/$num/100',
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.groups_outlined,
                                size: 28,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(t.groupNumberHint(num),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        SectionCard(
          icon: Icons.local_fire_department_outlined,
          title: t.trendTitle,
          hint: t.trendHint,
          child: state.trending.isEmpty
              ? Text(
                  state.steamReady ? t.trendLoading : t.rankHintNoSteam,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              : Column(
                  children: [
                    for (final (i, it) in state.trending.indexed)
                      _TrendRow(index: i + 1, item: it, scheme: scheme),
                  ],
                ),
        ),

        if (state.busy && state.progress != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            icon: Icons.cloud_upload_outlined,
            title: t.publishingTitle,
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

String _ago(AppLocalizations t, DateTime time) {
  final d = DateTime.now().difference(time);
  if (d.inDays >= 30) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
  if (d.inDays >= 1) return t.agoDays('${d.inDays}');
  if (d.inHours >= 1) return t.agoHours('${d.inHours}');
  return t.agoJustNow;
}

class _TrendRow extends StatelessWidget {
  final int index;
  final WorkshopItemRemote item;
  final ColorScheme scheme;
  const _TrendRow(
      {required this.index, required this.item, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()]);
    final hot = index <= 3;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openSteamPage(
          'https://steamcommunity.com/sharedfiles/filedetails/?id=${item.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: hot ? 15 : 12.5,
                  fontWeight: hot ? FontWeight.w800 : FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: hot ? scheme.primary : scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
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
            if (item.votesUp + item.votesDown > 0)
              _stat(
                  Icons.thumb_up_outlined,
                  '${(item.votesUp / (item.votesUp + item.votesDown) * 100).round()}%',
                  dim),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
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
