import 'package:flutter/material.dart';
import 'available_orders_screen.dart';
import 'active_deliveries_screen.dart';
import '../../widgets/ai_fab.dart';
import '../../widgets/sos_button.dart';

/// Driver Orders hub: "Get Orders" (available to accept) and "Active Orders"
/// (in progress). Only the SELECTED screen is mounted — mounting both full
/// CustomScrollView screens at once (as a TabBarView does) nests two viewports
/// and crashes the offstage one's map/sliver layout.
class DriverOrdersScreen extends StatefulWidget {
  /// 0 = Get Orders, 1 = Active Orders.
  final int initialTab;
  const DriverOrdersScreen({super.key, this.initialTab = 0});

  @override
  State<DriverOrdersScreen> createState() => _DriverOrdersScreenState();
}

class _DriverOrdersScreenState extends State<DriverOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tc.addListener(() {
      if (mounted) setState(() {}); // swap the mounted screen on tab change
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        bottom: TabBar(
          controller: _tc,
          indicatorColor: const Color(0xFF6C63FF),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF8A90A6),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'Get Orders'),
            Tab(text: 'Active Orders'),
          ],
        ),
      ),
      // Only the active screen is built, so there is never a second offstage
      // scroll viewport to break layout/paint.
      body: _tc.index == 0
          ? const AvailableOrdersScreen(embedded: true)
          : const ActiveDeliveriesScreen(embedded: true),
    );
  }
}
