import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/subscription_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Meal Plans',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: AppTheme.textPrimary,
          bottom: TabBar(
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: [
              Tab(text: 'Browse Plans'),
              Tab(text: 'My Subscriptions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BrowsePlans(userId: userId),
            _MySubscriptions(userId: userId),
          ],
        ),
      ),
    );
  }
}

// ── Browse Plans ────────────────────────────────────────────

class _BrowsePlans extends ConsumerWidget {
  final String userId;
  const _BrowsePlans({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(availablePlansProvider);
    return plansAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (plans) {
        if (plans.isEmpty) {
          return const AppEmptyState(
            icon: Icons.restaurant_menu,
            title: 'No meal plans available yet',
            subtitle: 'Check back soon for curated meal subscriptions',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: plans.length,
          itemBuilder: (_, i) => _PlanCard(plan: plans[i], userId: userId),
        );
      },
    );
  }
}

class _PlanCard extends ConsumerWidget {
  final MealPlan plan;
  final String userId;
  const _PlanCard({required this.plan, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (plan.description != null)
                        Text(
                          plan.description!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                          maxLines: 2,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(
                  icon: Icons.calendar_today,
                  label: plan.frequencyLabel,
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.fastfood,
                  label: '${plan.mealsPerPeriod} meals',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '\$${plan.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '/${plan.frequency}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    final service = ref.read(subscriptionServiceProvider);
                    final result = await service.subscribe(
                      userId: userId,
                      mealPlanId: plan.id,
                      deliveryAddress: 'Default Address',
                    );
                    if (result != null) {
                      ref.invalidate(userSubscriptionsProvider(userId));
                      if (context.mounted) {
                        AppSnackbar.success(
                          context,
                          'Subscribed successfully!',
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Subscribe',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// ── My Subscriptions ────────────────────────────────────────

class _MySubscriptions extends ConsumerWidget {
  final String userId;
  const _MySubscriptions({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(userSubscriptionsProvider(userId));
    return subsAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (subs) {
        if (subs.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_rounded,
            title: 'No active subscriptions',
            subtitle: 'Browse plans to get started',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: subs.length,
          itemBuilder: (_, i) => _SubscriptionCard(
            sub: subs[i],
            onAction: () => ref.invalidate(userSubscriptionsProvider(userId)),
          ),
        );
      },
    );
  }
}

class _SubscriptionCard extends ConsumerWidget {
  final UserSubscription sub;
  final VoidCallback onAction;
  const _SubscriptionCard({required this.sub, required this.onAction});

  Color get _statusColor {
    switch (sub.status) {
      case 'active':
        return const Color(0xFF10B981);
      case 'paused':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = sub.mealPlan;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sub.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${sub.mealsRemaining} meals left',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan?.name ?? 'Meal Plan',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (sub.nextDelivery != null) ...[
              const SizedBox(height: 4),
              Text(
                'Next delivery: ${DateFormat('MMM d, y').format(sub.nextDelivery!)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (sub.status == 'active')
                  _ActionBtn(
                    label: 'Pause',
                    icon: Icons.pause,
                    onTap: () async {
                      await ref
                          .read(subscriptionServiceProvider)
                          .pauseSubscription(sub.id);
                      onAction();
                    },
                  ),
                if (sub.status == 'paused')
                  _ActionBtn(
                    label: 'Resume',
                    icon: Icons.play_arrow,
                    onTap: () async {
                      await ref
                          .read(subscriptionServiceProvider)
                          .resumeSubscription(sub.id);
                      onAction();
                    },
                  ),
                const SizedBox(width: 8),
                if (sub.status != 'cancelled')
                  _ActionBtn(
                    label: 'Cancel',
                    icon: Icons.cancel,
                    color: Colors.red,
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancel Subscription?'),
                          content: const Text(
                            'This will cancel your meal plan subscription.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Keep'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref
                            .read(subscriptionServiceProvider)
                            .cancelSubscription(sub.id);
                        onAction();
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}
