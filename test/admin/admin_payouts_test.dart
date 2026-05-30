import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/screens/admin/admin_payouts_screen.dart';
import 'package:food_driver/providers/payout_provider.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  List<Override> payoutsOverrides() => [
    allPayoutsProvider.overrideWith((ref) async => mockPayouts()),
  ];

  group('AdminPayoutsScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPayoutsScreen(),
          extraOverrides: payoutsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(AdminPayoutsScreen), findsOneWidget);
    });

    testWidgets('shows tab bar with status filters', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPayoutsScreen(),
          extraOverrides: payoutsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('shows payout rows after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPayoutsScreen(),
          extraOverrides: payoutsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      // mock payout has amount 200.0
      expect(find.textContaining('200'), findsAny);
    });

    testWidgets('shows bank name in payout card', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPayoutsScreen(),
          extraOverrides: payoutsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('FirstCaribbean'), findsAny);
    });

    testWidgets('switching tabs does not crash', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPayoutsScreen(),
          extraOverrides: payoutsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(Tab);
      if (tabs.evaluate().length >= 2) {
        await tester.tap(tabs.at(1));
        await tester.pumpAndSettle();
      }
      expect(find.byType(AdminPayoutsScreen), findsOneWidget);
    });
  });
}
