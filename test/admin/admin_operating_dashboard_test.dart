import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/models/admin_metrics_model.dart';
import 'package:food_driver/providers/admin_metrics_provider.dart';
import 'package:food_driver/screens/admin/admin_operating_dashboard_screen.dart';

import '../helpers/admin_test_helpers.dart';

/// Renders the operating dashboard with fixture data.
///
/// The point of these is layout, not logic: the maths is all in Postgres and
/// is covered by supabase/tests/. What a widget test can catch that SQL cannot
/// is a RenderFlex overflow — and the two new sections are exactly the shape
/// that overflows, a five-cell bucket strip and a leaderboard row with a long
/// partner name next to a money column. An overflow fails these tests rather
/// than showing up as a yellow-and-black stripe on someone's phone.
void main() {
  final liveOps = [
    LiveOpsRow(
      status: 'preparing',
      ordersCount: 9,
      bucketLabels: const ['0-30', '30-35', '35-40', '40-45', '45+'],
      bucketCounts: const [4, 2, 1, 1, 1],
      breachCount: 1,
      oldestMinutes: 51.4,
    ),
    LiveOpsRow(
      status: 'on_the_way',
      ordersCount: 3,
      bucketLabels: const ['0-30', '30-35', '35-40', '40-45', '45+'],
      bucketCounts: const [3, 0, 0, 0, 0],
      breachCount: 0,
      oldestMinutes: 12.0,
    ),
  ];

  final sla = [
    const SlaAttributionRow(
      actorType: 'store',
      avgMinutes: 22.4,
      medianMinutes: 19,
      p90Minutes: 41,
      maxMinutes: 63,
      sampleSize: 8,
      shareOfTimePct: 54.2,
    ),
    const SlaAttributionRow(
      actorType: 'rider',
      avgMinutes: 14.1,
      medianMinutes: 13,
      p90Minutes: 25,
      maxMinutes: 31,
      sampleSize: 8,
      shareOfTimePct: 45.8,
    ),
  ];

  final partners = [
    const PartnerRow(
      partnerId: 'a',
      // Deliberately long: partner names are user data and the tile must
      // ellipsize rather than push the money column off the screen.
      partnerName: 'Ackee & Saltfish Kitchen — Half Way Tree Road Branch',
      ordersCount: 128,
      gmv: 4820000,
      contribution: 960000,
      deliveredCount: 120,
      onTimePct: 91.7,
    ),
    const PartnerRow(
      partnerId: 'b',
      partnerName: 'Sushi World',
      ordersCount: 1,
      gmv: 2795,
      contribution: -1500, // negative contribution must render, and in red
      deliveredCount: 0,
      onTimePct: null, // nothing delivered yet: must not render as 0%
    ),
  ];

  List<Override> overrides({
    List<LiveOpsRow>? ops,
    List<SlaAttributionRow>? attribution,
    List<PartnerRow>? board,
  }) => [
    adminLiveOpsProvider.overrideWith((ref) async => ops ?? liveOps),
    adminSlaAttributionProvider.overrideWith((ref) async => attribution ?? sla),
    adminTopPartnersProvider.overrideWith((ref) async => board ?? partners),
  ];

  Future<void> pumpDashboard(WidgetTester tester, List<Override> o) async {
    // A phone-width surface, because that is where a horizontal overflow
    // actually happens.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildAdminTestApp(
        const AdminOperatingDashboardScreen(),
        extraOverrides: o,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('AdminOperatingDashboardScreen', () {
    testWidgets('renders with data and no layout overflow', (tester) async {
      await pumpDashboard(tester, overrides());

      expect(find.byType(Scaffold), findsOneWidget);
      // Scroll the whole page so every section is laid out, not just the
      // ones above the fold.
      final list = find.byType(ListView);
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty results render an empty state, not a crash', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        overrides(ops: const [], attribution: const [], board: const []),
      );

      final list = find.byType(ListView);
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Nothing in flight'), findsOneWidget);
    });

    testWidgets('a failing RPC shows an error, never a zero', (tester) async {
      // A financial dashboard that renders a failure as 0 is worse than one
      // that renders nothing: a real zero and a broken query look identical.
      await pumpDashboard(tester, [
        adminLiveOpsProvider.overrideWith(
          (ref) async => throw Exception('boom'),
        ),
        adminSlaAttributionProvider.overrideWith((ref) async => sla),
        adminTopPartnersProvider.overrideWith((ref) async => partners),
      ]);

      final list = find.byType(ListView);
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }
      expect(find.byIcon(Icons.error_outline), findsAtLeastNWidgets(1));
    });
  });

  group('LiveOpsRow', () {
    test('titles a snake_case status without inventing one', () {
      // 'on_the_way' is the real status in this database. There is no
      // 'out_for_delivery' — a dead branch elsewhere in the codebase assumes
      // there is, and this label must not repeat that mistake.
      const row = LiveOpsRow(
        status: 'on_the_way',
        ordersCount: 1,
        bucketLabels: [],
        bucketCounts: [],
        breachCount: 0,
        oldestMinutes: 0,
      );
      expect(row.label, 'On The Way');
    });
  });

  group('PartnerRow', () {
    test('distinguishes no deliveries from nothing delivered on time', () {
      final none = PartnerRow.fromJson(const {
        'partner_id': 'a',
        'partner_name': 'X',
        'orders_count': 3,
        'gmv': 100,
        'contribution': 10,
        'delivered_count': 0,
        'on_time_pct': null,
      });
      final zero = PartnerRow.fromJson(const {
        'partner_id': 'b',
        'partner_name': 'Y',
        'orders_count': 3,
        'gmv': 100,
        'contribution': 10,
        'delivered_count': 3,
        'on_time_pct': 0,
      });
      expect(none.onTimePct, isNull);
      expect(zero.onTimePct, 0);
    });
  });

  group('formatMinor', () {
    test('renders minor units without float drift', () {
      expect(formatMinor(4820000, r'$'), r'$48,200.00');
      expect(formatMinor(-1500, r'$'), r'-$15.00');
      expect(formatMinor(0, r'$'), r'$0.00');
      expect(formatMinor(1, r'$'), r'$0.01');
    });
  });
}
