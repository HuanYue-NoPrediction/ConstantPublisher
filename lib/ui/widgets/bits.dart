import 'package:flutter/material.dart';

import '../../theme.dart';

/// 状态小徽章:已同步 / 本地已改 / 未发布。
enum BadgeKind { ok, warn, muted }

class StatusBadge extends StatelessWidget {
  final String text;
  final BadgeKind kind;
  const StatusBadge(this.text, this.kind, {super.key});

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (kind) {
      BadgeKind.ok => (sem.successContainer, sem.onSuccessContainer),
      BadgeKind.warn => (sem.warnContainer, sem.onWarnContainer),
      BadgeKind.muted => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// 统一的卡片段落:标题 + 说明 + 内容。
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 13),
            child,
          ],
        ),
      ),
    );
  }
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(2)} MB';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
