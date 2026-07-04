import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogLevel? _filter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sem = SemanticColors.of(context);
    final items = _filter == null
        ? state.logs
        : state.logs.where((l) => l.level == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('日志', style: Theme.of(context).textTheme.headlineSmall),
              Text('发布过程与 steamcmd 输出 · EResult 自动翻译',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (label, lv) in [
                    ('全部', null),
                    ('信息', LogLevel.info),
                    ('警告', LogLevel.warn),
                    ('错误', LogLevel.error),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(label),
                        selected: _filter == lv,
                        onSelected: (_) => setState(() => _filter = lv),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: state.clearLogs,
                    child: const Text('清空'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: scheme.outlineVariant),
            itemBuilder: (context, i) {
              final l = items[i];
              final (bg, fg, label) = switch (l.level) {
                LogLevel.info => (
                    scheme.secondaryContainer,
                    scheme.onSecondaryContainer,
                    'INFO'
                  ),
                LogLevel.warn =>
                  (sem.warnContainer, sem.onWarnContainer, 'WARN'),
                LogLevel.error =>
                  (scheme.errorContainer, scheme.onErrorContainer, 'ERROR'),
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.time.hour.toString().padLeft(2, '0')}:${l.time.minute.toString().padLeft(2, '0')}:${l.time.second.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: fg)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l.message,
                          style: const TextStyle(
                              fontSize: 12.5, fontFamily: 'monospace')),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
