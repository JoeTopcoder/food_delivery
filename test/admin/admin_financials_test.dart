import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_financials_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminFinancialsScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminFinancialsScreen()));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminFinancialsScreen()));
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows financial data after loading', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminFinancialsScreen()));
      await tester.pumpAndSettle();
      // Some financial number should be on screen
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('\$') == true ||
                  w.data?.contains('85') == true ||
                  w.data?.contains('12') == true),
        ),
        findsAny,
      );
    });

    testWidgets('pull-to-refresh works without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminFinancialsScreen()));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, 300),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
