import 'package:flutter/material.dart';

/// 极简 BBCode 预览:支持 [h1] [b] [i] [u] [strike] [list][*] [url=] [img] [spoiler] [hr]。
/// 只求"排版长什么样"一目了然,不追求与 Steam 渲染逐像素一致。
class BBCodePreview extends StatelessWidget {
  final String source;
  const BBCodePreview(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocks = <Widget>[];
    // 先把块级标签拆出来:h1 / list / hr,其余按段落走内联解析。
    final text = source.replaceAll('\r\n', '\n');
    final pattern = RegExp(
        r'\[h1\]([\s\S]*?)\[\/h1\]|\[list\]([\s\S]*?)\[\/list\]|\[hr\]',
        caseSensitive: false);
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        blocks.add(_para(context, text.substring(cursor, m.start)));
      }
      if (m.group(1) != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(m.group(1)!.trim(),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ));
      } else if (m.group(2) != null) {
        for (final item in m.group(2)!.split('[*]')) {
          final t = item.trim();
          if (t.isEmpty) continue;
          blocks.add(Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  '),
              Expanded(child: _inline(context, t)),
            ]),
          ));
        }
      } else {
        blocks.add(Divider(color: scheme.outlineVariant));
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      blocks.add(_para(context, text.substring(cursor)));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  Widget _para(BuildContext context, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _inline(context, t),
    );
  }

  /// 内联标签 → TextSpan。逐个匹配最先出现的标签,递归处理内部。
  Widget _inline(BuildContext context, String text) {
    return Text.rich(TextSpan(children: _spans(context, text)),
        style: const TextStyle(fontSize: 13.5, height: 1.55));
  }

  List<InlineSpan> _spans(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    final tags = <(RegExp, TextStyle Function())>[
      (RegExp(r'\[b\]([\s\S]*?)\[\/b\]', caseSensitive: false),
          () => const TextStyle(fontWeight: FontWeight.w700)),
      (RegExp(r'\[i\]([\s\S]*?)\[\/i\]', caseSensitive: false),
          () => const TextStyle(fontStyle: FontStyle.italic)),
      (RegExp(r'\[u\]([\s\S]*?)\[\/u\]', caseSensitive: false),
          () => const TextStyle(decoration: TextDecoration.underline)),
      (RegExp(r'\[strike\]([\s\S]*?)\[\/strike\]', caseSensitive: false),
          () => const TextStyle(decoration: TextDecoration.lineThrough)),
    ];

    // 特殊标签
    final url =
        RegExp(r'\[url=([^\]]*)\]([\s\S]*?)\[\/url\]', caseSensitive: false);
    final img = RegExp(r'\[img\]([\s\S]*?)\[\/img\]', caseSensitive: false);
    final spoiler =
        RegExp(r'\[spoiler\]([\s\S]*?)\[\/spoiler\]', caseSensitive: false);

    // 找最先出现的任意标签
    Match? first;
    TextStyle Function()? style;
    var kind = '';
    for (final (re, st) in tags) {
      final m = re.firstMatch(text);
      if (m != null && (first == null || m.start < first.start)) {
        first = m;
        style = st;
        kind = 'style';
      }
    }
    for (final (re, k) in [(url, 'url'), (img, 'img'), (spoiler, 'spoiler')]) {
      final m = re.firstMatch(text);
      if (m != null && (first == null || m.start < first.start)) {
        first = m;
        kind = k;
      }
    }

    if (first == null) return [TextSpan(text: text)];

    final before = text.substring(0, first.start);
    final after = text.substring(first.end);
    final spans = <InlineSpan>[];
    if (before.isNotEmpty) spans.add(TextSpan(text: before));

    switch (kind) {
      case 'style':
        spans.add(TextSpan(
            style: style!(),
            children: _spans(context, first.group(1) ?? '')));
      case 'url':
        spans.add(TextSpan(
            text: first.group(2) ?? '',
            style: TextStyle(
                color: scheme.primary,
                decoration: TextDecoration.underline)));
      case 'img':
        spans.add(WidgetSpan(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('图片(发布后显示):${first.group(1)}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant)),
          ),
        ));
      case 'spoiler':
        spans.add(TextSpan(
            text: first.group(1) ?? '',
            style: TextStyle(
                backgroundColor: scheme.onSurface,
                color: scheme.onSurface)));
    }

    spans.addAll(_spans(context, after));
    return spans;
  }
}
