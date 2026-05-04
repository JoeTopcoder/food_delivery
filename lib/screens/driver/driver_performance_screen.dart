import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/driver_intelligence_models.dart';
import '../../providers/driver_provider.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_theme.dart';

class DriverPerformanceScreen extends ConsumerWidget {
  const DriverPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: Text('Not signed in', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final driverAsync = ref.watch(driverProfileProvider(uid));
    final driver = driverAsync.valueOrNull;
    if (driver == null) {
      if (driverAsync.hasError) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: Center(
            child: Text(
              friendlyError(driverAsync.error),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    final statsAsync = ref.watch(driverStatsProvider(driver.id));
    final recsAsync = ref.watch(
      driverRecommendationsProvider((
        driverId: driver.id,
        lat: null,
        lng: null,
      )),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverAppBar(
            pinned: true,
            backgroundColor: Color(0xFF0F1117),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Performance',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: statsAsync.when(
              loading: () => Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  friendlyError(e),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
              data: (stats) {
                if (stats == null) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No performance data yet. Complete some deliveries!',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Tier Card ──────────────────────────────────────────
                      _TierCard(stats: stats),
                      const SizedBox(height: 16),

                      // ── Score Breakdown ────────────────────────────────────
                      _ScoreBreakdown(stats: stats),
                      const SizedBox(height: 16),

                      // ── Rate cards ─────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _RateCard(
                              label: 'Acceptance',
                              value: stats.acceptanceRate,
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF22C55E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _RateCard(
                              label: 'Completion',
                              value: stats.completionRate,
                              icon: Icons.verified_rounded,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _RateCard(
                              label: 'On-Time',
                              value: stats.onTimeRate,
                              icon: Icons.schedule_rounded,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _RateCard(
                              label: 'Decline',
                              value: () {
                                final total =
                                    stats.ordersAccepted + stats.ordersDeclined;
                                return total > 0
                                    ? (stats.ordersDeclined / total) * 100
                                    : 0.0;
                              }(),
                              icon: Icons.cancel_rounded,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Stats grid ─────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'Avg Rating',
                              value: stats.avgCustomerRating.toStringAsFixed(1),
                              icon: Icons.star_rounded,
                              color: const Color(0xFFFBBF24),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              label: 'Avg Delivery',
                              value:
                                  '${stats.avgDeliveryMinutes.toStringAsFixed(0)} min',
                              icon: Icons.timer_rounded,
                              color: const Color(0xFF06B6D4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'Distance Driven',
                              value:
                                  '${(stats.totalDistanceKm * AppConstants.kmToMiles).toStringAsFixed(1)} mi',
                              icon: Icons.route_rounded,
                              color: const Color(0xFFF97316),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              label: 'Total Tips',
                              value:
                                  '${AppConstants.currencySymbol}${stats.totalTips.toStringAsFixed(2)}',
                              icon: Icons.volunteer_activism_rounded,
                              color: const Color(0xFF22C55E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'Accepted',
                              value: stats.ordersAccepted.toString(),
                              icon: Icons.thumb_up_rounded,
                              color: const Color(0xFF22C55E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              label: 'Declined',
                              value: stats.ordersDeclined.toString(),
                              icon: Icons.thumb_down_rounded,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Pay Rate ───────────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2030),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF22C55E,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.paid_rounded,
                                color: Color(0xFF22C55E),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '\$${AppConstants.driverRatePerMile.toStringAsFixed(2)}/mile',
                                    style: const TextStyle(
                                      color: Color(0xFF22C55E),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Text(
                                    'Your guaranteed pay rate + tips',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Min \$${AppConstants.driverMinBasePay.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Tier Benefits ──────────────────────────────────────
                      _TierBenefits(
                        tier: stats.tier,
                        bonusMultiplier: stats.bonusMultiplier,
                        priorityDispatch: stats.priorityDispatch,
                      ),
                      const SizedBox(height: 16),

                      // ── Smart Recommendations ─────────────────────────────
                      recsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (recs) {
                          if (recs == null || recs.tips.isEmpty)
                            return const SizedBox.shrink();
                          return _RecommendationsCard(recs: recs);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tier Card ────────────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final DriverStats stats;
  const _TierCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final Color tierColor;
    final IconData tierIcon;
    switch (stats.tier) {
      case 'elite':
        tierColor = const Color(0xFFE879F9);
        tierIcon = Icons.diamond_rounded;
        break;
      case 'gold':
        tierColor = const Color(0xFFFBBF24);
        tierIcon = Icons.emoji_events_rounded;
        break;
      case 'silver':
        tierColor = const Color(0xFF94A3B8);
        tierIcon = Icons.workspace_premium_rounded;
        break;
      default:
        tierColor = const Color(0xFFD97706);
        tierIcon = Icons.shield_rounded;
    }

    final nextTierScore = stats.scoreToNextTier;
    final double progressToNext;
    if (stats.tier == 'elite') {
      progressToNext = 1.0;
    } else if (stats.tier == 'gold') {
      progressToNext = ((stats.score - 75) / 15).clamp(0.0, 1.0);
    } else if (stats.tier == 'silver') {
      progressToNext = ((stats.score - 60) / 15).clamp(0.0, 1.0);
    } else {
      progressToNext = (stats.score / 60).clamp(0.0, 1.0);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tierColor.withValues(alpha: 0.25), const Color(0xFF1E2030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: tierColor, width: 2),
                ),
                child: Icon(tierIcon, color: tierColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          stats.tierEmoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${stats.tierLabel} Driver',
                          style: TextStyle(
                            color: tierColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Driver Score: ${stats.score.toStringAsFixed(0)}/100',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          if (stats.tier != 'elite') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  stats.tierLabel,
                  style: TextStyle(
                    color: tierColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$nextTierScore pts to next tier',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progressToNext,
                backgroundColor: const Color(0xFF2A2D3E),
                valueColor: AlwaysStoppedAnimation(tierColor),
                minHeight: 8,
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_rounded, color: tierColor, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Max tier reached!',
                    style: TextStyle(
                      color: tierColor,
                      fontWeight: FontWeight.w700,
                    ),
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

// ─── Score Breakdown ──────────────────────────────────────────────────────────

class _ScoreBreakdown extends StatelessWidget {
  final DriverStats stats;
  const _ScoreBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    // Values are stored as 0–100 percentages; scale to weighted score points.
    final completionScore = ((stats.completionRate / 100) * 30).round();
    final onTimeScore = ((stats.onTimeRate / 100) * 25).round();
    final ratingScore = ((stats.avgCustomerRating / 5.0) * 25).round();
    final acceptanceScore = ((stats.acceptanceRate / 100) * 20).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Score Breakdown',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _ScoreRow(
            label: 'Completion (30%)',
            value: completionScore,
            maxValue: 30,
            color: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 8),
          _ScoreRow(
            label: 'On-Time (25%)',
            value: onTimeScore,
            maxValue: 25,
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 8),
          _ScoreRow(
            label: 'Customer Rating (25%)',
            value: ratingScore,
            maxValue: 25,
            color: const Color(0xFFFBBF24),
          ),
          const SizedBox(height: 8),
          _ScoreRow(
            label: 'Acceptance (20%)',
            value: acceptanceScore,
            maxValue: 20,
            color: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1117),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Total: ',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                Text(
                  '${stats.score.toStringAsFixed(0)}/100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
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

class _ScoreRow extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            Text(
              '$value/$maxValue',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: maxValue > 0 ? value / maxValue : 0,
            backgroundColor: const Color(0xFF2A2D3E),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ─── Rate Card ────────────────────────────────────────────────────────────────

class _RateCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  const _RateCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Values are stored as 0–100 percentages in the DB (e.g. 85.0 = 85%)
    final percentage = value.round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            '$percentage%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.grey[700], fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Stat Tile ────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[700], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tier Benefits ────────────────────────────────────────────────────────────

class _TierBenefits extends StatelessWidget {
  final String tier;
  final double bonusMultiplier;
  final bool priorityDispatch;
  const _TierBenefits({
    required this.tier,
    required this.bonusMultiplier,
    required this.priorityDispatch,
  });

  @override
  Widget build(BuildContext context) {
    final benefits = <_Benefit>[
      _Benefit(
        'Earnings Bonus',
        '${((bonusMultiplier - 1) * 100).toStringAsFixed(0)}% bonus on base pay',
        Icons.trending_up_rounded,
        const Color(0xFF22C55E),
        true,
      ),
      _Benefit(
        'Priority Dispatch',
        'See high-value orders first',
        Icons.flash_on_rounded,
        const Color(0xFFFBBF24),
        priorityDispatch,
      ),
      _Benefit(
        'Surge Access',
        'Get surge zone orders automatically',
        Icons.bolt_rounded,
        const Color(0xFFF97316),
        tier == 'gold' || tier == 'elite',
      ),
      _Benefit(
        'Elite Badge',
        'Visible to customers',
        Icons.verified_rounded,
        const Color(0xFFE879F9),
        tier == 'elite',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFFBBF24),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Tier Benefits',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: b.unlocked
                          ? b.color.withValues(alpha: 0.12)
                          : const Color(0xFF2A2D3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      b.icon,
                      color: b.unlocked ? b.color : Colors.grey[700],
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.title,
                          style: TextStyle(
                            color: b.unlocked ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          b.subtitle,
                          style: TextStyle(
                            color: b.unlocked
                                ? Colors.grey[400]
                                : Colors.grey[700],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    b.unlocked
                        ? Icons.check_circle_rounded
                        : Icons.lock_rounded,
                    color: b.unlocked ? b.color : Colors.grey[700],
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final bool unlocked;
  const _Benefit(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.unlocked,
  );
}

// ─── Recommendations Card ─────────────────────────────────────────────────────

class _RecommendationsCard extends StatelessWidget {
  final DriverRecommendations recs;
  const _RecommendationsCard({required this.recs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF818CF8),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Smart Tips',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recs.tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outlined,
                      color: Color(0xFF818CF8),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(
                          color: Color(0xFFA5B4FC),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (recs.surgeZones.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Active Surge Zones',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            ...recs.surgeZones.map(
              (zone) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFFF59E0B),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      zone.name,
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
