import 'package:flutter/material.dart';

/// Normalized weather data returned by the `get-weather` Edge Function.
///
/// Hand-written (no json_serializable / .g.dart) so regenerating shared models
/// never touches this file. All fields are nullable-tolerant: the parser must
/// survive missing or unknown provider fields without throwing.
class Weather {
  final WeatherLocation location;
  final WeatherCurrent current;
  final List<WeatherHour> hourly;

  /// Provider's observation time (`current.last_updated`), may be null.
  final DateTime? providerObservedAt;

  /// When the backend retrieved/cached this data.
  final DateTime? retrievedAt;

  /// True when served from cache because the provider was unavailable.
  /// Such data must be visibly labelled and never shown as "current".
  final bool stale;

  /// The rounded representative cell coordinate ("near" the request point).
  final double? cellLat;
  final double? cellLon;

  const Weather({
    required this.location,
    required this.current,
    required this.hourly,
    this.providerObservedAt,
    this.retrievedAt,
    this.stale = false,
    this.cellLat,
    this.cellLon,
  });

  factory Weather.fromJson(Map<String, dynamic> json) {
    final loc = json['location'];
    final cur = json['current'];
    final hours = json['hourly'];

    return Weather(
      location: WeatherLocation.fromJson(
        loc is Map ? Map<String, dynamic>.from(loc) : const {},
      ),
      current: WeatherCurrent.fromJson(
        cur is Map ? Map<String, dynamic>.from(cur) : const {},
      ),
      hourly: hours is List
          ? hours
                .whereType<Map>()
                .map((h) => WeatherHour.fromJson(Map<String, dynamic>.from(h)))
                .toList()
          : const [],
      providerObservedAt: _parseDate(json['provider_observed_at']),
      retrievedAt: _parseDate(json['retrieved_at']),
      stale: json['stale'] == true,
      cellLat: _toDouble((json['cell'] is Map ? json['cell']['lat'] : null)),
      cellLon: _toDouble((json['cell'] is Map ? json['cell']['lon'] : null)),
    );
  }

  /// The next [count] hourly entries strictly after [from] (defaults to now),
  /// so the end of the day degrades gracefully when fewer remain.
  List<WeatherHour> upcomingHours(int count, {DateTime? from}) {
    final ref = from ?? DateTime.now();
    final future = hourly.where((h) {
      final t = h.time;
      return t != null && t.isAfter(ref);
    }).toList();
    final source = future.isNotEmpty ? future : hourly;
    return source.take(count).toList();
  }
}

class WeatherLocation {
  final String? name;
  final String? region;
  final String? country;
  final String? tzId;
  final String? localtime;

  const WeatherLocation({
    this.name,
    this.region,
    this.country,
    this.tzId,
    this.localtime,
  });

  factory WeatherLocation.fromJson(Map<String, dynamic> json) =>
      WeatherLocation(
        name: json['name'] as String?,
        region: json['region'] as String?,
        country: json['country'] as String?,
        tzId: json['tz_id'] as String?,
        localtime: json['localtime'] as String?,
      );
}

class WeatherCurrent {
  final double? tempC;
  final double? feelsLikeC;
  final String? conditionText;
  final int? conditionCode;
  final bool isDay;
  final int? humidity;
  final double? windKph;
  final double? precipMm;

  const WeatherCurrent({
    this.tempC,
    this.feelsLikeC,
    this.conditionText,
    this.conditionCode,
    this.isDay = true,
    this.humidity,
    this.windKph,
    this.precipMm,
  });

  factory WeatherCurrent.fromJson(Map<String, dynamic> json) => WeatherCurrent(
    tempC: _toDouble(json['temp_c']),
    feelsLikeC: _toDouble(json['feelslike_c']),
    conditionText: json['condition_text'] as String?,
    conditionCode: _toInt(json['condition_code']),
    isDay: json['is_day'] == true || json['is_day'] == 1,
    humidity: _toInt(json['humidity']),
    windKph: _toDouble(json['wind_kph']),
    precipMm: _toDouble(json['precip_mm']),
  );

