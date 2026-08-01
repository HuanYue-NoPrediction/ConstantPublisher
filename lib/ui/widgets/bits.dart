import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';

Future<void> openSteamPage(String url) async {
  try {
    if (await launchUrl(Uri.parse('steam://openurl/$url'))) return;
  } catch (_) {}
  await launchUrl(Uri.parse(url));
}

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
  final IconData? icon;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.icon,
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 16, color: scheme.primary),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .1,
                              height: 1.3)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: scheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 14),
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
