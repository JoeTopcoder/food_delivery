import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';

// ---------------------------------------------------------------------------
// Ride Complete Screen — driver summary and completion
// ---------------------------------------------------------------------------

class RideCompleteScreen extends ConsumerStatefulWidget {
  final String rideId;

  const RideCompleteScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideCompleteScreen> createState() => _RideCompleteScreenState();
}

class _RideCompleteScreenState extends ConsumerState<RideCompleteScreen> {
  Map<String, dynamic>? _completionResult;
  int _customerRating = 4;
  bool _isCompleting = false;
  RideRequest? _ride;
  bool _isLoadingRide = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRide());
  }

  // ------------------------------------------------------------------
  // Data loading
  // ------------------------------------------------------------------

  Future<void> _loadRide() async {
    try {
      final ride =
          await ref.read(rideServiceProvider).getRideRequest(widget.rideId);
      if (!mounted) return;
      setState(() {
        _ride = ride;
        _isLoadingRide = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoadingRide = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // Complete ride
  // ------------------------------------------------------------------

  Future<void> _completeRide() async {
    setState(() => _isCompleting = true);

    try {
      final rideService = ref.read(rideServiceProvider);

      final result = await rideService.completeRide(
        rideId: widget.rideId,
      );

      // Fire-and-forget customer rating
      unawaited(rideService.rateCustomer(
        rideId: widget.rideId,
        rating: _customerRating,
      ));

      if (!mounted) return;
      setState(() {
        _isCompleting = false;
        _completionResult = result;
      });

      // Short delay so user sees the earnings, then pop back to driver home
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete ride: $e')),
      );
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Ride Completed',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoadingRide
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 20),
                      _buildEarningsSection(),
                      const SizedBox(height: 30),
                      _buildRatingSection(),
                      const SizedBox(height: 40),
                      _buildCompleteButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load ride data',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(_loadError ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoadingRide = true;
                  _loadError = null;
                });
                _loadRide();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Summary card
  // ------------------------------------------------------------------

  Widget _buildSummaryCard() {
    final ride = _ride!;
    final distanceLabel =
        ride.distanceKm != null ? '${ride.distanceKm!.toStringAsFixed(1)} km' : '--';
    final durationLabel =
        ride.estimatedDurationMinutes != null ? '${ride.estimatedDurationMinutes} min' : '--';
    final fareValue = ride.finalFare ?? ride.estimatedFare ?? 0.0;
    final fareLabel = 'J\$${fareValue.toStringAsFixed(0)}';
    final paymentLabel = ride.paymentMethod?.name ?? 'card';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RIDE SUMMARY',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatColumn(label: 'Distance', value: distanceLabel),
              _VerticalDivider(),
              _StatColumn(label: 'Duration', value: durationLabel),
              _VerticalDivider(),
              _StatColumn(label: 'Fare', value: fareLabel),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Icon(Icons.credit_card_outlined, color: Theme.of(context).colorScheme.outlineVariant, size: 20),
              const SizedBox(width: 10),
              const Text('Payment', style: TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                _capitalise(paymentLabel),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Earnings section
  // ------------------------------------------------------------------

  Widget _buildEarningsSection() {
    if (_completionResult == null) return const SizedBox.shrink();

    final earning =
        (_completionResult!['driver_earning'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EARNINGS',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'J\$${earning.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Color(0xFF22C55E),
            fontSize: 40,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'After platform fee',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Rating section
  // ------------------------------------------------------------------

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rate your customer',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final filled = index < _customerRating;
            return GestureDetector(
              onTap: () => setState(() => _customerRating = index + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color:
                      filled ? const Color(0xFFFACC15) : Theme.of(context).colorScheme.outlineVariant,
                  size: 36,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Complete button
  // ------------------------------------------------------------------

  Widget _buildCompleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isCompleting ? null : _completeRide,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isCompleting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                'Complete',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: Theme.of(context).colorScheme.outlineVariant);
  }
}
