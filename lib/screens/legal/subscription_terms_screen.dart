import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class SubscriptionTermsScreen extends StatelessWidget {
  const SubscriptionTermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Subscription Terms',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. 7Dash+ Subscription Plans',
          body:
              '7Dash offers optional subscription plans ("7Dash+") that provide delivery benefits for a recurring monthly fee. Current plans are displayed in the app on the Subscription screen. Plan details, pricing, and included benefits are subject to change with prior notice.',
        ),
        LegalSection(
          heading: '2. Billing',
          body:
              'Your subscription is billed monthly on the date you first subscribed. The charge appears as "7Dash+" or "SevenDash Technologies" on your payment statement. All charges are in USD unless otherwise indicated. By subscribing, you authorize 7Dash to charge your selected payment method automatically each billing period.',
        ),
        LegalSection(
          heading: '3. What Is Included',
          body:
              'Each plan includes a set number of free or reduced-fee deliveries per month, as described on the plan selection screen. Delivery benefits apply to eligible food and grocery orders placed through the 7Dash app. Benefits do not carry over to the following month and are not transferable.',
        ),
        LegalSection(
          heading: '4. Free Trial',
          body:
              'If a free trial is offered, it will be clearly stated on the subscription screen. You will be charged the standard plan price at the end of the trial period unless you cancel before the trial ends. Only one free trial per user.',
        ),
        LegalSection(
          heading: '5. Automatic Renewal',
          body:
              'Your subscription renews automatically at the end of each billing period unless you cancel. You will not receive a separate notice before each renewal charge. You can view your next renewal date in Settings → Subscription.',
        ),
        LegalSection(
          heading: '6. Cancellation',
          body:
              'You may cancel your subscription at any time from Settings → Subscription → Cancel Subscription. Cancellation takes effect at the end of the current billing period. You retain access to your plan benefits until the end of the period you have already paid for.',
        ),
        LegalSection(
          heading: '7. Refunds',
          body:
              'Subscription fees are non-refundable once a billing period has started. If you believe you were incorrectly charged, contact support@7dash.app within 7 days of the charge and we will investigate.',
        ),
        LegalSection(
          heading: '8. Price Changes',
          body:
              'We may change subscription pricing with at least 30 days\' advance notice. You will receive a notification and email before any price change takes effect. Continuing your subscription after the change date constitutes acceptance of the new price.',
        ),
        LegalSection(
          heading: '9. Payment Failure',
          body:
              'If a subscription payment fails, we will retry the charge and notify you. If payment is not resolved within 7 days, your subscription may be paused or cancelled and benefits will be suspended.',
        ),
        LegalSection(
          heading: '10. Apple & Google Billing',
          body:
              'If you subscribed through the Apple App Store or Google Play Store, billing is managed by Apple or Google under their respective terms. To cancel or manage your subscription, visit your App Store or Play Store subscription settings. 7Dash cannot process refunds for in-app purchases made through these stores; contact Apple or Google support.',
        ),
        LegalSection(
          heading: '11. Contact',
          body:
              'For subscription-related questions, contact us at support@7dash.app or through Settings → Contact Support.',
        ),
      ],
    );
  }
}
