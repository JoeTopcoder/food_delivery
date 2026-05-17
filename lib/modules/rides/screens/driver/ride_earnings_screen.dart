import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/config/supabase_config.dart';

// ---------------------------------------------------------------------------
// Ride Earnings Screen — dark theme, real data
// ---------------------------------------------------------------------------

class RideEarningsScreen extends ConsumerStatefulWidget {
  const RideEarningsScreen({super.key});

  @override
  ConsumerState<RideEarningsScreen> createState() => _RideEarningsScreenState();
}

class _RideEarningsScreenState extends ConsumerState<RideEarningsScreen> {
  bool _isLoading = true;

  double _todayEarnings = 0;
  int _todayRides = 0;
  double _weekEarnings = 0;
  int _weekRides = 0;
  List<RideRequest> _recentRides = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final driverResp = await SupabaseConfig.client
          .from('drivers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (driverResp == null) {
        setState(() => _isLoading = false);
        return;
      }

      final driverId = driverResp['id'] as String;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

      final rides = await ref.read(rideServiceProvider).getDriverRides(
        driverId: driverId,
        limit: 100,
      );

      double todayTotal = 0;
      int todayCount = 0;
      double weekTotal = 0;
      int weekCount = 0;
      final completed = <RideRequest>[];

      for (final r in rides) {
        if (r.rideStatus != RideStatus.rideCompleted) continue;
        completed.add(r);
        final earning = r.driverEarning ?? r.finalFare ?? r.estimatedFare ?? 0.0;
        if (!r.requestedAt.isBefore(todayStart)) {
          todayTotal += earning;
          todayCount++;
        }
        if (!r.requestedAt.isBefore(weekStart)) {
          weekTotal += earning;
          weekCount++;
        }
      }

      if (!mounted) return;
      setState(() {
        _todayEarnings = todayTotal;
        _todayRides = todayCount;
        _weekEarnings = weekTotal;
        _weekRides = weekCount;
        _recentRides = completed.take(20).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Earnings',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() => _isLoading = true);
              _load();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF22C55E)),
            )
          : RefreshIndicator(
              color: const Color(0xFF22C55E),
              backgroundColor: const Color(0xFF1E1E1E),
              onRefresh: () async {
                setState(() => _isLoading = true);
                await _load();
              },
              child: CustomScrollView(
                slivers: [
                  // Today's card
                  SliverToBoxAdapter(
                    child: _buildSummaryCard(
                      label: "Today's Earnings",
                      amount: _todayEarnings,
                      rides: _todayRides,
                      gradient: const [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                    ),
                  ),

                  // This week card
                  SliverToBoxAdapter(
                    child: _buildSummaryCard(
                      label: 'This Week',
                      amount: _weekEarnings,
                      rides: _weekRides,
                      gradient: const [Color(0xFF065F46), Color(0xFF059669)],
                    ),
                  ),

                  // Recent rides header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Text(
                        'Recent Rides',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Ride list
                  if (_recentRides.isEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.directions_car_outlined,
                                color: Colors.grey[700], size: 44),
                            const SizedBox(height: 10),
                            Text(
                              'No completed rides yet',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _buildRideRow(_recentRides[i]),
                        childCount: _recentRides.length,
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required double amount,
    required int rides,
    required List<Color> gradient,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'J\$${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$rides',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                rides == 1 ? 'Ride' : 'Rides',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRideRow(RideRequest ride) {
    final earning =
        ride.driverEarning ?? ride.finalFare ?? ride.estimatedFare ?? 0.0;
    final dateLabel = DateFormat('MMM d • h:mm a').format(ride.requestedAt);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car,
                color: Color(0xFF22C55E), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.destinationAddress,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'J\$${earning.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
