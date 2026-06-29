import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Privacy Policy',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Introduction',
          body:
              'SevenDash Technologies Limited ("7Dash", "we", "us", or "our") operates the 7Dash mobile application and related services (collectively, the "Service"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our Service. By using 7Dash, you agree to the collection and use of information in accordance with this policy.',
        ),
        LegalSection(
          heading: '2. Information We Collect',
          body:
              'We collect the following categories of personal information:\n\n'
              '• Account data: full name, email address, phone number, profile photo, and authentication credentials (handled securely by Supabase Auth).\n\n'
              '• Delivery and order data: delivery addresses, order history, restaurant, grocery, and cart items, payment status, and refund or cancellation history.\n\n'
              '• Location data: your delivery address, real-time driver location while online or assigned to a delivery or ride, pickup and drop-off locations, and ride route data where applicable.\n\n'
              '• Device and app data: device type and model, app version, crash logs, IP address, push notification token, and basic analytics.\n\n'
              '• Payment data: payment processor customer ID, transaction IDs, last 4 digits and card brand as returned by Stripe. We do not store full card numbers, CVV codes, or raw card data.\n\n'
              '• Communication data: in-app chat messages exchanged with drivers or support, support tickets, call metadata if using in-app voice calls (Agora), and any user reports or flagged messages.',
        ),
        LegalSection(
          heading: '3. How We Use Your Information',
          body:
              'We use the information we collect to:\n\n'
              '• Create and manage your account.\n'
              '• Process orders, deliveries, rides, and payments.\n'
              '• Match customers with drivers and service providers.\n'
              '• Send order status updates, driver arrival notifications, and promotional messages (if opted in).\n'
              '• Detect and prevent fraud, abuse, and policy violations.\n'
              '• Improve the app, personalize recommendations, and conduct analytics.\n'
              '• Comply with legal obligations and enforce our Terms & Conditions.\n'
              '• Respond to support requests and resolve disputes.',
        ),
        LegalSection(
          heading: '4. How We Share Your Information',
          body:
              'We may share your information with:\n\n'
              '• Drivers: your delivery address, first name, and contact info needed to complete your order or ride.\n'
              '• Restaurants and grocery stores: your name and order details required to prepare your order.\n'
              '• Service providers: contact and booking information needed to complete your car service or laundry booking.\n'
              '• Payment processors: Stripe receives payment-related data to process transactions. Stripe\'s own privacy policy applies to data they handle.\n'
              '• Analytics and crash reporting services: anonymized or aggregated usage data.\n'
              '• Law enforcement: when required by applicable law, court order, or governmental regulation.\n\n'
              'We do not sell your personal information to third parties.',
        ),
        LegalSection(
          heading: '5. Location Data',
          body:
              'Customer location is used to determine your delivery address and to track order progress. Driver location is collected in real time while the driver is online or actively assigned to a delivery or ride. This location data is used to display arrival estimates, match nearby drivers, and optimize routing. Background location may be collected for drivers actively on a delivery or ride if permitted by your device settings. You may disable location access in your device settings; however, this will limit core functionality.',
        ),
        LegalSection(
          heading: '6. Data Retention',
          body:
              'We retain account data for as long as your account is active. If you delete your account, we will anonymize or remove your personal profile data within 30 days. Transaction and order records may be retained for up to 7 years as required by applicable tax and financial regulations. Chat messages are retained for 90 days to support dispute resolution. You may request immediate deletion of your data by submitting a request through the app or at our data deletion URL.',
        ),
        LegalSection(
          heading: '7. Your Rights',
          body:
              'Depending on your jurisdiction, you may have the right to:\n\n'
              '• Access the personal data we hold about you.\n'
              '• Correct inaccurate personal data.\n'
              '• Request deletion of your personal data.\n'
              '• Withdraw consent for data processing where consent is the basis.\n'
              '• Data portability.\n'
              '• Lodge a complaint with a data protection authority.\n\n'
              'To exercise any of these rights, contact us at support@7dash.app or use the in-app Data Deletion Request feature.',
        ),
        LegalSection(
          heading: '8. Security',
          body:
              'We use industry-standard security measures including TLS encryption in transit, secure authentication via Supabase Auth, role-based access controls, and regular security reviews. While we take reasonable precautions, no method of transmission or storage is 100% secure, and we cannot guarantee absolute security.',
        ),
        LegalSection(
          heading: '9. Children\'s Privacy',
          body:
              'Our Service is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe a child has provided us with personal information, contact us at support@7dash.app and we will promptly delete it.',
        ),
        LegalSection(
          heading: '10. Third-Party Links',
          body:
              'The app may contain links to third-party websites or services that are not operated by us. We have no control over and assume no responsibility for the content, privacy policies, or practices of any third-party sites or services.',
        ),
        LegalSection(
          heading: '11. Changes to This Policy',
          body:
              'We may update this Privacy Policy from time to time. We will notify you of any material changes by posting the new policy in the app and updating the "Last updated" date. Your continued use of the Service after changes are posted constitutes acceptance of the updated policy.',
        ),
        LegalSection(
          heading: '12. Contact Us',
          body:
              'If you have questions about this Privacy Policy or our data practices, contact us at:\n\n'
              'SevenDash Technologies Limited\n'
              'Email: support@7dash.app\n'
              'App: Settings → Contact Support',
        ),
      ],
    );
  }
}
