import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class ProviderTermsScreen extends StatelessWidget {
  const ProviderTermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Restaurant & Provider Terms',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Partner Agreement',
          body:
              'This agreement governs the relationship between SevenDash Technologies Limited ("7Dash") and any restaurant, grocery store, car service provider, laundry provider, or other business partner ("Provider") listed on the 7Dash platform. By registering as a Provider, you accept these terms.',
        ),
        LegalSection(
          heading: '2. Eligibility',
          body:
              'You must hold all licences, permits, health certificates, and insurance required by applicable law to operate your business. Food businesses must maintain current food handler certifications. You must maintain these requirements for the duration of your partnership with 7Dash.',
        ),
        LegalSection(
          heading: '3. Listing and Content',
          body:
              '• You are responsible for the accuracy of your menu items, prices, images, and availability.\n'
              '• Prices listed on 7Dash must match your advertised prices; hidden surcharges are not permitted.\n'
              '• You may not list products you do not have or services you cannot fulfill.\n'
              '• 7Dash reserves the right to remove listings that violate these terms or applicable law.',
        ),
        LegalSection(
          heading: '4. Order Acceptance and Fulfillment',
          body:
              '• Accept or decline incoming orders within the window specified in your dashboard.\n'
              '• Prepare orders accurately and within the estimated time displayed to customers.\n'
              '• Package food and products safely for delivery.\n'
              '• Notify 7Dash promptly if you are unable to fulfill an accepted order.',
        ),
        LegalSection(
          heading: '5. Commission & Fees',
          body:
              '7Dash charges a commission on each completed order as agreed in your onboarding contract. Commission rates and any applicable fees are displayed in your provider dashboard and may be updated with 30 days\' notice. You are responsible for your own tax obligations on earnings received.',
        ),
        LegalSection(
          heading: '6. Payouts',
          body:
              'Earnings are paid out according to the payout schedule selected in your dashboard (daily, weekly, or monthly), subject to minimum payout thresholds. Payouts are processed via Stripe Connect. You must maintain a verified Stripe Connect account to receive payouts. 7Dash is not liable for delays caused by banking or payment processor issues.',
        ),
        LegalSection(
          heading: '7. Quality Standards',
          body:
              '• Food must be prepared to applicable health and safety standards.\n'
              '• Items must be as described and of reasonable quality.\n'
              '• Car services and laundry must be performed to a professional standard.\n'
              '• Providers with consistently low ratings or high complaint rates may be suspended or removed.',
        ),
        LegalSection(
          heading: '8. Customer Data',
          body:
              'Customer delivery addresses and contact information shared with you is for fulfillment purposes only. You may not use customer data for marketing, solicitation, or any purpose other than completing the order.',
        ),
        LegalSection(
          heading: '9. Disputes and Refunds',
          body:
              'If a customer disputes an order, 7Dash will investigate and may issue a refund at our discretion. Chargeback costs resulting from provider error (missing items, incorrect orders, quality issues) may be deducted from future payouts.',
        ),
        LegalSection(
          heading: '10. Suspension and Termination',
          body:
              '7Dash may suspend or terminate a provider account for:\n\n'
              '• Repeated order cancellations.\n'
              '• Consistently low ratings or high complaint rate.\n'
              '• Violation of food safety or applicable law.\n'
              '• Fraudulent activity or misrepresentation.\n'
              '• Failure to maintain required licences.\n\n'
              'Providers may terminate the partnership by providing 14 days\' written notice via support@7dash.app.',
        ),
        LegalSection(
          heading: '11. Intellectual Property',
          body:
              'By uploading images, logos, or other content to the 7Dash platform, you grant 7Dash a non-exclusive, royalty-free licence to display and use that content for the purpose of operating and promoting the platform.',
        ),
        LegalSection(
          heading: '12. Contact',
          body:
              'Questions about your partnership or this agreement? Contact us at support@7dash.app.',
        ),
      ],
    );
  }
}
