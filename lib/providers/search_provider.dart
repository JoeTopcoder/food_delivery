import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/search_service.dart';
import 'auth_provider.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(Supabase.instance.client);
});

/// Search query state
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchCuisineProvider = StateProvider<String?>((ref) => null);
final searchMaxPriceProvider = StateProvider<double?>((ref) => null);
final searchMinRatingProvider = StateProvider<double?>((ref) => null);

/// Menu item search results (reactive to query/filters)
final menuSearchResultsProvider = FutureProvider<List<MenuSearchResult>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  final cuisine = ref.watch(searchCuisineProvider);
  final maxPrice = ref.watch(searchMaxPriceProvider);
  final minRating = ref.watch(searchMinRatingProvider);
  final service = ref.watch(searchServiceProvider);

  if (query.isEmpty &&
      cuisine == null &&
      maxPrice == null &&
      (minRating == null || minRating == 0)) {
    return [];
  }

  return service.searchMenuItems(
    query: query.isNotEmpty ? query : null,
    cuisine: cuisine,
    maxPrice: maxPrice,
    minRating: minRating,
  );
});

/// Personalized recommendations
final recommendationsProvider = FutureProvider<List<RecommendationResult>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final service = ref.watch(searchServiceProvider);
  return service.getRecommendations(userId);
});
