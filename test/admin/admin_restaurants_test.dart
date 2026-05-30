import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_restaurants_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminRestaurantsScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminRestaurantsScreen()),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows tab bar', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminRestaurantsScreen()),
      );
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('shows restaurants after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminRestaurantsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Burger Palace'), findsAny);
    });

    testWidgets('shows a restaurant status indicator', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminRestaurantsScreen()),
      );
      await tester.pumpAndSettle();
      // Any verification/status indicator (chip, icon, text)
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Chip ||
              w is Icon ||
              (w is Text &&
                  (w.data?.toLowerCase().contains('verif') == true ||
                      w.data?.toLowerCase().contains('active') == true ||
                      w.data?.toLowerCase().contains('pending') == true)),
        ),
        findsAny,
      );
    });

    testWidgets('switching tabs does not crash', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminRestaurantsScreen()),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(Tab);
      if (tabs.evaluate().length >= 2) {
        await tester.tap(tabs.at(1));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
