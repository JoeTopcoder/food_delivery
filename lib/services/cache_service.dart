import 'package:hive_flutter/hive_flutter.dart';
import '../utils/app_logger.dart';

/// Offline cache backed by Hive. Stores JSON-serialisable data
/// with optional TTL (time-to-live) expiry.
class CacheService {
  static const _metaBoxName = 'cache_meta';

  /// Initialise Hive (call once in main()).
  static Future<void> init() async {
    await Hive.initFlutter();
  }

  /// Open (or reuse) a named box.
  static Future<Box> _box(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  /// Store a value with optional TTL in seconds.
  static Future<void> put(
    String boxName,
    String key,
    dynamic value, {
    int? ttlSeconds,
  }) async {
    try {
      final box = await _box(boxName);
      await box.put(key, value);
      if (ttlSeconds != null) {
        final meta = await _box(_metaBoxName);
        await meta.put(
          '${boxName}_${key}_expiry',
          DateTime.now().add(Duration(seconds: ttlSeconds)).toIso8601String(),
        );
      }
    } catch (e) {
      AppLogger.error('CacheService.put error: $e');
    }
  }

  /// Retrieve a value (returns null if expired or missing).
  static Future<dynamic> get(String boxName, String key) async {
    try {
      // Check TTL
      final meta = await _box(_metaBoxName);
      final expiryStr = meta.get('${boxName}_${key}_expiry') as String?;
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && DateTime.now().isAfter(expiry)) {
          // Expired – remove
          final box = await _box(boxName);
          await box.delete(key);
          await meta.delete('${boxName}_${key}_expiry');
          return null;
        }
      }
      final box = await _box(boxName);
      return box.get(key);
    } catch (e) {
      AppLogger.error('CacheService.get error: $e');
      return null;
    }
  }

  /// Cache a list of JSON maps.
  static Future<void> putList(
    String boxName,
    String key,
    List<Map<String, dynamic>> items, {
    int? ttlSeconds,
  }) async {
    await put(boxName, key, items, ttlSeconds: ttlSeconds);
  }

  /// Retrieve a cached JSON list.
  static Future<List<Map<String, dynamic>>?> getList(
    String boxName,
    String key,
  ) async {
    final raw = await get(boxName, key);
    if (raw == null) return null;
    try {
      return (raw as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Clear a specific box.
  static Future<void> clearBox(String boxName) async {
    try {
      final box = await _box(boxName);
      await box.clear();
    } catch (e) {
      AppLogger.error('CacheService.clearBox error: $e');
    }
  }

  /// Clear all caches.
  static Future<void> clearAll() async {
    try {
      await Hive.deleteFromDisk();
      await init();
    } catch (e) {
      AppLogger.error('CacheService.clearAll error: $e');
    }
  }
}

/// Standard box names used throughout the app.
class CacheBoxes {
  static const restaurants = 'restaurants';
  static const menuItems = 'menu_items';
  static const orders = 'orders';
  static const userProfile = 'user_profile';
}
