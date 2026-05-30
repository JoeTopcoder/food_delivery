import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/screens/admin/admin_earnings_screen.dart';
import 'package:food_driver/providers/earning_provider.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  List<Override> earningsOverrides() => [
    allEarningAccountsProvider.overrideWith(
      (ref) async => mockEarningAccounts(),
    ),
  ];

  group('AdminEarningsScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminEarningsScreen(),
          extraOverrides: earningsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminEarningsScreen(),
          extraOverrides: earningsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows earning accounts after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminEarningsScreen(),
          extraOverrides: earningsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Alice Smith'), findsAny);
    });

    testWidgets('shows total earned amount', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminEarningsScreen(),
          extraOverrides: earningsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('120'), findsAny);
    });

    testWidgets('shows tier information', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminEarningsScreen(),
          extraOverrides: earningsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.toLowerCase().contains('builder') == true ||
                  w.data?.toLowerCase().contains('tier') == true ||
                  w.data?.toLowerCase().contains('leader') == true),
        ),
        findsAny,
      );
    });
  });
}
