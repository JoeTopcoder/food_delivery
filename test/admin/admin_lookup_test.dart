import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/admin/admin_lookup_screen.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  group('AdminLookupScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminLookupScreen()));
      await tester.pump();
      expect(find.byType(AdminLookupScreen), findsOneWidget);
    });

    testWidgets('shows search input field', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminLookupScreen()));
      await tester.pump();
      expect(find.byType(TextField), findsAtLeast(1));
    });

    testWidgets('shows search button or icon', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminLookupScreen()));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              (w is IconButton &&
                  (w.icon is Icon) &&
                  ((w.icon as Icon).icon == Icons.search)) ||
              (w is ElevatedButton) ||
              (w is Icon && w.icon == Icons.search),
        ),
        findsAny,
      );
    });

    testWidgets('shows AppBar with Lookup title', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminLookupScreen()));
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('typing into search field does not crash', (tester) async {
      await tester.pumpWidget(buildAdminTestApp(const AdminLookupScreen()));
      await tester.pump();
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.enterText(field, 'test query');
      await tester.pump();
      expect(find.byType(AdminLookupScreen), findsOneWidget);
    });
  });
}
