import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Terms & Conditions',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Acceptance of Terms',
          body:
              'By downloading, installing, or using the 7Dash mobile application ("App") operated by SevenDash Technologies Limited ("7Dash", "we", "us", "our"), you agree to be bound by these Terms & Conditions. If you do not agree to these terms, do not use the App.',
        ),
        LegalSection(
          heading: '2. Eligibility',
          body:
              'You must be at least 18 years of age to use 7Dash. By using the App, you represent and warrant that you are 18 or older and have the legal capacity to enter into these Terms.',
        ),
        LegalSection(
          heading: '3. Account Registration',
          body:
              'You must create an account to access most features. You are responsible for maintaining the confidentiality of your credentials and for all activity under your account. Notify us immediately at support@7dash.app if you suspect unauthorized access.',
        ),
        LegalSection(
          heading: '4. Customer Responsibilities',
          body:
              'As a customer, you agree to:\n\n'
              '• Provide accurate delivery addresses and contact information.\n'
              '• Be present or make arrangements for order receipt at the designated delivery location.\n'
              '• Not order items you are not legally permitted to purchase or receive.\n'
              '• Treat drivers, restaurant staff, and support agents with respect.\n'
              '• Not abuse refund, dispute, or cancellation processes.',
        ),
        LegalSection(
          heading: '5. Driver Responsibilities',
          body:
              'As a driver partner, you agree to:\n\n'
              '• Maintain a valid driver\'s licence and comply with all applicable traffic laws.\n'
              '• Maintain appropriate vehicle insurance as required by local regulations.\n'
              '• Complete deliveries and rides in a timely, professional manner.\n'
              '• Not accept orders or rides while intoxicated or impaired.\n'
              '• Comply with the Driver Safety Policy available in the app.\n'
              '• Accurately report your location while on duty.',
        ),
        LegalSection(
          heading: '6. Restaurant & Provider Responsibilities',
          body:
              'As a restaurant or service provider partner, you agree to:\n\n'
              '• Maintain current food handler certificates and applicable business licences.\n'
              '• Keep menu items, pricing, and availability up to date in the dashboard.\n'
              '• Prepare and package orders to the standard expected by customers.\n'
              '• Respond to incoming orders within the agreed acceptance window.\n'
              '• Comply with the Restaurant & Provider Partner Terms in the Legal Center.',
        ),
        LegalSection(
          heading: '7. Payments',
          body:
              'All payments are processed securely by Stripe. By placing an order or booking a service, you authorize 7Dash to charge your selected payment method for the total amount shown at checkout, including item prices, delivery fees, service fees, applicable taxes, and tip if added. Payments are denominated in USD unless otherwise indicated. We do not store full card numbers.',
        ),
        LegalSection(
          heading: '8. Delivery Fees & Service Fees',
          body:
              'Delivery fees are calculated based on distance and may include a base fee, per-mile rate, and peak-hour surcharge. A platform service fee is applied to each order. These fees are disclosed at checkout before you confirm payment. Fees are non-refundable except in cases covered by our Refund Policy.',
        ),
        LegalSection(
          heading: '9. Promotions & Credits',
          body:
              'Promotional codes, referral credits, and loyalty points are governed by their individual terms and may not be combined unless explicitly stated. We reserve the right to modify, suspend, or discontinue any promotion at any time without notice. Misuse of promotions may result in account suspension.',
        ),
        LegalSection(
          heading: '10. Cancellations & Refunds',
          body:
              'Cancellations and refunds are governed by our Cancellation Policy and Refund Policy, both available in the Legal Center. By placing an order or booking, you agree to those policies.',
        ),
        LegalSection(
          heading: '11. Subscriptions',
          body:
              '7Dash+ subscription plans are billed on a recurring basis. By subscribing, you authorize us to charge your payment method automatically at the start of each billing period. You may cancel at any time; cancellations take effect at the end of the current billing period. See Subscription Terms in the Legal Center for full details.',
        ),
        LegalSection(
          heading: '12. Prohibited Behavior',
          body:
              'You may not:\n\n'
              '• Use the App for any unlawful purpose.\n'
              '• Harass, threaten, or discriminate against drivers, customers, or staff.\n'
              '• Attempt to circumvent or manipulate pricing, fees, or the rating system.\n'
              '• Upload content that is defamatory, obscene, or infringes third-party rights.\n'
              '• Reverse engineer or attempt to gain unauthorized access to the App or its systems.\n'
              '• Create multiple accounts to abuse promotional offers.\n'
              '• Use the App to facilitate illegal transactions.',
        ),
        LegalSection(
          heading: '13. Intellectual Property',
          body:
              'All content, trademarks, logos, and software in the App are owned by or licensed to 7Dash and are protected by applicable intellectual property laws. You may not reproduce, distribute, or create derivative works without our written permission.',
        ),
        LegalSection(
          heading: '14. Limitation of Liability',
          body:
              'To the fullest extent permitted by law, 7Dash shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the App. 7Dash acts as a technology platform connecting customers, drivers, and providers; we are not liable for the quality, safety, or legality of products or services provided by third-party partners.',
        ),
        LegalSection(
          heading: '15. Account Suspension & Termination',
          body:
              'We reserve the right to suspend or terminate accounts that violate these Terms, engage in fraudulent activity, abuse our platform, or pose a risk to other users. You may delete your account at any time via Settings → Delete Account.',
        ),
        LegalSection(
          heading: '16. Governing Law',
          body:
              'These Terms are governed by the laws of the Cayman Islands. Any disputes shall be resolved in the courts of competent jurisdiction in the Cayman Islands.',
        ),
        LegalSection(
          heading: '17. Changes to Terms',
          body:
              'We may update these Terms periodically. Continued use of the App after changes are posted constitutes acceptance. We will notify you of material changes through the app.',
        ),
        LegalSection(
          heading: '18. Contact',
          body:
              'Questions about these Terms? Contact us at support@7dash.app or via Settings → Contact Support.',
        ),
      ],
    );
  }
}
