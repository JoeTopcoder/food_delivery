import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class CuisineService {
  final SupabaseClient _client;
  CuisineService(this._client);

  // Get all cuisine categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await _client
          .from('cuisine_categories')
          .select()
          .eq('is_active', true)
          .order('display_order');
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('Error fetching cuisine categories: $e');
      return [];
    }
  }
}
