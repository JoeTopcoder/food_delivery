import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/models/weather_model.dart';

/// A realistic normalized payload as returned by the get-weather Edge Function.
Map<String, dynamic> _fixture({bool stale = false}) => {
  'location': {
    'name': 'Kingston',
    'region': 'Kingston',
    'country': 'Jamaica',
    'tz_id': 'America/Jamaica',
    'localtime': '2026-10-07 09:15',
  },
  'current': {
    'temp_c': 27.0,
    'feelslike_c': 30.2,
    'condition_text': 'Light rain',
    'condition_code': 1183,
    'is_day': 1,
    'humidity': 78,
    'wind_kph': 12.6,
    'precip_mm': 1.2,
  },
  'hourly': [
    {
      'time': '2026-10-07 08:00',
      'temp_c': 26.0,
      'condition_code': 1003,
      'condition_text': 'Partly cloudy',
      'chance_of_rain': 20,
      'is_day': 1,
    },
    {
      'time': '2026-10-07 10:00',
      'temp_c': 28.0,
      'condition_code': 1183,
      'condition_text': 'Light rain',
      'chance_of_rain': 65,
      'is_day': 1,
    },
    {
      'time': '2026-10-07 23:00',
      'temp_c': 24.0,
      'condition_code': 1000,
      'condition_text': 'Clear',
      'chance_of_rain': 0,
      'is_day': 0,
    },
  ],
  'provider_observed_at': '2026-10-07T14:00:00.000Z',
  'retrieved_at': '2026-10-07T14:02:00.000Z',
  'stale': stale,
  'cell': {'lat': 17.98, 'lon': -76.80},
};

void main() {
  group('Weather.fromJson', () {
    test('parses current weather and hourly forecast', () {
      final w = Weather.fromJson(_fixture());
      expect(w.location.name, 'Kingston');
      expect(w.location.tzId, 'America/Jamaica');
      expect(w.current.tempC, 27.0);
      expect(w.current.feelsLikeC, 30.2);
      expect(w.current.conditionCode, 1183);
      expect(w.current.humidity, 78);
      expect(w.current.windKph, 12.6);
      expect(w.current.precipMm, 1.2);
      expect(w.current.isDay, isTrue);
      expect(w.hourly.length, 3);
      expect(w.hourly[1].chanceOfRain, 65);
      expect(w.hourly[1].tempC, 28.0);
      expect(w.cellLat, 17.98);
      expect(w.cellLon, -76.80);
      expect(w.stale, isFalse);
    });

    test('rain condition code is detected as currently raining', () {
      final w = Weather.fromJson(_fixture());
      expect(w.current.isCurrentlyRaining, isTrue); // 1183 = light rain
    });

    test('clear/sunny code is not treated as raining', () {
      final f = _fixture();
      (f['current'] as Map)['condition_code'] = 1000;
      final w = Weather.fromJson(f);
      expect(w.current.isCurrentlyRaining, isFalse);
    });

    test('survives completely missing fields', () {
      final w = Weather.fromJson({});
      expect(w.location.name, isNull);
      expect(w.current.tempC, isNull);
      expect(w.current.isCurrentlyRaining, isFalse);
      expect(w.hourly, isEmpty);
      expect(w.stale, isFalse);
      expect(w.providerObservedAt, isNull);
    });

    test('tolerates unknown/garbage types without throwing', () {
      final w = Weather.fromJson({
        'location': 'nonsense',
        'current': {
          'temp_c': 'not-a-number',
          'humidity': '80',
          'condition_code': '1063',
          'is_day': 'yes',
        },
        'hourly': 'nope',
        'cell': 42,
      });
      expect(w.current.tempC, isNull); // unparseable -> null
      expect(w.current.humidity, 80); // numeric string coerced
      expect(w.current.conditionCode, 1063); // numeric string coerced
      expect(w.hourly, isEmpty);
      expect(w.cellLat, isNull);
    });

    test('stale flag is carried through', () {
      final w = Weather.fromJson(_fixture(stale: true));
      expect(w.stale, isTrue);
    });
  });

  group('Weather.upcomingHours', () {
    test('returns entries strictly after the reference time', () {
      final w = Weather.fromJson(_fixture());
      final from = DateTime.parse('2026-10-07T09:00:00');
      final next = w.upcomingHours(6, from: from);
      // 10:00 and 23:00 are after 09:00; 08:00 is not.
      expect(next.length, 2);
      expect(next.first.tempC, 28.0);
    });

    test('caps to requested count', () {
      final w = Weather.fromJson(_fixture());
      final from = DateTime.parse('2026-10-07T00:00:00');
      expect(w.upcomingHours(2, from: from).length, 2);
    });

    test('degrades gracefully at end of day (falls back to available)', () {
      final w = Weather.fromJson(_fixture());
      final from = DateTime.parse('2026-10-08T00:00:00'); // nothing after
      final next = w.upcomingHours(6, from: from);
      expect(next, isNotEmpty); // falls back rather than returning empty
    });
  });

  group('WeatherCodes.iconFor', () {
    test('maps known codes', () {
      expect(WeatherCodes.iconFor(1000, isDay: true), Icons.wb_sunny_rounded);
      expect(WeatherCodes.iconFor(1000, isDay: false), Icons.nightlight_round);
      expect(WeatherCodes.iconFor(1183), Icons.water_drop_rounded);
      expect(WeatherCodes.iconFor(1006), Icons.cloud_rounded);
    });

    test('falls back for null and unknown codes', () {
      expect(WeatherCodes.iconFor(null), Icons.cloud_outlined);
      expect(WeatherCodes.iconFor(999999), Icons.cloud_outlined);
    });
  });
}
