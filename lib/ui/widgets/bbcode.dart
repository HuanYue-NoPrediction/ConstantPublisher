import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

const kSteamPreviewBg = Color(0xFF1B2838);
const _kBody = Color(0xFFACB2B8);
const _kWhite = Color(0xFFF3F3F3);
const _kLink = Color(0xFF66C0F4);
const _kLine = Color(0xFF4D5766);
const _kQuoteBg = Color(0x33000000);
const _kCodeBg = Color(0x4D000000);
const List<String> _kFonts = [
  'Segoe UI',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
];

String _edge(String s) =>
    s.replaceAll(RegExp(r'^[ \t\r\n]+|[ \t\r\n]+$'), '');

class BBCodePreview extends StatelessWidget {
  final String source;
  const BBCodePreview(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
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
        final size = level == 'h1' ? 21.0 : (level == 'h2' ? 17.5 : 15.0);
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text.rich(
              TextSpan(children: _spans(context, _edge(m.group(2)!))),
              style: TextStyle(
                  fontSize: size,
                  fontWeight: level == 'h3' ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: .2,
                  fontFamilyFallback: _kFonts,
                  color: _kWhite)),
        ));
      } else if (m.group(3) != null) {
        final ordered = m.group(3)!.toLowerCase() == 'olist';
        var n = 0;
        for (final item in m.group(4)!.split('[*]')) {
          final t = _edge(item);
          if (t.isEmpty) continue;
          n++;
          blocks.add(Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 24,
                  child: Text(ordered ? '$n.' : '•',
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.6, color: _kBody))),
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
            color: _kCodeBg,
            border: Border.all(color: _kLine),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(m.group(5)!.trim(),
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFF9BB1C8))),
        ));
      } else if (m.group(7) != null) {
        blocks.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: _kQuoteBg,
            border: Border.all(color: _kLine),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((m.group(6) ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      AppLocalizations.of(context)
                          .bbPrevQuoteBy('${m.group(6)}'),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF8B98A6))),
                ),
              _inline(context, _edge(m.group(7)!)),
            ],
          ),
        ));
      } else if (m.group(8) != null) {
        blocks.add(_table(context, m.group(8)!));
      } else if (m.group(9) != null) {
        blocks.add(_placeholder(context,
            AppLocalizations.of(context).bbPrevVideo('${m.group(9)}')));
      } else if (m.group(10) != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(m.group(10)!,
              style:
                  const TextStyle(fontSize: 13.5, height: 1.6, color: _kBody)),
        ));
      } else {
        blocks.add(const Divider(color: _kLine, height: 22, thickness: 1));
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
    final trRe = RegExp(r'\[tr\]([\s\S]*?)\[\/tr\]', caseSensitive: false);
    final cellRe =
        RegExp(r'\[(th|td)\]([\s\S]*?)\[\/\1\]', caseSensitive: false);
    final parsed = <List<(String, String)>>[];
    var cols = 0;
    for (final tr in trRe.allMatches(body)) {
      final cells = [
        for (final c in cellRe.allMatches(tr.group(1)!))
          (c.group(1)!.toLowerCase(), _edge(c.group(2)!))
      ];
      if (cells.isEmpty) continue;
      if (cells.length > cols) cols = cells.length;
      parsed.add(cells);
    }
    if (parsed.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Table(
        border: TableBorder.all(color: _kLine),
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
                      ? Text.rich(
                          TextSpan(children: _spans(context, cells[i].$2)),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontFamilyFallback: _kFonts,
                              color: cells[i].$1 == 'th' ? _kWhite : _kBody,
                              fontWeight: cells[i].$1 == 'th'
                                  ? FontWeight.w600
                                  : FontWeight.w400))
                      : const SizedBox.shrink(),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _netImage(BuildContext context, String url) {
    if (!url.startsWith('http')) {
      return _placeholder(
          context, AppLocalizations.of(context).bbPrevImage(url));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            loadingBuilder: (c, child, prog) => prog == null
                ? child
                : Container(
                    width: 120,
                    height: 60,
                    color: const Color(0xFF2A3A4E),
                    child: const Icon(Icons.image_outlined,
                        size: 20, color: _kBody),
                  ),
            errorBuilder: (_, __, ___) => _placeholder(
                context, AppLocalizations.of(context).bbPrevImage(url)),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: _kLine),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11.5, fontFamily: 'monospace', color: _kBody)),
    );
  }

  Widget _para(BuildContext context, String raw) {
    final t = _edge(raw);
    if (t.isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _inline(context, t),
    );
  }

  Widget _inline(BuildContext context, String text) {
    return Text.rich(TextSpan(children: _spans(context, text)),
        style: const TextStyle(
            fontSize: 13.5,
            height: 1.6,
            color: _kBody,
            fontFamilyFallback: _kFonts));
  }

  List<InlineSpan> _spans(BuildContext context, String text) {
    final tags = <(RegExp, TextStyle Function())>[
      (
        RegExp(r'\[b\]([\s\S]*?)\[\/b\]', caseSensitive: false),
        () => const TextStyle(fontWeight: FontWeight.w700, color: _kWhite)
      ),
      (
        RegExp(r'\[i\]([\s\S]*?)\[\/i\]', caseSensitive: false),
        () => const TextStyle(fontStyle: FontStyle.italic)
      ),
      (
        RegExp(r'\[u\]([\s\S]*?)\[\/u\]', caseSensitive: false),
        () => const TextStyle(decoration: TextDecoration.underline)
      ),
      (
        RegExp(r'\[strike\]([\s\S]*?)\[\/strike\]', caseSensitive: false),
        () => const TextStyle(decoration: TextDecoration.lineThrough)
      ),
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
            style: style!(), children: _spans(context, first.group(1) ?? '')));
      case 'url':
        spans.add(TextSpan(
            style: const TextStyle(
                color: _kLink,
                decoration: TextDecoration.underline,
                decorationColor: _kLink),
            children: _spans(context, first.group(2) ?? '')));
      case 'img':
        spans.add(WidgetSpan(
          child: _netImage(context, (first.group(1) ?? '').trim()),
        ));
      case 'spoiler':
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _Spoiler(text: first.group(1) ?? ''),
        ));
    }

    spans.addAll(_spans(context, after));
    return spans;
  }
}

class _Spoiler extends StatefulWidget {
  final String text;
  const _Spoiler({required this.text});

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  var _show = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _show = true),
      onExit: (_) => setState(() => _show = false),
      child: Container(
        color: const Color(0xFF23252E),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.6,
            color: _show ? _kBody : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
