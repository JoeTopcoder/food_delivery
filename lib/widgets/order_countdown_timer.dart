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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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

  Duration get _remaining =>
      _isOverdue ? Duration.zero : _totalDuration - _elapsed;

  double get _progress =>
      (_elapsed.inSeconds / _totalDuration.inSeconds).clamp(0.0, 1.0);

  /// Returns an escalating urgency color based on elapsed time:
  /// - Under 75% of estimate → green
  /// - 75-100% of estimate → amber
  /// - 45+ min elapsed → light red, darkening every 30 min after
  Color get _urgencyColor {
    final elapsedMin = _elapsed.inMinutes;

    if (elapsedMin >= 45) {
      // Steps beyond 45 min, each 30 min = one darker step
      final steps = ((elapsedMin - 45) / 30).floor();
      // Interpolate from light-red to very-dark-red
      // step 0 = #EF4444, step 1 = #DC2626, step 2 = #B91C1C, step 3+ = #7F1D1D
      const reds = [
        Color(0xFFEF4444), // 45 min
        Color(0xFFDC2626), // 75 min
        Color(0xFFB91C1C), // 105 min
        Color(0xFF991B1B), // 135 min
        Color(0xFF7F1D1D), // 165 min+
      ];
      return reds[math.min(steps, reds.length - 1)];
    }

    if (_isOverdue || _progress > 0.75) {
      return const Color(0xFFF59E0B); // amber
    }

    return const Color(0xFF10B981); // green
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompact();
    return _buildFull();
  }

  Widget _buildCompact() {
    final color = _urgencyColor;
    final isRed = _elapsed.inMinutes >= 45;
    final text = _isOverdue
        ? '+${_formatDuration(_elapsed - _totalDuration)}'
        : _formatDuration(_remaining);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isRed ? Icons.warning_amber_rounded : Icons.timer_outlined,
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
    final elapsedMin = _elapsed.inMinutes;
    final String label;

    if (elapsedMin >= 45 && _isOverdue) {
      label = 'OVERDUE by ${_formatDuration(_elapsed - _totalDuration)}';
    } else if (elapsedMin >= 45) {
      label = '${_formatDuration(_remaining)} remaining \u2022 PRIORITY';
    } else if (_isOverdue) {
      label = 'OVERDUE by ${_formatDuration(_elapsed - _totalDuration)}';
    } else {
      label = '${_formatDuration(_remaining)} remaining';
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
              '${_formatDuration(_elapsed)} / ${_totalMinutes}m',
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
