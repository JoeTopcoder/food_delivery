import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_users_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminUsersScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pump();
      expect(find.byType(AdminUsersScreen), findsOneWidget);
    });

    testWidgets('shows search field', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pump();
      expect(find.byType(TextField), findsAtLeast(1));
    });

    testWidgets('shows users after data loads', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Alice Smith'), findsAny);
      expect(find.text('Bob Jones'), findsAny);
    });

    testWidgets('shows role filter chips', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pump();
      // Role filter chips: All, Customer, Driver, Restaurant, Admin
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              const ['All', 'Customer', 'Driver', 'Restaurant', 'Admin']
                  .contains(w.data),
        ),
        findsAny,
      );
    });

    testWidgets('shows inactive badge for banned users', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pumpAndSettle();
      // Bob Jones is isActive: false — expect a "Banned" or similar badge
      expect(find.textContaining('Banned'), findsAny);
    });

    testWidgets('tapping a user opens detail sheet', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice Smith').first);
      await tester.pumpAndSettle();
      // Bottom sheet should appear
      expect(find.byType(BottomSheet), findsAny);
    });

    testWidgets('pull-to-refresh works without error', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminUsersScreen()));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, 300),
      );
      await tester.pump();
      expect(find.byType(AdminUsersScreen), findsOneWidget);
    });
  });
}
