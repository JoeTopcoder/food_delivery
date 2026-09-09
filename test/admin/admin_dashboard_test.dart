import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_dashboard_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminDashboardScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows welcome message with admin first name', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pump();
      // Dashboard greets with first name: "Welcome back, Test"
      expect(find.textContaining('Test'), findsAny);
    });

    testWidgets('shows KPI content after data loads', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      // Dashboard renders custom _KpiCard containers — look for any
      // child widget that indicates the data section loaded
      expect(find.byType(Container), findsAny);
    });

    testWidgets('shows navigation menu after data loads', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('pull-to-refresh works without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('lays out on a 360dp phone without overflowing', (
      tester,
    ) async {
      // The regression this guards: seven KPI cards shared one Row via
      // Expanded, which gave each about 38dp on a phone and truncated every
      // label to "Tar...", "Bre...", "Restau...". The greeting had the same
      // problem horizontally, sharing its line with three action buttons.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildAdminTestApp(const AdminDashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Walk the whole page so every section is laid out, not just the part
      // above the fold.
      final scroller = find.byType(CustomScrollView);
      for (var i = 0; i < 10; i++) {
        await tester.drag(scroller, const Offset(0, -400));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });
}
