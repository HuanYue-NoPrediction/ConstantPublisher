import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/workshop_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
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
  var _tagsExpanded = false;
  final Set<String> _tagFilter = {};

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

    // 标签统计与筛选(像 Steam 工坊侧边栏那样)
    final tagCounts = <String, int>{};
    for (final it in state.remoteItems) {
      for (final t in it.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    _tagFilter.removeWhere((t) => !tagCounts.containsKey(t));
    final sortedTags = tagCounts.keys.toList()
      ..sort((a, b) => tagCounts[b]!.compareTo(tagCounts[a]!));
    // 多选 = 交集筛选,与 Steam 工坊侧边栏一致
    final filteredRemote = _tagFilter.isEmpty
        ? state.remoteItems
        : state.remoteItems
            .where((it) => _tagFilter.every(it.tags.contains))
            .toList();

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
                  Text('你账号名下的全部模组 —— 点「更新」选内容文件夹即可发布,无需预先绑定',
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
          title: '账号名下条目',
          subtitle: 'Steamworks 引擎下零配置直查(开着 Steam 即可);steamcmd 引擎才需要 Web API Key',
          child: state.remoteItems.isEmpty
              ? Text('尚未拉取,或未配置 API Key',
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sortedTags.isNotEmpty) ...[
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          FilterChip(
                            label: Text('全部 (${state.remoteItems.length})'),
                            selected: _tagFilter.isEmpty,
                            onSelected: (_) =>
                                setState(() => _tagFilter.clear()),
                          ),
                          // 折叠:默认前 8 个,选中的永远可见
                          for (final t in _tagsExpanded
                              ? sortedTags
                              : sortedTags
                                  .where((t) =>
                                      _tagFilter.contains(t) ||
                                      sortedTags.indexOf(t) < 8)
                                  .toList())
                            FilterChip(
                              label: Text('$t (${tagCounts[t]})'),
                              selected: _tagFilter.contains(t),
                              onSelected: (on) => setState(() {
                                if (on) {
                                  _tagFilter.add(t);
                                } else {
                                  _tagFilter.remove(t);
                                }
                              }),
                            ),
                          if (sortedTags.length > 8)
                            ActionChip(
                              label: Text(_tagsExpanded
                                  ? '收起'
                                  : '+${sortedTags.length - 8} 更多'),
                              onPressed: () => setState(
                                  () => _tagsExpanded = !_tagsExpanded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final it in filteredRemote)
                      _remoteRow(state, scheme, it),
                  ],
                ),
        ),
      ],
    );
  }
}

extension on _WorkshopPageState {
  String _shortDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 远端条目行:标题 + id 在左;订阅/时间/绑定状态用图标靠右;每行都可「更新」。
  Widget _remoteRow(AppState state, ColorScheme scheme, WorkshopItemRemote it) {
    final sem = SemanticColors.of(context);
    final bound =
        state.mods.where((m) => m.pub.publishedFileId == it.id).firstOrNull;
    final dim = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: it.previewUrl.isEmpty
                ? Container(
                    width: 44,
                    height: 44,
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.cloud_outlined,
                        size: 20, color: scheme.onSurfaceVariant),
                  )
                : Image.network(
                    it.previewUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, prog) => prog == null
                        ? child
                        : Container(
                            width: 44,
                            height: 44,
                            color: scheme.surfaceContainerHighest,
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.cloud_off_outlined,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text('id ${it.id}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: '订阅数',
            child: Row(children: [
              Icon(Icons.people_alt_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text('${it.subs}', style: dim),
            ]),
          ),
          if (it.updated != null) ...[
            const SizedBox(width: 14),
            Tooltip(
              message: '最近更新',
              child: Row(children: [
                Icon(Icons.schedule, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(_shortDate(it.updated!.toLocal()), style: dim),
              ]),
            ),
          ],
          const SizedBox(width: 14),
          Tooltip(
            message: bound != null
                ? '已绑定 ${bound.folderName}/'
                : '未绑定本地文件夹(点「更新」时选择)',
            child: Icon(
              bound != null ? Icons.link : Icons.link_off,
              size: 16,
              color: bound != null ? sem.success : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact),
            onPressed: () => _updateItem(state, it),
            child: const Text('更新'),
          ),
        ],
      ),
    );
  }

  /// 更新:把该条目设为发布目标,内容文件夹默认沿用上次(或当前),到发布页再选。
  void _updateItem(AppState state, WorkshopItemRemote it) {
    final guess =
        state.mods.where((m) => m.pub.publishedFileId == it.id).firstOrNull ??
            state.current;
    state.startPublish(content: guess, targetId: it.id);
  }
}
