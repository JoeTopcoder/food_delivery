import 'package:flutter/material.dart';
import '../../../screens/restaurant/grocery_management_screen.dart';

/// Wraps the existing grocery management screen inside the web layout.
class WebGroceryPage extends StatelessWidget {
  const WebGroceryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroceryManagementScreen();
  }
}
