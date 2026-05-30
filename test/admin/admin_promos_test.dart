import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/screens/admin/admin_promos_screen.dart';
import 'package:food_driver/providers/promo_provider.dart';
import 'package:food_driver/services/promo_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../helpers/admin_test_helpers.dart';

void main() {
  // _PromoCard.build() calls ref.read(promoServiceProvider) synchronously,
  // which constructs PromoService(SupabaseConfig.client). A live Supabase
  // client is required for that constructor even in tests.
  setUpAll(setupTestSupabase);

  List<Override> promosOverrides() => [
    allPromosProvider.overrideWith((ref) async => mockPromos()),
    // Override promoServiceProvider so _PromoCard uses the already-initialized
    // client rather than SupabaseConfig.client (which re-checks initialization).
    promoServiceProvider.overrideWith(
      (ref) => PromoService(Supabase.instance.client),
    ),
  ];

  group('AdminPromosScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPromosScreen(),
          extraOverrides: promosOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPromosScreen(),
          extraOverrides: promosOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows promo code after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPromosScreen(),
          extraOverrides: promosOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('SAVE10'), findsAny);
    });

    testWidgets('shows discount value', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPromosScreen(),
          extraOverrides: promosOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('10'), findsAny);
    });

    testWidgets('has a create / add action', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminPromosScreen(),
          extraOverrides: promosOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is FloatingActionButton ||
              w is IconButton ||
              (w is Icon &&
                  (w.icon == Icons.add ||
                      w.icon == Icons.add_circle ||
                      w.icon == Icons.add_circle_outline)),
        ),
        findsAny,
      );
    });
  });
}
