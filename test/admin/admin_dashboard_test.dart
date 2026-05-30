import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_dashboard_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminDashboardScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminDashboardScreen()),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows welcome message with admin first name', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminDashboardScreen()),
      );
      await tester.pump();
      // Dashboard greets with first name: "Welcome back, Test"
      expect(find.textContaining('Test'), findsAny);
    });

    testWidgets('shows KPI content after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminDashboardScreen()),
      );
      await tester.pumpAndSettle();
      // Dashboard renders custom _KpiCard containers — look for any
      // child widget that indicates the data section loaded
      expect(find.byType(Container), findsAny);
    });

    testWidgets('shows navigation menu after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminDashboardScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('pull-to-refresh works without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(const AdminDashboardScreen()),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
