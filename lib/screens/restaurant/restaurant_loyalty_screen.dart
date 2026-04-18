import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _restaurantLoyaltyStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      restaurantId,
    ) async {
      final client = Supabase.instance.client;

      // Get all delivered orders for this restaurant to find unique customers
      final orders = await client
          .from('orders')
          .select('id, user_id, total_amount')
          .eq('restaurant_id', restaurantId)
          .eq('status', 'delivered');

      final orderList = orders as List;
      final orderIds = orderList.map((o) => o['id'] as String).toList();
      final uniqueCustomerIds = orderList
          .map((o) => o['user_id'] as String)
          .toSet();

      // Get loyalty accounts for customers who ordered from this restaurant
      List loyaltyAccounts = [];
      if (uniqueCustomerIds.isNotEmpty) {
        loyaltyAccounts = await client
            .from('loyalty_accounts')
            .select()
            .inFilter('user_id', uniqueCustomerIds.toList());
      }

      // Get loyalty transactions for this restaurant's orders
      List loyaltyTransactions = [];
      if (orderIds.isNotEmpty) {
        // Batch in groups of 50 to avoid URL length limits
        for (var i = 0; i < orderIds.length; i += 50) {
          final batch = orderIds.sublist(
            i,
            i + 50 > orderIds.length ? orderIds.length : i + 50,
          );
          final txns = await client
              .from('loyalty_transactions')
              .select('*, users:user_id(name)')
              .inFilter('order_id', batch)
              .order('created_at', ascending: false);
          loyaltyTransactions.addAll(txns as List);
        }
      }

      // Compute stats
      final totalCustomers = uniqueCustomerIds.length;
      final loyaltyCustomers = loyaltyAccounts.length;
      final enrollmentRate = totalCustomers > 0
          ? (loyaltyCustomers / totalCustomers * 100)
          : 0.0;

      // Tier breakdown
      int bronze = 0, silver = 0, gold = 0, platinum = 0;
      for (final a in loyaltyAccounts) {
        switch (a['tier'] ?? 'bronze') {
          case 'platinum':
            platinum++;
            break;
          case 'gold':
            gold++;
            break;
          case 'silver':
            silver++;
            break;
          default:
            bronze++;
        }
      }

      // Points earned/redeemed at this restaurant
      int totalEarned = 0, totalRedeemed = 0;
      for (final t in loyaltyTransactions) {
        final pts = (t['points'] as num?)?.toInt() ?? 0;
        final type = t['type'] as String? ?? '';
        if (type == 'earn') {
          totalEarned += pts;
        } else if (type == 'redeem') {
          totalRedeemed += pts.abs();
        }
      }

      // Repeat customers (ordered more than once)
      final customerOrderCount = <String, int>{};
      for (final o in orderList) {
        final uid = o['user_id'] as String;
        customerOrderCount[uid] = (customerOrderCount[uid] ?? 0) + 1;
      }
      final repeatCustomers = customerOrderCount.values
          .where((c) => c > 1)
          .length;
      final repeatRate = totalCustomers > 0
          ? (repeatCustomers / totalCustomers * 100)
          : 0.0;

      // Recent transactions (top 20)
      final recentTxns = loyaltyTransactions.take(20).toList();

      return {
        'totalCustomers': totalCustomers,
        'loyaltyCustomers': loyaltyCustomers,
        'enrollmentRate': enrollmentRate,
        'repeatCustomers': repeatCustomers,
        'repeatRate': repeatRate,
        'totalEarned': totalEarned,
        'totalRedeemed': totalRedeemed,
        'bronze': bronze,
        'silver': silver,
        'gold': gold,
        'platinum': platinum,
        'recentTransactions': recentTxns,
      };
    });

// ── Screen ───────────────────────────────────────────────────────────────────

