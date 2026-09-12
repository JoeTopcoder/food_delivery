import 'dart:math';

import 'package:flutter/material.dart';

/// A courier riding a scooter with a delivery box on the back.
///
/// Drawn rather than shipped as an asset: it stays crisp at any density, needs
/// no image to load before it can appear, tints itself to whatever background
/// it sits on, and the wheels actually turn. Laid out in a fixed 140x96 space
/// and scaled to the box it is given, so the proportions hold at any width.
class RidingCourier extends StatefulWidget {
  const RidingCourier({
    super.key,
    this.width = 200,
    this.color = Colors.white,
    this.accent,
  });

  final double width;

  /// The rider, scooter and road. Usually the foreground colour of whatever
  /// this sits on.
  final Color color;

  /// Used for the details cut into the filled shapes — the box's handle and
  /// panel, the helmet's visor. Should be the background colour behind the
  /// widget, so the cuts read as holes rather than as a third colour.
  final Color? accent;

  @override
  State<RidingCourier> createState() => _RidingCourierState();
}

class _RidingCourierState extends State<RidingCourier>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.width * (_CourierPainter.designH / _CourierPainter.designW),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _CourierPainter(
            t: _c.value,
            color: widget.color,
            accent: widget.accent,
          ),
        ),
      ),
    );
  }
}

class _CourierPainter extends CustomPainter {
  _CourierPainter({required this.t, required this.color, this.accent});

  /// 0..1, looping.
  final double t;
  final Color color;
  final Color? accent;

  static const designW = 140.0;
  static const designH = 96.0;

  // Everything is positioned against these three, so the parts stay related to
  // each other if any one of them moves.
  static const _rearWheel = Offset(34, 72);
  static const _frontWheel = Offset(112, 72);
  static const _wheelR = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / designW);

    // Two wheel turns per loop, and the bob runs at the same rate so the rider
    // rises and falls with the road rather than drifting against it.
    final spin = t * 2 * pi * 2;
    final bob = sin(t * 2 * pi * 2) * 1.2;

    _speedLines(canvas);
    _road(canvas);

    canvas.save();
    canvas.translate(0, bob);
    _deliveryBox(canvas);
    _frame(canvas);
    _wheel(canvas, _rearWheel, spin);
    _wheel(canvas, _frontWheel, spin);
    _rider(canvas);
    canvas.restore();

    canvas.restore();
  }

  // ── Motion ───────────────────────────────────────────────────────────────

  void _road(Canvas canvas) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // The dashes scroll and the scooter stays put — that is what reads as
    // forward motion in a fixed frame.
    const dash = 13.0, period = 24.0;
    final shift = -(t * period);
    for (double x = shift - period; x < designW + period; x += period) {
      final a = x.clamp(0.0, designW);
      final b = (x + dash).clamp(0.0, designW);
      if (b > a) canvas.drawLine(Offset(a, 90), Offset(b, 90), p);
    }
  }

  void _speedLines(Canvas canvas) {
    final p = Paint()
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    // Own phases, so they never blink in unison.
    const rows = [
      (y: 28.0, len: 15.0, phase: 0.0),
      (y: 46.0, len: 22.0, phase: 0.36),
      (y: 62.0, len: 12.0, phase: 0.7),
    ];
    for (final r in rows) {
      final k = (t + r.phase) % 1.0;
      final x = 16 - k * 22;
      p.color = color.withValues(alpha: 0.45 * sin(k * pi));
      canvas.drawLine(Offset(x - r.len, r.y), Offset(x, r.y), p);
    }
  }

  // ── Scooter ──────────────────────────────────────────────────────────────

  void _deliveryBox(Canvas canvas) {
    final solid = Paint()..color = color;

    // Sits behind the seat and over the rear wheel, where a courier's box goes.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 22, 31, 31),
        const Radius.circular(6),
      ),
      solid,
    );

    if (accent != null) {
      final cut = Paint()..color = accent!;
      // A handle across the lid and a panel below it: two cuts are enough to
      // read as an insulated food box instead of a plain crate.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(15, 27, 19, 3.5),
          const Radius.circular(1.75),
        ),
        cut,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(16, 35, 17, 12),
          const Radius.circular(3),
        ),
        cut,
      );
    }
  }

  void _frame(Canvas canvas) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 6.5;

    // One continuous path from the rear axle, along the body, down to the
    // footboard and up the steering column. Kept steep on purpose: a shallow
    // leg shield crosses the rider's torso and the two merge into one mass.
    final frame = Path()
      ..moveTo(_rearWheel.dx, _rearWheel.dy)
      ..lineTo(40, 57)
      ..lineTo(70, 57)
      ..lineTo(76, 65)
      ..lineTo(98, 65)
      ..lineTo(106, 34);
    canvas.drawPath(frame, stroke);

    // Seat.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(38, 51, 33, 7),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );

    // Handlebar and grip.
    stroke.strokeWidth = 5;
    canvas.drawLine(const Offset(101, 29), const Offset(119, 25), stroke);
    canvas.drawCircle(const Offset(119, 25), 3.2, Paint()..color = color);

    // Headlight, tucked under the bars.
    canvas.drawCircle(const Offset(111, 38), 4.2, Paint()..color = color);
  }

  void _wheel(Canvas canvas, Offset c, double spin) {
    canvas.drawCircle(
      c,
      _wheelR,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Spokes are what make the rotation legible — a plain ring spinning looks
    // like a ring standing still.
    final spoke = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final a = spin + i * pi / 4;
      final d = Offset(cos(a), sin(a)) * (_wheelR - 3);
      canvas.drawLine(c - d, c + d, spoke);
    }
    canvas.drawCircle(c, 2.8, Paint()..color = color);
  }

  // ── Rider ────────────────────────────────────────────────────────────────

  void _rider(Canvas canvas) {
    final limb = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Seated, leaning into the ride: hip on the seat, hands on the bars, feet
    // on the footboard. Each limb is a separate stroke with clear air between
    // it and the frame, so nothing reads as one solid shape.
    limb.strokeWidth = 8; // torso, its base resting on the seat
    canvas.drawLine(const Offset(54, 47), const Offset(72, 29), limb);

    limb.strokeWidth = 5; // arm to the grip
    canvas.drawLine(const Offset(72, 31), const Offset(105, 27), limb);

    // The thigh runs above the body rail with air under it, and the shin comes
    // down past the front of the step rather than through it. Both gaps are
    // deliberate: when these touched, rider and scooter read as one blob.
    limb.strokeWidth = 5.5;
    canvas.drawLine(const Offset(54, 46), const Offset(78, 47.5), limb);
    limb.strokeWidth = 5;
    canvas.drawLine(const Offset(78, 47.5), const Offset(87, 63), limb);

    // Helmet: a filled dome with a short peak over the brow.
    const head = Offset(80, 19);
    canvas.drawCircle(head, 9.5, Paint()..color = color);
    final peak = Path()
      ..moveTo(86, 15)
      ..lineTo(94, 17.5)
      ..lineTo(86, 21)
      ..close();
    canvas.drawPath(peak, Paint()..color = color);

    if (accent != null) {
      // Visor: a slot across the front of the helmet rather than a bite out of
      // its edge, which read as damage.
      canvas.save();
      canvas.translate(head.dx, head.dy);
      canvas.rotate(-0.18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1.5, -2.5, 8, 5),
          const Radius.circular(2.5),
        ),
        Paint()..color = accent!,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CourierPainter old) =>
      old.t != t || old.color != color || old.accent != accent;
}
