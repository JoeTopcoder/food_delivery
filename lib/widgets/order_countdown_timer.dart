import 'dart:async';
import 'package:flutter/material.dart';

/// A countdown timer widget that shows elapsed time since an order was placed,
/// with a visual progress indicator toward the estimated completion time.
///
/// Displays MM:SS elapsed, a progress bar, and the estimated total minutes.
/// Turns red and shows "OVERDUE" when time exceeds the estimate.
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
    final color = _isOverdue ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final text = _isOverdue
        ? '+${_formatDuration(_elapsed - _totalDuration)}'
        : _formatDuration(_remaining);

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
    final Color barColor;
    final String label;

    if (_isOverdue) {
      barColor = const Color(0xFFEF4444);
      label = 'OVERDUE by ${_formatDuration(_elapsed - _totalDuration)}';
    } else if (_progress > 0.75) {
      barColor = const Color(0xFFF59E0B);
      label = '${_formatDuration(_remaining)} remaining';
    } else {
      barColor = const Color(0xFF10B981);
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
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
              ),
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
