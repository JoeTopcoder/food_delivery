import 'package:flutter/material.dart';
import 'legal_helpers.dart';

class DriverSafetyPolicyScreen extends StatelessWidget {
  const DriverSafetyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPolicyScreen(
      title: 'Driver Safety Policy',
      lastUpdated: 'June 2026',
      sections: [
        LegalSection(
          heading: '1. Purpose',
          body:
              'This Driver Safety Policy applies to all delivery and ride-sharing partners ("drivers") operating on the 7Dash platform. It establishes minimum safety standards to protect drivers, customers, and the public.',
        ),
        LegalSection(
          heading: '2. Vehicle Requirements',
          body:
              '• Your vehicle must be legally registered and roadworthy.\n'
              '• You must carry at minimum the legally required vehicle insurance in your jurisdiction.\n'
              '• Motorcycles must have a valid motorcycle endorsement.\n'
              '• Vehicles used for ride-sharing must pass any additional inspections required by local regulations.\n'
              '• Maintain your vehicle in safe operating condition — brakes, lights, tyres, and seatbelts must be functional at all times.',
        ),
        LegalSection(
          heading: '3. Driver Conduct',
          body:
              '• Never drive under the influence of alcohol, drugs, or any substance that impairs judgment or reaction time.\n'
              '• Do not use a handheld phone while driving; use hands-free devices only.\n'
              '• Obey all traffic laws, speed limits, and road signs.\n'
              '• Do not accept more simultaneous deliveries than you can safely manage.\n'
              '• Treat all customers and other road users with courtesy and respect.',
        ),
        LegalSection(
          heading: '4. Fatigue and Hours',
          body:
              'Do not drive if you are excessively fatigued. Take regular breaks during long shifts. 7Dash may automatically notify you to take a break if you have been continuously active beyond recommended hours. Your safety is more important than any individual delivery.',
        ),
        LegalSection(
          heading: '5. Customer Interactions',
          body:
              '• Maintain professional conduct at all times.\n'
              '• Do not enter a customer\'s home uninvited — deliver to the door unless instructed otherwise.\n'
              '• Do not record customers without consent.\n'
              '• For ride passengers: do not engage in discriminatory, harassing, or threatening behavior.\n'
              '• Verify passenger identity or order PIN before handover if required by the app.',
        ),
        LegalSection(
          heading: '6. Reporting Incidents',
          body:
              'If you are involved in an accident, witness criminal activity, or feel unsafe during a delivery or ride, end the trip safely and contact emergency services first. Then report the incident to 7Dash through the app or at support@7dash.app. We will work with you on next steps.',
        ),
        LegalSection(
          heading: '7. Zero-Tolerance Behaviors',
          body:
              'The following will result in immediate account suspension and possible legal referral:\n\n'
              '• Driving under the influence.\n'
              '• Theft of orders, packages, or customer property.\n'
              '• Physical or verbal assault of any customer, partner, or road user.\n'
              '• Sexual harassment or assault.\n'
              '• Fraudulent trip or delivery claims.\n'
              '• Sharing account access with another person.',
        ),
        LegalSection(
          heading: '8. Background Checks',
          body:
              'All driver applicants are subject to a background check before approval. Drivers must notify 7Dash of any changes to their criminal record or driving record. 7Dash reserves the right to deactivate accounts that no longer meet safety standards.',
        ),
        LegalSection(
          heading: '9. Insurance Disclaimer',
          body:
              '7Dash does not provide vehicle insurance for drivers. You are responsible for maintaining adequate coverage. Some jurisdictions require specific ride-sharing insurance endorsements; it is your responsibility to comply with local insurance laws.',
        ),
        LegalSection(
          heading: '10. Safety Resources',
          body:
              'If you feel unsafe during a delivery or ride, you can:\n\n'
              '• Tap the emergency button in the active delivery or ride screen to call emergency services.\n'
              '• Contact 7Dash support at support@7dash.app.\n'
              '• End the order or ride safely and leave the situation.\n\n'
              'Your personal safety always takes priority over completing a trip.',
        ),
      ],
    );
  }
}