class RestaurantLoyaltyScreen extends ConsumerWidget {
  const RestaurantLoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: AppLoadingIndicator());
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const Scaffold(body: AppLoadingIndicator()),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Loyalty & Retention')),
        body: AppErrorState(message: friendlyError(e)),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loyalty & Retention')),
            body: const Center(child: Text('No restaurant found')),
          );
        }

        final statsAsync = ref.watch(
          _restaurantLoyaltyStatsProvider(restaurant.id),
        );

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // ── Header ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Loyalty & Retention',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      restaurant.name,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.loyalty_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Body ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: statsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: AppLoadingIndicator(
                      message: 'Loading loyalty data...',
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppErrorState(
                      message: friendlyError(e),
                      onRetry: () => ref.invalidate(
                        _restaurantLoyaltyStatsProvider(restaurant.id),
                      ),
                    ),
                  ),
                  data: (stats) => _LoyaltyBody(stats: stats),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _LoyaltyBody extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _LoyaltyBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final totalCustomers = stats['totalCustomers'] as int;
    final loyaltyCustomers = stats['loyaltyCustomers'] as int;
    final enrollmentRate = stats['enrollmentRate'] as double;
    final repeatCustomers = stats['repeatCustomers'] as int;
    final repeatRate = stats['repeatRate'] as double;
    final totalEarned = stats['totalEarned'] as int;
    final totalRedeemed = stats['totalRedeemed'] as int;
    final bronze = stats['bronze'] as int;
    final silver = stats['silver'] as int;
    final gold = stats['gold'] as int;
    final platinum = stats['platinum'] as int;
    final recentTxns = stats['recentTransactions'] as List;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Customer Retention Cards ────────────────────────
          Transform.translate(
            offset: const Offset(0, -16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.people_rounded,
                          color: Color(0xFF7C3AED),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Customer Retention',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: 'Total Customers',
                          value: '$totalCustomers',
                          icon: Icons.person_rounded,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricTile(
                          label: 'Repeat Customers',
                          value: '$repeatCustomers',
                          subtitle: '${repeatRate.toStringAsFixed(1)}%',
                          icon: Icons.replay_rounded,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: 'Loyalty Members',
                          value: '$loyaltyCustomers',
                          subtitle: '${enrollmentRate.toStringAsFixed(1)}%',
                          icon: Icons.card_membership_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricTile(
                          label: 'Points Activity',
                          value: '+$totalEarned',
                          subtitle: '-$totalRedeemed redeemed',
                          icon: Icons.stars_rounded,
                          color: const Color(0xFFEC4899),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Tier Distribution ───────────────────────────────
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loyalty Tier Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _TierBar(
                  label: 'Platinum',
                  count: platinum,
                  total: loyaltyCustomers,
                  color: const Color(0xFF7C3AED),
                ),
                const SizedBox(height: 10),
                _TierBar(
                  label: 'Gold',
                  count: gold,
                  total: loyaltyCustomers,
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 10),
                _TierBar(
                  label: 'Silver',
                  count: silver,
                  total: loyaltyCustomers,
                  color: const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 10),
                _TierBar(
                  label: 'Bronze',
                  count: bronze,
                  total: loyaltyCustomers,
                  color: const Color(0xFFD97706),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── How Your Loyalty Program Works ──────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF7C3AED),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'How It Works',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5B21B6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.shopping_bag_rounded,
                  text:
                      'Customers earn ${AppConstants.loyaltyPointsPer100} pts per ${AppConstants.currencySymbol}100 spent',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.redeem_rounded,
                  text:
                      '100 pts = ${AppConstants.currencySymbol}${(100 * AppConstants.loyaltyPointValue).toStringAsFixed(0)} discount',
                ),
                const SizedBox(height: 8),
                const _InfoRow(
                  icon: Icons.trending_up_rounded,
                  text: 'Higher tiers earn points faster with multipliers',
                ),
                const SizedBox(height: 8),
                const _InfoRow(
                  icon: Icons.repeat_rounded,
                  text: 'Rewards drive repeat orders to your restaurant',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Recent Loyalty Transactions ─────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (recentTxns.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No loyalty activity yet',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...recentTxns.map((t) {
                    final type = t['type'] as String? ?? 'earn';
                    final pts = (t['points'] as num?)?.toInt() ?? 0;
                    final desc = t['description'] as String? ?? '';
                    final usersData = t['users'];
                    final userName = usersData is Map
                        ? usersData['name'] as String?
                        : null;
                    final date =
                        DateTime.tryParse(t['created_at'] as String? ?? '') ??
                        DateTime.now();
                    final isEarn = type == 'earn';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color:
                                  (isEarn
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444))
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isEarn
                                  ? Icons.add_circle_outline_rounded
                                  : Icons.remove_circle_outline_rounded,
                              color: isEarn
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  desc.isEmpty
                                      ? (isEarn
                                            ? 'Points Earned'
                                            : 'Points Redeemed')
                                      : desc,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${userName != null ? '$userName · ' : ''}${date.month}/${date.day}/${date.year}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isEarn ? '+' : '-'}${pts.abs()} pts',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isEarn
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _TierBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 14,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7C3AED), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF5B21B6)),
          ),
        ),
      ],
    );
  }
}
