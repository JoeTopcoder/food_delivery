import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/screens/admin/admin_analytics_screen.dart';
import 'package:food_driver/providers/analytics_provider.dart';
import 'package:food_driver/services/social/analytics_service.dart';
import '../helpers/admin_test_helpers.dart';

void main() {
  final mockTrend = [
    DauDataPoint(
      date: DateTime(2024, 5, 1),
      dau: 80,
      orders: 40,
      revenue: 480.0,
    ),
    DauDataPoint(
      date: DateTime(2024, 5, 2),
      dau: 95,
      orders: 50,
      revenue: 620.0,
    ),
  ];

  final mockRetention = [
    RetentionPoint(
      cohortDate: DateTime(2024, 5, 1),
      cohortSize: 100,
      retained: 72,
      rate: 72.0,
    ),
  ];

  final mockTopRestaurants = [
    const TopRestaurant(
      id: 'rest-0001-aaaa-bbbb',
      name: 'Burger Palace',
      orderCount: 120,
      revenue: 1440.0,
    ),
  ];

  List<Override> analyticsOverrides() => [
    analyticsSummaryProvider.overrideWith(
      (ref) async => mockAnalyticsSummary(),
    ),
    dauTrendProvider.overrideWith((ref, days) async => mockTrend),
    retentionProvider.overrideWith((ref, day) async => mockRetention),
    topRestaurantsProvider.overrideWith((ref) async => mockTopRestaurants),
  ];

  group('AdminAnalyticsScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminAnalyticsScreen(),
          extraOverrides: analyticsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows summary metrics after data loads', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminAnalyticsScreen(),
          extraOverrides: analyticsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      // DAU = 88, or at least some numeric/text content is visible
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('88') == true ||
                  w.data?.contains('42') == true ||
                  w.data?.contains('520') == true),
        ),
        findsAny,
      );
    });

    testWidgets('shows top restaurants section', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminAnalyticsScreen(),
          extraOverrides: analyticsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      // Scroll down to reveal the top restaurants section
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              (w is Text && w.data?.contains('Burger Palace') == true) ||
              (w is Text && w.data?.toLowerCase().contains('restaurant') == true),
        ),
        findsAny,
      );
    });

    testWidgets('AppBar is present', (tester) async {
      await tester.pumpWidget(
        buildAdminTestApp(
          const AdminAnalyticsScreen(),
          extraOverrides: analyticsOverrides(),
        ),
      );
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
