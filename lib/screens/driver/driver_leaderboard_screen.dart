import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/premium_providers.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';

class DriverLeaderboardScreen extends ConsumerStatefulWidget {
  const DriverLeaderboardScreen({super.key});

  @override
  ConsumerState<DriverLeaderboardScreen> createState() =>
      _DriverLeaderboardScreenState();
}

class _DriverLeaderboardScreenState
    extends ConsumerState<DriverLeaderboardScreen> {
  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(driverLeaderboardProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        backgroundColor: const Color(0xFF1E2030),
        onRefresh: () async {
          ref.invalidate(driverLeaderboardProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              backgroundColor: const Color(0xFF0F1117),
              foregroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 24),
                        Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Driver Leaderboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Compete with other drivers!',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            leaderboardAsync.when(
              data: (result) {
                final drivers = result.drivers;
                final totalDrivers = result.totalDrivers;
                if (drivers.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFBBF24,
                              ).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_events_outlined,
                              size: 40,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No Leaderboard Data',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rankings will appear once deliveries start.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Find current driver in the list
                final myDriver = drivers
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                      (d) => d?['user_id'] == currentUserId,
                      orElse: () => null,
                    );
                final myRank =
                    (myDriver?['deliveries_rank'] as num?)?.toInt() ?? -1;

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      // First item: "Your Rank" card
                      if (index == 0) {
                        return _YourRankCard(
                          myRank: myRank,
                          totalDrivers: totalDrivers,
                          driver: myDriver,
                        );
                      }

                      final driverIndex = index - 1;
                      final driver = drivers[driverIndex];
                      final rank =
                          (driver['deliveries_rank'] as num?)?.toInt() ??
                          driverIndex + 1;
                      final isMe = driver['user_id'] == currentUserId;

                      return _LeaderboardTile(
                        rank: rank,
                        name: driver['driver_name'] as String? ?? 'Unknown',
                        deliveries:
                            (driver['completed_deliveries'] as num?)?.toInt() ??
                            0,
                        rating: (driver['rating'] as num?)?.toDouble() ?? 0.0,
                        vehicleType: driver['vehicle_type'] as String? ?? 'car',
                        earnings:
                            (driver['total_earnings'] as num?)?.toDouble() ??
                            0.0,
                        isCurrentUser: isMe,
                      );
                    }, childCount: drivers.length + 1),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Text(
                    friendlyError(e),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "Your Rank" hero card ─────────────────────────────────────────────────
class _YourRankCard extends StatelessWidget {
  final int myRank;
  final int totalDrivers;
  final Map<String, dynamic>? driver;

  const _YourRankCard({
    required this.myRank,
    required this.totalDrivers,
    this.driver,
  });

  String get _positionLabel {
    if (myRank < 1) return 'Unranked';
    if (myRank == 1) return '1st';
    if (myRank == 2) return '2nd';
    if (myRank == 3) return '3rd';
    return '${myRank}th';
  }

  String get _motivationText {
    if (myRank < 1) return 'Complete a delivery to get on the board!';
    if (myRank == 1) return 'You\'re the #1 driver! Keep it up!';
    if (myRank <= 3)
      return 'Almost at the top! Just ${myRank - 1} driver(s) ahead.';
    if (myRank <= totalDrivers ~/ 2)
      return 'Top half! ${myRank - 1} drivers to beat.';
    return 'Keep delivering to climb the ranks!';
  }

  Color get _rankGlowColor {
    if (myRank < 1) return const Color(0xFF6B7280);
    if (myRank == 1) return const Color(0xFFFFD700);
    if (myRank == 2) return const Color(0xFFC0C0C0);
    if (myRank == 3) return const Color(0xFFCD7F32);
    return AppTheme.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final myDeliveries =
        (driver?['completed_deliveries'] as num?)?.toInt() ?? 0;
    final myRating = (driver?['rating'] as num?)?.toDouble() ?? 0.0;
    final myEarnings = (driver?['total_earnings'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _rankGlowColor.withValues(alpha: 0.15),
            const Color(0xFF1E2030),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _rankGlowColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Big rank circle
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _rankGlowColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: _rankGlowColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _positionLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: myRank >= 1 && myRank <= 3 ? 18 : 15,
                    color: _rankGlowColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR POSITION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      myRank >= 1
                          ? '#$myRank of $totalDrivers drivers'
                          : 'Not ranked yet',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _motivationText,
                      style: TextStyle(
                        fontSize: 12,
                        color: _rankGlowColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (driver != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1117).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatChip(
                    icon: Icons.local_shipping_rounded,
                    label: '$myDeliveries',
                    subtitle: 'Deliveries',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: const Color(0xFF2A2D3E),
                  ),
                  _StatChip(
                    icon: Icons.star_rounded,
                    label: myRating.toStringAsFixed(1),
                    subtitle: 'Rating',
                    iconColor: const Color(0xFFFBBF24),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: const Color(0xFF2A2D3E),
                  ),
                  _StatChip(
                    icon: Icons.payments_rounded,
                    label:
                        '${AppConstants.currencySymbol}${myEarnings.toStringAsFixed(2)}',
                    subtitle: 'Earned',
                    iconColor: const Color(0xFF34D399),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? iconColor;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor ?? Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final String name;
  final int deliveries;
  final double rating;
  final String vehicleType;
  final double earnings;
  final bool isCurrentUser;

  const _LeaderboardTile({
    required this.rank,
    required this.name,
    required this.deliveries,
    required this.rating,
    required this.vehicleType,
    required this.earnings,
    this.isCurrentUser = false,
  });

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData get _vehicleIcon {
    switch (vehicleType) {
      case 'motorcycle':
        return Icons.two_wheeler;
      case 'bicycle':
        return Icons.pedal_bike;
      case 'car':
        return Icons.directions_car;
      default:
        return Icons.delivery_dining;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;

    return Container(
      margin: EdgeInsets.only(top: rank == 1 ? 0 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppTheme.primaryColor.withValues(alpha: 0.12)
            : const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.primaryColor.withValues(alpha: 0.7)
              : isTop3
              ? _rankColor.withValues(alpha: 0.4)
              : const Color(0xFF2A2D3E),
          width: isCurrentUser ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isTop3
                  ? _rankColor.withValues(alpha: 0.15)
                  : const Color(0xFF2A2D3E),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: isTop3
                ? Icon(Icons.emoji_events_rounded, color: _rankColor, size: 20)
                : Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Driver info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: isTop3 ? 15 : 14,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      _vehicleIcon,
                      size: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$deliveries deliveries',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.payments_rounded,
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${AppConstants.currencySymbol}${earnings.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Rating badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFBBF24),
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFFFBBF24),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
