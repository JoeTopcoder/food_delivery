import '../../../utils/est_datetime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../providers/rewards/membership_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

/// HotBite+ membership hub — status, benefits and plans, all from real data.
/// Payment/activation is handled by the membership checkout (next phase); this
/// screen presents status and plans and never grants benefits on its own.
class HotBitePlusScreen extends ConsumerWidget {
  const HotBitePlusScreen({super.key});

  static const _gold = Color(0xFFEAB308);
  static const _flame = Color(0xFFFF5A1F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(hotbitePlusEnabledProvider);
    final statusAsync = ref.watch(membershipStatusProvider);
    final plansAsync = ref.watch(membershipPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('HotBite+')),
      body: !enabled
          ? const _Empty(text: 'HotBite+ is not available yet. Check back soon.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(status: statusAsync.valueOrNull),
                if (statusAsync.valueOrNull?.isActive == true)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _cancelMembership(context, ref),
                      child: const Text('Cancel auto-renewal'),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text('Member benefits',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ...const [
                  'Exclusive restaurant deals',
                  'Exclusive supermarket deals',
                  'Member-only prices',
                  'Delivery benefits',
                  'Priority benefits',
                  'Member vouchers',
                ].map((b) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF16A34A), size: 20),
                        const SizedBox(width: 10),
                        Text(b, style: const TextStyle(fontSize: 14)),
                      ]),
                    )),
                const SizedBox(height: 24),
                Text(
                  statusAsync.valueOrNull?.isActive == true
                      ? 'Renew or upgrade'
                      : 'Choose your plan',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                plansAsync.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator())),
                  error: (_, __) =>
                      const _Empty(text: 'Could not load plans.'),
                  data: (plans) {
                    if (plans.isEmpty) {
                      return const _Empty(text: 'No plans available yet.');
                    }
                    return Column(
                      children: [for (final p in plans) _PlanCard(plan: p)],
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

Future<void> _cancelMembership(BuildContext context, WidgetRef ref) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel auto-renewal?'),
      content: const Text(
        'Your HotBite+ stays active until the end of the current billing '
        'period, then it will not renew.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel renewal')),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  try {
    final res = await Supabase.instance.client.functions.invoke(
      'stripe/subscription',
      body: {'action': 'membership_cancel'},
    );
    final data = res.data as Map?;
    if (res.status == 200 && data?['success'] == true) {
      ref.invalidate(membershipStatusProvider);
      if (context.mounted) {
        AppSnackbar.success(
            context, 'Auto-renewal cancelled. You keep HotBite+ until the period ends.');
      }
    } else if (context.mounted) {
      AppSnackbar.error(
          context, (data?['error'] as String?) ?? 'Could not cancel.');
    }
  } catch (e) {
    if (context.mounted) AppSnackbar.error(context, friendlyError(e));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({this.status});
  final MembershipStatus? status;

  @override
  Widget build(BuildContext context) {
    final active = status?.isActive ?? false;
    final expired = status != null && !active && status!.status != null;
    final gradient = active
        ? const [Color(0xFF1F2937), Color(0xFF111827)]
        : [
            HotBitePlusScreen._flame.withValues(alpha: 0.9),
            const Color(0xFFEA580C)
          ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: gradient),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.workspace_premium_rounded,
                color: HotBitePlusScreen._gold, size: 24),
            const SizedBox(width: 8),
            const Text('HOTBITE+',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            const Spacer(),
            if (active)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('ACTIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 10),
          if (active) ...[
            Text('${status?.planName ?? ''} membership',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            if (status?.endDate != null)
              Text(
                'Active until ${DateFormat('MMM d, yyyy').format(toJamaicaOf(status!.endDate!.toLocal()))}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
          ] else ...[
            Text(
              expired ? 'Your membership has expired.' : 'Join HotBite+',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            const Text(
              'Unlock exclusive restaurant & supermarket deals for less.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});
  final MembershipPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sym = AppConstants.currencySymbol;
    final rec = plan.isRecommended;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rec
              ? HotBitePlusScreen._flame
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          width: rec ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(plan.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  if (rec) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: HotBitePlusScreen._flame,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('RECOMMENDED',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('${plan.durationDays} days',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Text('$sym${plan.price.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: HotBitePlusScreen._flame)),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _subscribe(context, ref),
            style: FilledButton.styleFrom(
                backgroundColor: HotBitePlusScreen._flame),
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    final sym = AppConstants.currencySymbol;
    // Recurring subscription: Stripe charges the customer's saved card now and
    // every month. Activation/renewal is server-side (membership_subscribe +
    // the subscription webhook); the client never grants membership itself.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Subscribe to HotBite+ — ${plan.name}'),
        content: Text(
          'Pay $sym${plan.price.toStringAsFixed(0)} now for your first month. '
          'It then auto-renews at $sym${plan.price.toStringAsFixed(0)}/month on '
          'the card you pay with, until you cancel.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: HotBitePlusScreen._flame),
            child: Text('Subscribe $sym${plan.price.toStringAsFixed(0)}/mo'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var spinnerOpen = true;
    void closeSpinner() {
      if (spinnerOpen && context.mounted) {
        spinnerOpen = false;
        Navigator.pop(context);
      }
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'stripe/subscription',
        body: {
          'action': 'membership_subscribe',
          'membership_plan_id': plan.id,
        },
      );
      final data = res.data as Map?;
      closeSpinner();
      if (res.status != 200 || data?['success'] != true) {
        final msg = (data?['error'] as String?) ??
            'Could not start your subscription.';
        if (context.mounted) AppSnackbar.error(context, msg);
        return;
      }
      final clientSecret = data?['client_secret'] as String?;
      if (clientSecret == null) {
        if (context.mounted) {
          AppSnackbar.error(context, 'Could not start the first payment.');
        }
        return;
      }

      // First payment is collected interactively via the Stripe Payment Sheet.
      // The card used is saved, so Stripe auto-charges it every 30 days.
      if (Stripe.publishableKey.isEmpty) {
        Stripe.publishableKey = AppConstants.stripePublishableKey;
        Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
        await Stripe.instance.applySettings();
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: AppConstants.cardMerchantName,
          customerId: data?['customer_id'] as String?,
          customerEphemeralKeySecret: data?['ephemeral_key'] as String?,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      ref.invalidate(membershipStatusProvider);
      if (context.mounted) {
        AppSnackbar.success(
            context, "You're subscribed to HotBite+! It auto-renews monthly.");
      }
    } on StripeException catch (e) {
      closeSpinner();
      // User cancelled the sheet or the card was declined.
      if (context.mounted) {
        AppSnackbar.error(
            context, e.error.localizedMessage ?? 'Payment was not completed.');
      }
    } catch (e) {
      closeSpinner();
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)))),
      );
}
