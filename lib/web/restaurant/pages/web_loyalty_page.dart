import 'package:flutter/material.dart';
import '../../../screens/restaurant/restaurant_loyalty_screen.dart';

/// Wraps the existing loyalty screen inside the web layout.
class WebLoyaltyPage extends StatelessWidget {
  const WebLoyaltyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const RestaurantLoyaltyScreen();
  }
}
