import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/gen/app_localizations.dart';

Future<Color?> showSeedPicker(BuildContext context, Color initial) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _SeedPickerDialog(initial: initial),
    );

class _SeedPickerDialog extends StatefulWidget {
  final Color initial;
  const _SeedPickerDialog({required this.initial});

  @override
  State<_SeedPickerDialog> createState() => _SeedPickerDialogState();
}

class _SeedPickerDialogState extends State<_SeedPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex =
      TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(Color c) =>
      '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor v, {bool syncHex = true}) {
    setState(() {
      _hsv = v;
      if (syncHex) _hex.text = _hexOf(v.toColor());
    });
  }

  void _onHexSubmit(String s) {
    final t = s.startsWith('#') ? s.substring(1) : s;
    if (t.length != 6) return;
    final n = int.tryParse(t, radix: 16);
    if (n == null) return;
    _set(HSVColor.fromColor(Color(0xFF000000 | n)), syncHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(t.seedCustomTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _SvField(
                hsv: _hsv,
                onChanged: (h) => _set(h),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _HueBar(
                hue: _hsv.hue,
                onChanged: (h) => _set(_hsv.withHue(h)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onSubmitted: _onHexSubmit,
                    onChanged: _onHexSubmit,
                    style: const TextStyle(fontFamily: 'monospace'),
                    inputFormatters: [LengthLimitingTextInputFormatter(7)],
                    decoration: InputDecoration(
                      labelText: t.seedHex,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: Text(t.seedApply),
        ),
      ],
    );
  }
}

class _SvField extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _SvField({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const h = 170.0;
      void handle(Offset p) {
        final s = (p.dx / box.maxWidth).clamp(0.0, 1.0);
        final v = 1 - (p.dy / h).clamp(0.0, 1.0);
        onChanged(hsv.withSaturation(s).withValue(v));
      }

      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: SizedBox(
          width: double.infinity,
          height: h,
          child: CustomPaint(
            painter: _SvPainter(hsv),
          ),
        ),
      );
    });
  }
}

class _SvPainter extends CustomPainter {
  final HSVColor hsv;
  const _SvPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hue],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final cx = hsv.saturation * size.width;
    final cy = (1 - hsv.value) * size.height;
    canvas.drawCircle(
      Offset(cx, cy),
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black26,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueBar({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      void handle(Offset p) =>
          onChanged((p.dx / box.maxWidth).clamp(0.0, 1.0) * 360);
      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: SizedBox(
          width: double.infinity,
          height: 22,
          child: CustomPaint(painter: _HuePainter(hue)),
        ),
      );
    });
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          for (var i = 0; i <= 360; i += 60)
            HSVColor.fromAHSV(1, i.toDouble() % 360, 1, 1).toColor(),
        ]).createShader(rect),
    );
    final x = hue / 360 * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(x, size.height / 2), width: 6, height: size.height),
        const Radius.circular(3),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
