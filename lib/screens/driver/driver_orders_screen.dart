import 'package:flutter/material.dart';
import 'available_orders_screen.dart';
import 'active_deliveries_screen.dart';
import '../../widgets/ai_fab.dart';
import '../../widgets/sos_button.dart';

/// Driver Orders hub: "Get Orders" (available to accept) and "Active Orders"
/// (in progress). After accepting an order the driver swipes to Active Orders.
class DriverOrdersScreen extends StatelessWidget {
  /// 0 = Get Orders, 1 = Active Orders.
  final int initialTab;
  const DriverOrdersScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1117),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Orders',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
          actions: const [
            AiAppBarAction(role: 'driver'),
            SosButton(),
            SizedBox(width: 4),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF6C63FF),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFF8A90A6),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: [
              Tab(text: 'Get Orders'),
              Tab(text: 'Active Orders'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            AvailableOrdersScreen(embedded: true),
            ActiveDeliveriesScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}
