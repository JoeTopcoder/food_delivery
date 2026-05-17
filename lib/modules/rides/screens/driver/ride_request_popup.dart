import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/services/ride_service.dart';

// ---------------------------------------------------------------------------
// Ride Request Popup — dark modal bottom sheet shown when a new ride arrives
// ---------------------------------------------------------------------------

class RideRequestPopup extends StatefulWidget {
  final RideDriverRequest request;

  /// Pre-fetched ride data: pickupAddress, destinationAddress,
  /// distanceKm, estimatedDurationMinutes, estimatedFare
  final Map<String, dynamic> rideDetails;

  /// Called with the rideId when the driver accepts
  final void Function(String rideId) onAccepted;

  final VoidCallback onRejected;

  /// Injected so this StatefulWidget can call RideService without ref
  final RideService rideService;

  const RideRequestPopup({
    super.key,
    required this.request,
    required this.rideDetails,
    required this.onAccepted,
    required this.onRejected,
    required this.rideService,
  });

  @override
  State<RideRequestPopup> createState() => _RideRequestPopupState();
}

class _RideRequestPopupState extends State<RideRequestPopup>
    with SingleTickerProviderStateMixin {
  static const int _totalSeconds = 60;

  int _secondsLeft = _totalSeconds;
  Timer? _timer;
  bool _isProcessing = false;

  late final AnimationController _arcCtrl;

  // ------------------------------------------------------------------
  // Accessors into rideDetails
  // ------------------------------------------------------------------
  String get _pickupAddress =>
      widget.rideDetails['pickupAddress'] as String? ?? 'Pickup Location';

  String get _destinationAddress =>
      widget.rideDetails['destinationAddress'] as String? ?? 'Destination';

  double get _distanceKm =>
      (widget.rideDetails['distanceKm'] as num?)?.toDouble() ?? 0.0;

  int get _estimatedDurationMinutes =>
      (widget.rideDetails['estimatedDurationMinutes'] as num?)?.toInt() ?? 0;

  double get _estimatedFare =>
      (widget.rideDetails['estimatedFare'] as num?)?.toDouble() ?? 0.0;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    _arcCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _totalSeconds),
    )..forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        t.cancel();
        _handleTimeout();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _arcCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Logic
  // ------------------------------------------------------------------
  void _handleTimeout() {
    _timer?.cancel();
    _timer = null;
    if (mounted) widget.onRejected();
  }

  Future<void> _onAccept() async {
    _timer?.cancel();
    _timer = null;
    setState(() => _isProcessing = true);

    try {
      final result = await widget.rideService.respondToDriverRideRequest(
        rideDriverRequestId: widget.request.id,
        accept: true,
      );

      if (!mounted) return;

      final accepted = result['accepted'] as bool? ?? false;
      if (accepted) {
        widget.onAccepted(widget.request.rideId);
      } else {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride already assigned to another driver'),
          ),
        );
        widget.onRejected();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to respond to request')),
      );
      widget.onRejected();
    }
  }

  Future<void> _onReject() async {
    _timer?.cancel();
    _timer = null;

    try {
      await widget.rideService.respondToDriverRideRequest(
        rideDriverRequestId: widget.request.id,
        accept: false,
      );
    } catch (_) {
      // Best effort — still dismiss
    }

    widget.onRejected();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'New Ride Request',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _CountdownRing(
                secondsLeft: _secondsLeft,
                totalSeconds: _totalSeconds,
                arcCtrl: _arcCtrl,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Pickup
          _LocationRow(
            isPickup: true,
            label: 'Pickup',
            address: _pickupAddress,
          ),

          // Dotted separator
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Column(
              children: List.generate(
                3,
                (_) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),

          // Destination
          _LocationRow(
            isPickup: false,
            label: 'Destination',
            address: _destinationAddress,
          ),

          const SizedBox(height: 12),

          // Distance & duration
          Row(
            children: [
              _InfoChip(
                icon: Icons.straighten_outlined,
                value: '${_distanceKm.toStringAsFixed(1)} km',
              ),
              const SizedBox(width: 16),
              _InfoChip(
                icon: Icons.access_time_outlined,
                value: '$_estimatedDurationMinutes min',
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Divider(color: Colors.white12),

          const SizedBox(height: 8),

          // Fare
          Center(
            child: Column(
              children: [
                Text(
                  '\$${_estimatedFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Estimated Fare',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Accept button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 8),

          // Reject button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _isProcessing ? null : _onReject,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                foregroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Reject',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown ring
// ---------------------------------------------------------------------------

class _CountdownRing extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;
  final AnimationController arcCtrl;

  const _CountdownRing({
    required this.secondsLeft,
    required this.totalSeconds,
    required this.arcCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / totalSeconds;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: arcCtrl,
            builder: (_, __) => CustomPaint(
              size: const Size(52, 52),
              painter: _ArcPainter(progress: progress),
            ),
          ),
          Text(
            '$secondsLeft',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;

  const _ArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Location row
// ---------------------------------------------------------------------------

class _LocationRow extends StatelessWidget {
  final bool isPickup;
  final String label;
  final String address;

  const _LocationRow({
    required this.isPickup,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isPickup
                ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                : const Color(0xFFEF4444).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPickup ? Icons.circle : Icons.location_pin,
            color: isPickup
                ? const Color(0xFF2563EB)
                : const Color(0xFFEF4444),
            size: isPickup ? 10 : 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Info chip
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey[500], size: 16),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      ],
    );
  }
}
