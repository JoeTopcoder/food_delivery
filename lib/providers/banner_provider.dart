import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/banner_model.dart';

/// Active banners for the customer home screen (joined with restaurant name).
/// Only shows banners whose linked restaurant is verified.
final activeBannersProvider = FutureProvider<List<Banner>>((ref) async {
  final now = DateTime.now().toUtc();
  final data = await SupabaseConfig.client
      .from('banners')
      .select('*, restaurants(name, is_verified)')
      .eq('is_active', true)
      .order('sort_order', ascending: true);

  return (data as List).map((e) => Banner.fromJson(e)).where((b) {
    if (b.startsAt != null && b.startsAt!.isAfter(now)) return false;
    if (b.endsAt != null && b.endsAt!.isBefore(now)) return false;
    // Hide banners for unverified / revoked restaurants
    if (b.restaurantVerified != true) return false;
    return true;
  }).toList();
});

/// All banners for admin management (including inactive).
final allBannersProvider = FutureProvider<List<Banner>>((ref) async {
  final data = await SupabaseConfig.client
      .from('banners')
      .select('*, restaurants(name)')
      .order('sort_order', ascending: true);

  return (data as List).map((e) => Banner.fromJson(e)).toList();
});
