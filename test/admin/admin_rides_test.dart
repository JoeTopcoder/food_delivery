// Admin rides screen uses private Supabase providers that cannot be overridden
// externally. These tests verify structural rendering only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/modules/rides/screens/admin/admin_rides_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminRidesScreen (structural)', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminRidesScreen()));
      await tester.pump();
      expect(find.byType(Scaffold), findsAny);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminRidesScreen()));
      await tester.pump();
      expect(find.byType(AppBar), findsAny);
    });

    testWidgets('shows TabBar for rides sections', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminRidesScreen()));
      await tester.pump();
      expect(find.byType(TabBar), findsAny);
    });

    testWidgets('settles into loading or error state without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminRidesScreen()));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      // Screen must still be in the tree
      expect(find.byType(Scaffold), findsAny);
    });
  });
}
