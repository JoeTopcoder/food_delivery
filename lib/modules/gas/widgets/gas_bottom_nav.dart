import 'package:flutter/material.dart';
import '../../../screens/customer/grocery/grocery_screen.dart';
import '../screens/customer/gas_landing_screen.dart';
import '../screens/customer/gas_orders_screen.dart';
import 'gas_ui.dart';

/// Bottom navigation shared by the gas customer pages (Home/Food/Groceries/Gas/Orders).
/// [current] is the active index: 3 = Gas, 4 = Orders.
class GasBottomNav extends StatelessWidget {
  const GasBottomNav({super.key, required this.current});
  final int current;

  void _go(BuildContext context, int i) {
    if (i == current) return;
    switch (i) {
      case 0: // Home
        Navigator.popUntil(context, (r) => r.isFirst);
        break;
      case 1: // Food
        Navigator.popUntil(context, (r) => r.isFirst);
        Navigator.pushNamed(context, '/all-restaurants');
        break;
      case 2: // Groceries
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GroceryScreen()));
        break;
      case 3: // Gas
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GasLandingScreen()));
        break;
      case 4: // Orders (gas orders)
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GasOrdersScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: current,
      onTap: (i) => _go(context, i),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: GasBrand.orange,
      unselectedItemColor: Theme.of(context).hintColor,
      showUnselectedLabels: true,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.restaurant_rounded), label: 'Food'),
        BottomNavigationBarItem(icon: Icon(Icons.local_grocery_store_rounded), label: 'Groceries'),
        BottomNavigationBarItem(icon: Icon(Icons.propane_tank_rounded), label: 'Gas'),
        BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: 'Orders'),
      ],
    );
  }
}
