import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class CancellationPolicyScreen extends StatelessWidget {
  const CancellationPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Cancellation Policy',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Food & Grocery Orders',
          body:
              '• Before restaurant accepts: You may cancel at no charge and receive a full refund.\n\n'
              '• After restaurant accepts but before preparation starts: Cancellation is permitted; refund is at 7Dash\'s discretion. The service fee is non-refundable.\n\n'
              '• After preparation has started: Cancellation is generally not permitted. Contact support if you have an emergency; partial refunds are at our discretion.\n\n'
              '• After driver is assigned: Cancellation is not available through the app. Contact support; the delivery fee and service fee are non-refundable.',
        ),
        LegalSection(
          heading: '2. Ride Cancellations',
          body:
              '• Before driver accepts: Free cancellation, full refund if any charge was made.\n\n'
              '• After driver accepts (within 2 minutes): Free cancellation.\n\n'
              '• After driver accepts (2–5 minutes): A small cancellation fee may apply.\n\n'
              '• After driver is en route for more than 5 minutes or has arrived: A cancellation fee applies. The exact fee is shown in the app at the time of cancellation.\n\n'
              '• No-show: If you do not meet the driver within the allowed wait time, the ride may be marked as a no-show and a fee applies.',
        ),
        LegalSection(
          heading: '3. Car Service Bookings',
          body:
              '• More than 1 hour before scheduled appointment: Full refund.\n\n'
              '• Within 1 hour of scheduled appointment: Cancellation fee up to 50% of the service price may apply.\n\n'
              '• After the service provider has arrived or started: No refund.',
        ),
        LegalSection(
          heading: '4. Laundry Bookings',
          body:
              '• More than 1 hour before scheduled pickup: Full refund.\n\n'
              '• Within 1 hour of scheduled pickup: A cancellation fee may apply.\n\n'
              '• After driver has arrived for pickup: No refund on booking fee.',
        ),
        LegalSection(
          heading: '5. Package Delivery',
          body:
              'Package delivery orders may be cancelled before a driver accepts. Once a driver accepts and is en route, cancellation is not available. Contact support for exceptional circumstances.',
        ),
        LegalSection(
          heading: '6. Subscriptions',
          body:
              'You may cancel your 7Dash+ subscription at any time. Your subscription remains active until the end of the current billing period. No partial-month refunds are issued. To cancel, go to Settings → Subscription → Cancel Subscription.',
        ),
        LegalSection(
          heading: '7. Provider-Initiated Cancellations',
          body:
              'If a restaurant, driver, or service provider cancels your confirmed booking, you will receive a full refund of all amounts paid, including fees. We will attempt to reassign another provider where possible.',
        ),
        LegalSection(
          heading: '8. Cancellation Fees',
          body:
              'Where a cancellation fee applies, the amount is shown in the app before you confirm the cancellation. Cancellation fees are charged to compensate partners for time and resources already committed. These fees are non-refundable.',
        ),
        LegalSection(
          heading: '9. How to Cancel',
          body:
              'To cancel an active order or ride, open the order or ride detail screen and tap "Cancel". If the cancel option is unavailable, the order has progressed past the cancellation window. For assistance, contact support@7dash.app.',
        ),
      ],
    );
  }
}