  /// Whether conditions indicate it is *currently* raining (from the condition
  /// code), as opposed to a forecast probability. Used for delivery messaging.
  bool get isCurrentlyRaining =>
      conditionCode != null &&
      WeatherCodes.rainCodes.contains(conditionCode);
}

class WeatherHour {
  final DateTime? time;
  final double? tempC;
  final int? conditionCode;
  final String? conditionText;
  final int chanceOfRain;
  final bool isDay;

  const WeatherHour({
    this.time,
    this.tempC,
    this.conditionCode,
    this.conditionText,
    this.chanceOfRain = 0,
    this.isDay = true,
  });

  factory WeatherHour.fromJson(Map<String, dynamic> json) => WeatherHour(
    // Provider format: "yyyy-MM-dd HH:mm" (local to the forecast location).
    time: _parseHourTime(json['time']),
    tempC: _toDouble(json['temp_c']),
    conditionCode: _toInt(json['condition_code']),
    conditionText: json['condition_text'] as String?,
    chanceOfRain: _toInt(json['chance_of_rain']) ?? 0,
    isDay: json['is_day'] == true || json['is_day'] == 1,
  );
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

DateTime? _parseDate(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  try {
    return DateTime.parse(v);
  } catch (_) {
    return null;
  }
}

DateTime? _parseHourTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  // "yyyy-MM-dd HH:mm" -> ISO-ish
  try {
    return DateTime.parse(v.replaceFirst(' ', 'T'));
  } catch (_) {
    return null;
  }
}

/// Maps WeatherAPI.com condition codes to Material icons with a safe fallback
/// for unknown codes. Day/night aware for the clear/sunny case.
class WeatherCodes {
  // Codes that mean rain/drizzle/thunder is actually happening now.
  static const Set<int> rainCodes = {
    1063, 1150, 1153, 1168, 1171, 1180, 1183, 1186, 1189, 1192, 1195,
    1240, 1243, 1246, 1273, 1276, 1087, 1072,
  };

  static const Set<int> _snow = {
    1066, 1114, 1117, 1210, 1213, 1216, 1219, 1222, 1225, 1255, 1258,
    1237, 1261, 1264, 1279, 1282,
  };
  static const Set<int> _sleet = {1069, 1198, 1201, 1204, 1207, 1249, 1252};
  static const Set<int> _fog = {1030, 1135, 1147};
  static const Set<int> _cloudy = {1006, 1009};
  static const Set<int> _partlyCloudy = {1003};
  static const int _clear = 1000;

  static IconData iconFor(int? code, {bool isDay = true}) {
    if (code == null) return Icons.cloud_outlined; // fallback for unknown
    if (code == _clear) {
      return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    }
    if (_partlyCloudy.contains(code)) {
      return isDay ? Icons.wb_cloudy_outlined : Icons.cloud_queue_rounded;
    }
    if (_cloudy.contains(code)) return Icons.cloud_rounded;
    if (_fog.contains(code)) return Icons.foggy;
    if (rainCodes.contains(code)) return Icons.water_drop_rounded;
    if (_sleet.contains(code)) return Icons.grain_rounded;
    if (_snow.contains(code)) return Icons.ac_unit_rounded;
    if (code == 1087 || code == 1273 || code == 1276) {
      return Icons.thunderstorm_rounded;
    }
    return Icons.cloud_outlined; // fallback for any unmapped code
  }

  /// A short emoji for the compact card label (documented mapping + fallback).
  static String emojiFor(int? code, {bool isDay = true}) {
    if (code == null) return '🌡️';
    if (code == _clear) return isDay ? '☀️' : '🌙';
    if (_partlyCloudy.contains(code)) return isDay ? '⛅' : '☁️';
    if (_cloudy.contains(code)) return '☁️';
    if (_fog.contains(code)) return '🌫️';
    if (code == 1273 || code == 1276 || code == 1087) return '⛈️';
    if (rainCodes.contains(code)) return '🌧️';
    if (_sleet.contains(code)) return '🌨️';
    if (_snow.contains(code)) return '❄️';
    return '🌡️';
  }
}
