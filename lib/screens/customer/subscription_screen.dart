import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../models/subscription_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/app_logger.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Subscriptions',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          bottom: TabBar(
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(text: 'MealHub+'),
              Tab(text: 'Meal Plans'),
              Tab(text: 'My Subs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DeliverySubscriptionTab(userId: userId),
            _BrowsePlans(userId: userId),
            _MySubscriptions(userId: userId),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Uber One-style Delivery Subscription Tab
// ═══════════════════════════════════════════════════════════════════════════════

class _DeliverySubscriptionTab extends ConsumerStatefulWidget {
  final String userId;
  const _DeliverySubscriptionTab({required this.userId});

  @override
  ConsumerState<_DeliverySubscriptionTab> createState() =>
      _DeliverySubscriptionTabState();
}

class _DeliverySubscriptionTabState
    extends ConsumerState<_DeliverySubscriptionTab> {
  bool _subscribing = false;

  Future<void> _subscribe(String planType) async {
    if (_subscribing) return;
    setState(() => _subscribing = true);

    try {
      final service = ref.read(subscriptionServiceProvider);
      final result = await service.createDeliverySubscription(plan: planType);

      if (result == null) throw Exception('No response from server');

      final clientSecret = result['client_secret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('Missing client secret');
      }

      // Present Stripe Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: AppConstants.appName,
          style: ThemeMode.system,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // Payment succeeded — subscription is now 'pending', will become 'active'
      // via Stripe webhook. Realtime listener on activeSubscriptionProvider
      // will auto-update when that happens.
      ref.invalidate(activeSubscriptionProvider);
      if (mounted) {
        AppSnackbar.success(
          context,
          'Payment successful! Your MealHub+ ${planType == 'pro' ? 'Pro' : 'Basic'} is activating...',
        );
      }
    } on StripeException catch (e) {
      if (e.error.code != FailureCode.Canceled && mounted) {
        AppSnackbar.error(
          context,
          e.error.localizedMessage ?? 'Payment failed',
        );
      }
    } catch (e) {
      AppLogger.error('Subscription error: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Subscription failed: $e');
      }
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  Future<void> _cancelSub(String subscriptionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel MealHub+?'),
        content: const Text(
          'You\'ll keep your remaining deliveries and benefits until '
          'the end of your current billing period. No further charges.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel Plan',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref
        .read(subscriptionServiceProvider)
        .cancelDeliverySubscription(subscriptionId);
    ref.invalidate(activeSubscriptionProvider);
    if (mounted) {
      ok
          ? AppSnackbar.success(
              context,
              'Plan will cancel at end of billing period',
            )
          : AppSnackbar.error(context, 'Could not cancel subscription');
    }
  }

  Future<void> _reactivateSub(String subscriptionId) async {
    final ok = await ref
        .read(subscriptionServiceProvider)
        .reactivateDeliverySubscription(subscriptionId);
    ref.invalidate(activeSubscriptionProvider);
    if (mounted) {
      ok
          ? AppSnackbar.success(context, 'Subscription reactivated!')
          : AppSnackbar.error(context, 'Could not reactivate');
    }
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(activeSubscriptionProvider);

    return subAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (activeSub) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MealHub+',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Free delivery on every eligible order',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Active / Pending subscription banner
              if (activeSub != null && activeSub.isActive) ...[
                _ActiveSubBanner(
                  sub: activeSub,
                  onCancel: () => _cancelSub(activeSub.id),
                  onReactivate: activeSub.isCancelling
                      ? () => _reactivateSub(activeSub.id)
                      : null,
                ),
                const SizedBox(height: 20),
              ],

              // Pending activation banner
              if (activeSub != null && activeSub.isPending) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Activating ${activeSub.planLabel}...',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Payment received. Your subscription will be ready in moments.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Plan cards
              if (activeSub == null) ...[
                const Text(
                  'Choose your plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _PlanOptionCard(
                  title: 'MealHub Basic',
                  price: AppConstants.subscriptionBasicPrice,
                  deliveries: AppConstants.subscriptionBasicDeliveries,
                  perks: const [
                    '\$0 delivery on eligible restaurants',
                    '50% off service fee',
                    'Priority support',
                  ],
                  color: const Color(0xFF2196F3),
                  subscribing: _subscribing,
                  onSubscribe: () => _subscribe('basic'),
                ),
                const SizedBox(height: 12),
                _PlanOptionCard(
                  title: 'MealHub Pro',
                  price: AppConstants.subscriptionProPrice,
                  deliveries: AppConstants.subscriptionProDeliveries,
                  perks: const [
                    '\$0 delivery on ALL restaurants',
                    '50% off service fee',
                    'Priority support',
                    'Exclusive member deals',
                  ],
                  color: const Color(0xFF6C63FF),
                  recommended: true,
                  subscribing: _subscribing,
                  onSubscribe: () => _subscribe('pro'),
                ),
              ],

              const SizedBox(height: 24),
              // FAQ
              const Text(
                'How it works',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _FaqItem(
                q: 'How does free delivery work?',
                a:
                    'Each month you get a set number of free deliveries. '
                    'When you order from an eligible restaurant with a minimum '
                    'cart value, delivery is automatically free.',
              ),
              _FaqItem(
                q: 'What happens when I run out of deliveries?',
                a:
                    'Standard delivery fees apply once your monthly deliveries '
                    'are used. They reset on your next billing date.',
              ),
              _FaqItem(
                q: 'Can I cancel anytime?',
                a:
                    'Yes. Cancel any time and keep your remaining deliveries '
                    'until the end of the billing period.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveSubBanner extends StatelessWidget {
  final UserSubscription sub;
  final VoidCallback onCancel;
  final VoidCallback? onReactivate;
  const _ActiveSubBanner({
    required this.sub,
    required this.onCancel,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = sub.currentPeriodEnd != null
        ? sub.currentPeriodEnd!.difference(DateTime.now()).inDays
        : 0;
    final isCancelling = sub.isCancelling;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isCancelling
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981))
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCancelling ? 'CANCELLING' : 'ACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCancelling
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  sub.planLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (isCancelling && onReactivate != null)
                  TextButton(
                    onPressed: onReactivate,
                    child: const Text(
                      'Keep Plan',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed: onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatBox(
                  label: 'Deliveries Left',
                  value: '${sub.deliveriesRemaining}',
                  icon: Icons.local_shipping,
                ),
                const SizedBox(width: 12),
                _StatBox(
                  label: 'Used',
                  value: '${sub.deliveriesUsed}',
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 12),
                _StatBox(
                  label: 'Days Left',
                  value: '$daysLeft',
                  icon: Icons.calendar_today,
                ),
              ],
            ),
            if (sub.currentPeriodEnd != null) ...[
              const SizedBox(height: 8),
              Text(
                isCancelling
                    ? 'Cancels ${DateFormat('MMM d, y').format(sub.currentPeriodEnd!)}'
                    : 'Renews ${DateFormat('MMM d, y').format(sub.currentPeriodEnd!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isCancelling
                      ? const Color(0xFFF59E0B)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  final String title;
  final double price;
  final int deliveries;
  final List<String> perks;
  final Color color;
  final bool recommended;
  final bool subscribing;
  final VoidCallback onSubscribe;

  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.deliveries,
    required this.perks,
    required this.color,
    this.recommended = false,
    required this.subscribing,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: recommended
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recommended) const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${AppConstants.currencySymbol}${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4, left: 2),
                      child: Text(
                        '/month',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$deliveries free deliveries per month',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 12),
                ...perks.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: subscribing ? null : onSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: subscribing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Subscribe to $title',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (recommended)
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: const Text(
                  'BEST VALUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        q,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            a,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                  '${AppConstants.currencySymbol}${plan.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '/${plan.frequency}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
    if (sub.isCancelling) return const Color(0xFFF59E0B);
    switch (sub.status) {
      case 'active':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFF3B82F6);
      case 'paused':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  String get _statusLabel {
    if (sub.isCancelling) return 'CANCELLING';
    if (sub.isPending) return 'ACTIVATING';
    return sub.status.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = sub.mealPlan;
    final isDeliverySub = sub.isDeliverySubscription;
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
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (isDeliverySub)
                  Text(
                    '${sub.deliveriesRemaining} deliveries left',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
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
              isDeliverySub ? sub.planLabel : (plan?.name ?? 'Meal Plan'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            // Show period end for delivery subscriptions
            if (isDeliverySub && sub.currentPeriodEnd != null) ...[
              const SizedBox(height: 4),
              Text(
                sub.isCancelling
                    ? 'Cancels ${DateFormat('MMM d, y').format(sub.currentPeriodEnd!)}'
                    : 'Renews ${DateFormat('MMM d, y').format(sub.currentPeriodEnd!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: sub.isCancelling
                      ? const Color(0xFFF59E0B)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!isDeliverySub && sub.nextDelivery != null) ...[
              const SizedBox(height: 4),
              Text(
                'Next delivery: ${DateFormat('MMM d, y').format(sub.nextDelivery!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                // Reactivate button for cancelling delivery subscriptions
                if (isDeliverySub && sub.isCancelling)
                  _ActionBtn(
                    label: 'Keep Plan',
                    icon: Icons.refresh,
                    color: const Color(0xFF10B981),
                    onTap: () async {
                      await ref
                          .read(subscriptionServiceProvider)
                          .reactivateDeliverySubscription(sub.id);
                      ref.invalidate(activeSubscriptionProvider);
                      onAction();
                    },
                  ),
                // Pause for non-delivery active subs
                if (!isDeliverySub && sub.status == 'active')
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
                // Cancel — route through Stripe for delivery subs
                if (sub.status != 'cancelled' && !sub.isCancelling)
                  _ActionBtn(
                    label: 'Cancel',
                    icon: Icons.cancel,
                    color: Colors.red,
                    onTap: () async {
                      final message = isDeliverySub
                          ? 'You\'ll keep benefits until the end of your billing period.'
                          : 'This will cancel your meal plan subscription.';
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancel Subscription?'),
                          content: Text(message),
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
                        if (isDeliverySub) {
                          // Route through Stripe edge function
                          await ref
                              .read(subscriptionServiceProvider)
                              .cancelDeliverySubscription(sub.id);
                          ref.invalidate(activeSubscriptionProvider);
                        } else {
                          await ref
                              .read(subscriptionServiceProvider)
                              .cancelSubscription(sub.id);
                        }
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
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
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
