import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Refund Policy',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Overview',
          body:
              '7Dash strives to ensure every order and booking meets your expectations. If something goes wrong, we want to make it right. This policy explains when and how refunds are issued.',
        ),
        LegalSection(
          heading: '2. Failed Orders',
          body:
              'If your order is accepted but never delivered due to a system failure or no driver being assigned, you are entitled to a full refund of the order total, delivery fee, and service fee. Refunds will be returned to your original payment method within 5–10 business days.',
        ),
        LegalSection(
          heading: '3. Missing or Incorrect Items',
          body:
              'If items are missing from your order or you receive incorrect items, contact support within 24 hours of delivery. We will verify with the restaurant and, if confirmed, issue a refund or credit for the affected items. Photographic evidence may be requested.',
        ),
        LegalSection(
          heading: '4. Restaurant Cancellation',
          body:
              'If a restaurant cancels your order after acceptance, you will receive a full refund of all amounts paid, including delivery fee and service fee, to your original payment method.',
        ),
        LegalSection(
          heading: '5. Driver-Related Issues',
          body:
              'If a driver fails to deliver your order after pick-up and the order is unaccounted for, you may be eligible for a full or partial refund following investigation. Each case is reviewed individually.',
        ),
        LegalSection(
          heading: '6. Customer Cancellation',
          body:
              'Refunds for customer-initiated cancellations depend on the stage of the order:\n\n'
              '• Cancelled before restaurant accepts: full refund.\n'
              '• Cancelled after restaurant begins preparing: partial refund may apply at our discretion; service fee is non-refundable.\n'
              '• Cancelled after driver is assigned: no refund on the order total; delivery fee may be refunded at our discretion.\n\n'
              'See our Cancellation Policy for full details.',
        ),
        LegalSection(
          heading: '7. Ride Cancellations',
          body:
              'Ride cancellations before a driver accepts your request are fully refunded. Cancellations after driver acceptance or after a wait-time threshold may incur a cancellation fee. See Cancellation Policy for specifics.',
        ),
        LegalSection(
          heading: '8. Car Service & Laundry Cancellations',
          body:
              'Cancellations of car service or laundry bookings made more than 1 hour before the scheduled appointment are fully refunded. Cancellations made within 1 hour of the appointment may incur a fee up to 50% of the service cost.',
        ),
        LegalSection(
          heading: '9. Subscription Refunds',
          body:
              'Subscription fees are non-refundable once a billing period has begun. If you cancel your subscription, it remains active until the end of the current period. If you believe you were incorrectly charged, contact support within 7 days of the charge.',
        ),
        LegalSection(
          heading: '10. Refund Processing Time',
          body:
              'Approved refunds to the original payment method typically take 5–10 business days, depending on your bank or card issuer. Store credits are applied immediately to your 7Dash wallet and can be used on your next order.',
        ),
        LegalSection(
          heading: '11. Store Credits vs. Original Payment Method',
          body:
              'In some cases, at our discretion, we may offer store credits as an alternative to a payment method refund. Store credits do not expire and can be applied to any future order. If you prefer a refund to your original payment method, contact support.',
        ),
        LegalSection(
          heading: '12. When Refunds May Be Denied',
          body:
              'Refunds may be denied if:\n\n'
              '• The report is made more than 24 hours after delivery (except where otherwise specified).\n'
              '• The claim cannot be verified.\n'
              '• The issue resulted from incorrect delivery information provided by the customer.\n'
              '• The account has a history of excessive refund claims indicating abuse.\n'
              '• The order was cancelled after food preparation was completed.',
        ),
        LegalSection(
          heading: '13. How to Request a Refund',
          body:
              'To request a refund, go to Orders → select the relevant order → Report an Issue, or contact us at support@7dash.app. Include your order number and a description of the issue. We aim to respond within 24–48 hours.',
        ),
      ],
    );
  }
}
