import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A countdown timer widget that shows elapsed time since an order was placed,
/// with a visual progress indicator toward the estimated completion time.
///
/// Color escalation:
///  - Green while under estimate
///  - Amber when > 75% of estimate
///  - At 45 min+: light red (#EF4444)
///  - Every 30 min after 45: progressively darker red → (#B91C1C) → (#7F1D1D)
class OrderCountdownTimer extends StatefulWidget {
  final DateTime orderedAt;

  /// Estimated total minutes for the order (prep + delivery).
  /// Falls back to 45 minutes if null.
  final int? estimatedMinutes;

  /// If true, show a compact single-line version.
  final bool compact;

  const OrderCountdownTimer({
    super.key,
    required this.orderedAt,
    this.estimatedMinutes,
    this.compact = false,
  });

  @override
  State<OrderCountdownTimer> createState() => _OrderCountdownTimerState();
}

class _OrderCountdownTimerState extends State<OrderCountdownTimer> {
  late Timer _timer;
  late Duration _elapsed;

  int get _totalMinutes => widget.estimatedMinutes ?? 45;
  Duration get _totalDuration => Duration(minutes: _totalMinutes);

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.orderedAt);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.orderedAt);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  bool get _isOverdue => _elapsed > _totalDuration;

  /// Minutes left on the countdown (negative = overdue).
  int get _remainingMin => _totalMinutes - _elapsed.inMinutes;

  /// How many minutes past zero.
  int get _overdueMin => _isOverdue ? (_elapsed.inMinutes - _totalMinutes) : 0;

  double get _progress =>
      (_elapsed.inSeconds / _totalDuration.inSeconds).clamp(0.0, 1.0);

  /// Green while counting down, then escalating red once at 0 and beyond.
  /// Every 30 min past 0 → darker red.
  Color get _urgencyColor {
    if (!_isOverdue) return const Color(0xFF10B981); // green

    final overMin = _overdueMin;
    final steps = (overMin / 30).floor();
    const reds = [
      Color(0xFFEF4444), // 0-29 min overdue
      Color(0xFFDC2626), // 30-59 min overdue
      Color(0xFFB91C1C), // 60-89 min overdue
      Color(0xFF991B1B), // 90-119 min overdue
      Color(0xFF7F1D1D), // 120+ min overdue
    ];
    return reds[math.min(steps, reds.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompact();
    return _buildFull();
  }

  Widget _buildCompact() {
    final color = _urgencyColor;
    final text = _isOverdue ? '+${_overdueMin}m' : '${_remainingMin}m';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _isOverdue ? Icons.warning_amber_rounded : Icons.timer_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFull() {
    final Color barColor = _urgencyColor;
    final String label;

    if (_isOverdue) {
      label = 'OVERDUE +${_overdueMin}m';
    } else {
      label = '${_remainingMin}m remaining';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _isOverdue ? Icons.warning_amber_rounded : Icons.timer_outlined,
              size: 14,
              color: barColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: barColor,
              ),
            ),
            const Spacer(),
            Text(
              '${_elapsed.inMinutes}m / ${_totalMinutes}m',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: barColor.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}
