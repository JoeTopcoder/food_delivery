import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/search_service.dart';
import 'auth_provider.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(Supabase.instance.client);
});

final searchCuisineProvider = StateProvider<String?>((ref) => null);
final searchMaxPriceProvider = StateProvider<double?>((ref) => null);
final searchMinRatingProvider = StateProvider<double?>((ref) => null);

/// Debounced search query notifier — emits a new value only after 400 ms of
/// inactivity, preventing a DB call on every keystroke.
class DebouncedSearchNotifier extends StateNotifier<String> {
  Timer? _timer;

  DebouncedSearchNotifier() : super('');

  void update(String value) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () {
      state = value;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final searchQueryProvider =
    StateNotifierProvider<DebouncedSearchNotifier, String>(
      (ref) => DebouncedSearchNotifier(),
    );

/// Convenience method — call this to update the search query with debounce.
/// Usage: ref.read(searchQueryProvider.notifier).update(value)
extension SearchQueryExt on DebouncedSearchNotifier {
  void setQuery(String v) => update(v);
}

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
