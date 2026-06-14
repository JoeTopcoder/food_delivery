import 'package:flutter/material.dart';
import '../../../screens/restaurant/restaurant_settings_screen.dart';

/// Wraps the existing mobile settings screen inside the web layout.
/// The mobile screen already handles all settings logic — no duplication needed.
class WebSettingsPage extends StatelessWidget {
  const WebSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const RestaurantSettingsScreen();
  }
}
