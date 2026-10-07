import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:food_driver/models/weather_model.dart';
import 'package:food_driver/providers/weather_provider.dart';
import 'package:food_driver/services/weather_service.dart';
import 'package:food_driver/utils/est_datetime.dart';
import 'package:food_driver/widgets/weather_card.dart';

Weather _sample({bool stale = false}) => Weather.fromJson({
  'location': {'name': 'Kingston', 'tz_id': 'America/Jamaica'},
  'current': {
    'temp_c': 27.0,
    'feelslike_c': 30.0,
    'condition_text': 'Light rain',
    'condition_code': 1183,
    'is_day': 1,
    'humidity': 78,
    'wind_kph': 12.0,
    'precip_mm': 1.2,
  },
  'hourly': const [],
  'provider_observed_at':
      DateTime.now().toUtc().toIso8601String(),
  'retrieved_at': DateTime.now().toUtc().toIso8601String(),
  'stale': stale,
  'cell': {'lat': 17.98, 'lon': -76.80},
});

WeatherQuery _query() => WeatherQuery(
  lat: 17.9771,
  lon: -76.7936,
  source: WeatherSource.deliveryAddress,
  label: 'Home',
);

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(
    home: Scaffold(body: CustomScrollViewOrColumn()),
  ),
);

/// WeatherCard is normally a sliver child but renders fine in a Column for test.
class CustomScrollViewOrColumn extends StatelessWidget {
  const CustomScrollViewOrColumn({super.key});
  @override
  Widget build(BuildContext context) =>
      const SingleChildScrollView(child: Column(children: [WeatherCard()]));
}

void main() {
  group('WeatherQuery', () {
    test('rounds coordinates to 2dp and is value-equal within a cell', () {
      final a = WeatherQuery(
        lat: 17.9760,
        lon: -76.7940,
        source: WeatherSource.deliveryAddress,
        label: 'Home',
      );
      final b = WeatherQuery(
        lat: 17.9795, // same 2dp cell (17.98, -76.79) -> equal
        lon: -76.7936,
        source: WeatherSource.deliveryAddress,
        label: 'Work', // label does not affect identity
      );
      expect(a.lat, 17.98);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different cells are not equal (prevents stale cross-use)', () {
      final a = WeatherQuery(
        lat: 18.00,
        lon: -76.80,
        source: WeatherSource.deliveryAddress,
      );
      final b = WeatherQuery(
        lat: 18.42,
        lon: -77.12,
        source: WeatherSource.deliveryAddress,
      );
      expect(a == b, isFalse);
    });

    test('same coords but different source are distinct', () {
      final a = WeatherQuery(
        lat: 18.0,
        lon: -76.8,
        source: WeatherSource.deliveryAddress,
      );
      final b = WeatherQuery(
        lat: 18.0,
        lon: -76.8,
        source: WeatherSource.currentLocation,
      );
      expect(a == b, isFalse);
    });
  });

  group('WeatherCard states', () {
    // Settle the async budget load + weatherProvider future, then dispose the
    // card (cancels its 1s accrual ticker so no timer is pending at test end).
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(); // budget load (SharedPreferences)
      await tester.pump(const Duration(milliseconds: 50)); // weatherProvider
    }

    Future<void> teardownCard(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('hidden entirely when there is no address', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_host([
        effectiveWeatherQueryProvider.overrideWithValue(null),
      ]));
      await settle(tester);
      expect(find.byType(WeatherCard), findsOneWidget); // widget present...
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing); // ...but renders nothing
      expect(find.textContaining('°C'), findsNothing);
      await teardownCard(tester);
    });

    testWidgets('loaded state shows condition and temperature',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final q = _query();
      await tester.pumpWidget(_host([
        effectiveWeatherQueryProvider.overrideWithValue(q),
        weatherProvider.overrideWith((ref, arg) async => _sample()),
      ]));
      await settle(tester);
      expect(find.textContaining('Light rain'), findsOneWidget);
      expect(find.text('27°C'), findsOneWidget);
      await teardownCard(tester);
    });

    testWidgets('stale weather shows the last-known label', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final q = _query();
      await tester.pumpWidget(_host([
        effectiveWeatherQueryProvider.overrideWithValue(q),
        weatherProvider.overrideWith((ref, arg) async => _sample(stale: true)),
      ]));
      await settle(tester);
      expect(find.textContaining('Last known'), findsOneWidget);
      await teardownCard(tester);
    });

    testWidgets('error state offers retry', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final q = _query();
      await tester.pumpWidget(_host([
        effectiveWeatherQueryProvider.overrideWithValue(q),
        weatherProvider.overrideWith(
          (ref, arg) async => throw WeatherException('weather_unreachable'),
        ),
      ]));
      await settle(tester);
      expect(find.text('Retry'), findsOneWidget);
      await teardownCard(tester);
    });

    testWidgets('hidden once the daily screen-time budget is spent',
        (tester) async {
      // Pre-seed today's Jamaica-day counter at the full 4-minute budget.
      final dayKey = DateTime.now().jmFormat('yyyy-MM-dd');
      SharedPreferences.setMockInitialValues({
        'weather_screen_secs_$dayKey': 4 * 60,
      });
      final q = _query();
      await tester.pumpWidget(_host([
        effectiveWeatherQueryProvider.overrideWithValue(q),
        weatherProvider.overrideWith((ref, arg) async => _sample()),
      ]));
      await settle(tester);
      // Budget exhausted -> nothing rendered even with a valid address + data.
      expect(find.textContaining('°C'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      await teardownCard(tester);
    });
  });
}
