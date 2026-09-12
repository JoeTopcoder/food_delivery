import 'dart:math';

import 'package:flutter/material.dart';

/// QuickDash brand colours, taken from the logo lockup.
class QuickDashBrand {
  QuickDashBrand._();
  static const blueLight = Color(0xFF2E6BE6);
  static const blueDark = Color(0xFF0F3BBF);
  static const orange = Color(0xFFFF8A00);
  static const orangeDeep = Color(0xFFF5401A);
}

/// The QuickDash mark: the Q with a cloche in its counter, the arrow tail, and
/// the speed lines trailing off to the left.
///
/// Drawn rather than shipped as a PNG. It stays sharp at every density and
/// needs no asset to decode before the splash can appear. [monochrome] draws
/// the same shape in a single colour — the brand blue disappears against
/// Midnight Navy, so a dark background needs a white version of it.
class QuickDashMark extends StatelessWidget {
  const QuickDashMark({super.key, this.size = 120, this.monochrome});

  final double size;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * (_MarkPainter.designH / _MarkPainter.designW),
      child: CustomPaint(painter: _MarkPainter(monochrome: monochrome)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({this.monochrome});

  final Color? monochrome;

  static const designW = 210.0;
  static const designH = 130.0;

  static const _c = Offset(140, 58); // centre of the Q
  static const _rOuter = 44.0;
  static const _rInner = 27.0;

  Shader? _blue(Rect r) => monochrome != null
      ? null
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [QuickDashBrand.blueLight, QuickDashBrand.blueDark],
        ).createShader(r);

  Shader? _hot(Rect r) => monochrome != null
      ? null
      : const LinearGradient(
          colors: [QuickDashBrand.orange, QuickDashBrand.orangeDeep],
        ).createShader(r);

  Paint _fill(Rect bounds, {required bool hot}) {
    final p = Paint()..color = monochrome ?? Colors.white;
    final sh = hot ? _hot(bounds) : _blue(bounds);
    if (sh != null) p.shader = sh;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / designW);

    _speedLines(canvas);
    _tail(canvas);
    _ring(canvas);
    _cloche(canvas);

    canvas.restore();
  }

  /// Four trails, longest at the left, so the mark reads as moving.
  void _speedLines(Canvas canvas) {
    const rows = [
      (x1: 74.0, x2: 112.0, y: 30.0),
      (x1: 34.0, x2: 104.0, y: 46.0),
      (x1: 12.0, x2: 92.0, y: 62.0),
      (x1: 44.0, x2: 100.0, y: 78.0),
    ];
    for (final r in rows) {
      final rect = Rect.fromLTRB(r.x1, r.y - 7, r.x2, r.y + 7);
      final p = _fill(rect, hot: true)
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(r.x1, r.y), Offset(r.x2, r.y), p);
    }
  }

  /// The Q's tail, and the arrowhead it throws forward.
  void _tail(Canvas canvas) {
    final bar = Path()
      ..moveTo(150, 74)
      ..lineTo(178, 74)
      ..lineTo(196, 112)
      ..lineTo(166, 112)
      ..close();
    canvas.drawPath(bar, _fill(bar.getBounds(), hot: false));

    // Clear of the ring's right edge (x=184): overlapping it made the two
    // shapes read as one blob rather than an arrow leaving the Q.
    final head = Path()
      ..moveTo(186, 69)
      ..lineTo(209, 89)
      ..lineTo(184, 105)
      ..close();
    canvas.drawPath(head, _fill(head.getBounds(), hot: true));
  }

  /// The ring, as one path with the hole punched out, so the tail passes behind
  /// it without a seam.
  void _ring(Canvas canvas) {
    final ring = Path()
      ..addOval(Rect.fromCircle(center: _c, radius: _rOuter))
      ..addOval(Rect.fromCircle(center: _c, radius: _rInner))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, _fill(ring.getBounds(), hot: false));
  }

  /// The cloche in the Q's counter: dome, tray, and the knob on top.
  void _cloche(Canvas canvas) {
    final bounds = Rect.fromCircle(center: _c, radius: _rInner);
    final p = _fill(bounds, hot: false);

    final dome = Path()
      ..moveTo(_c.dx - 19, _c.dy + 7)
      ..arcTo(
        Rect.fromCircle(center: Offset(_c.dx, _c.dy + 7), radius: 19),
        pi,
        pi,
        false,
      )
      ..close();
    canvas.drawPath(dome, p);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_c.dx - 23, _c.dy + 8, 46, 6),
        const Radius.circular(3),
      ),
      p,
    );
    canvas.drawCircle(Offset(_c.dx, _c.dy - 15), 3.6, p);

    // The highlight arc inside the dome, as on the lockup. Skipped in the
    // monochrome build, where there is no second colour to cut it with.
    if (monochrome == null) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(_c.dx, _c.dy + 7), radius: 12),
        pi * 1.15,
        pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.monochrome != monochrome;
}

/// "QuickDash" — blue through "Quick", orange through "Dash", as on the
/// lockup. One gradient with a hard stop rather than two text spans, so the
/// colour break stays put whatever the font metrics do.
class QuickDashWordmark extends StatelessWidget {
  const QuickDashWordmark({super.key, this.fontSize = 40, this.monochrome});

  final double fontSize;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      'QuickDash',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: -fontSize * 0.02,
        height: 1.05,
        color: monochrome ?? Colors.white,
      ),
    );
    if (monochrome != null) return text;

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [
          QuickDashBrand.blueLight,
          QuickDashBrand.blueDark,
          QuickDashBrand.orange,
          QuickDashBrand.orangeDeep,
        ],
        stops: [0.0, 0.55, 0.57, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.srcIn,
      child: text,
    );
  }
}

/// The full lockup: mark over wordmark, optionally with the tagline.
class QuickDashLogo extends StatelessWidget {
  const QuickDashLogo({
    super.key,
    this.width = 240,
    this.showTagline = false,
    this.monochrome,
  });

  final double width;
  final bool showTagline;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    final wordSize = width * 0.20;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QuickDashMark(size: width * 0.86, monochrome: monochrome),
        SizedBox(height: width * 0.02),
        QuickDashWordmark(fontSize: wordSize, monochrome: monochrome),
        if (showTagline) ...[
          SizedBox(height: width * 0.03),
          Text(
            'Good Food. Faster.',
            style: TextStyle(
              fontSize: wordSize * 0.36,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.2,
              color: monochrome ?? QuickDashBrand.blueDark,
            ),
          ),
        ],
      ],
    );
  }
}
