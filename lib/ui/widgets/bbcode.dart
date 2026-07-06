import 'package:flutter/material.dart';

class BBCodePreview extends StatelessWidget {
  final String source;
  const BBCodePreview(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocks = <Widget>[];
    final text = source.replaceAll('\r\n', '\n');
    final pattern = RegExp(
        r'\[(h[123])\]([\s\S]*?)\[\/\1\]'
        r'|\[(list|olist)\]([\s\S]*?)\[\/\3\]'
        r'|\[code\]([\s\S]*?)\[\/code\]'
        r'|\[quote(?:=([^\]]*))?\]([\s\S]*?)\[\/quote\]'
        r'|\[table[^\]]*\]([\s\S]*?)\[\/table\]'
        r'|\[previewyoutube=([^\];]*)[^\]]*\][\s\S]*?\[\/previewyoutube\]'
        r'|\[noparse\]([\s\S]*?)\[\/noparse\]'
        r'|\[hr\](?:\[\/hr\])?',
        caseSensitive: false);
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        blocks.add(_para(context, text.substring(cursor, m.start)));
      }
      if (m.group(1) != null) {
        final level = m.group(1)!.toLowerCase();
        final size = level == 'h1' ? 17.0 : (level == 'h2' ? 15.5 : 14.0);
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(m.group(2)!.trim(),
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
        ));
      } else if (m.group(3) != null) {
        final ordered = m.group(3)!.toLowerCase() == 'olist';
        var n = 0;
        for (final item in m.group(4)!.split('[*]')) {
          final t = item.trim();
          if (t.isEmpty) continue;
          n++;
          blocks.add(Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 24, child: Text(ordered ? '$n.' : '•')),
              Expanded(child: _inline(context, t)),
            ]),
          ));
        }
      } else if (m.group(5) != null) {
        blocks.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(m.group(5)!.trim(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
        ));
      } else if (m.group(7) != null) {
        blocks.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((m.group(6) ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${m.group(6)} 发表:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                ),
              _inline(context, m.group(7)!.trim()),
            ],
          ),
        ));
      } else if (m.group(8) != null) {
        blocks.add(_table(context, m.group(8)!));
      } else if (m.group(9) != null) {
        blocks.add(_placeholder(context, '视频(发布后显示):${m.group(9)}'));
      } else if (m.group(10) != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(m.group(10)!,
              style: const TextStyle(fontSize: 13.5, height: 1.55)),
        ));
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

  Widget _table(BuildContext context, String body) {
    final scheme = Theme.of(context).colorScheme;
    final trRe = RegExp(r'\[tr\]([\s\S]*?)\[\/tr\]', caseSensitive: false);
    final cellRe =
        RegExp(r'\[(th|td)\]([\s\S]*?)\[\/\1\]', caseSensitive: false);
    final parsed = <List<(String, String)>>[];
    var cols = 0;
    for (final tr in trRe.allMatches(body)) {
      final cells = [
        for (final c in cellRe.allMatches(tr.group(1)!))
          (c.group(1)!.toLowerCase(), c.group(2)!.trim())
      ];
      if (cells.isEmpty) continue;
      if (cells.length > cols) cols = cells.length;
      parsed.add(cells);
    }
    if (parsed.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Table(
        border: TableBorder.all(color: scheme.outlineVariant),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (final cells in parsed)
            TableRow(children: [
              for (var i = 0; i < cols; i++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: i < cells.length
                      ? Text(cells[i].$2,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: cells[i].$1 == 'th'
                                  ? FontWeight.w700
                                  : FontWeight.w400))
                      : const SizedBox.shrink(),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant)),
    );
  }

  Widget _para(BuildContext context, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _inline(context, t),
    );
  }

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

    final url =
        RegExp(r'\[url=([^\]]*)\]([\s\S]*?)\[\/url\]', caseSensitive: false);
    final img = RegExp(r'\[img\]([\s\S]*?)\[\/img\]', caseSensitive: false);
    final spoiler =
        RegExp(r'\[spoiler\]([\s\S]*?)\[\/spoiler\]', caseSensitive: false);

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
          child: _placeholder(context, '图片(发布后显示):${first.group(1)}'),
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
