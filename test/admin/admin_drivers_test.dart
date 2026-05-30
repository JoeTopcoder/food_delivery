import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_drivers_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminDriversScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDriversScreen()));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows tab bar', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDriversScreen()));
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('shows driver content after data loads', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDriversScreen()));
      await tester.pumpAndSettle();
      // Should show at least one widget from the loaded data
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ListTile ||
              w is Card ||
              (w is Text && (w.data?.contains('Jane') == true || w.data?.contains('4.8') == true)),
        ),
        findsAny,
      );
    });

    testWidgets('shows rating for approved drivers', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDriversScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('4.8'), findsAny);
    });

    testWidgets('switching tabs does not crash', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDriversScreen()));
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
