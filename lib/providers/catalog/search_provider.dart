import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/food/search_service.dart';
import '../../utils/menu_filter.dart';
import '../auth_user/auth_provider.dart';
import '../platform/feature_providers.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(Supabase.instance.client);
});

final searchCuisineProvider = StateProvider.autoDispose<String?>((ref) => null);
final searchMaxPriceProvider = StateProvider.autoDispose<double?>((ref) => null);
final searchMinRatingProvider = StateProvider.autoDispose<double?>((ref) => null);

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
    StateNotifierProvider.autoDispose<DebouncedSearchNotifier, String>(
      (ref) => DebouncedSearchNotifier(),
    );

/// Convenience method — call this to update the search query with debounce.
/// Usage: ref.read(searchQueryProvider.notifier).update(value)
extension SearchQueryExt on DebouncedSearchNotifier {
  void setQuery(String v) => update(v);
}

/// Menu item search results (reactive to query/filters)
final menuSearchResultsProvider = FutureProvider.autoDispose<List<MenuSearchResult>>((
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

  final results = await service.searchMenuItems(
    query: query.isNotEmpty ? query : null,
    cuisine: cuisine,
    maxPrice: maxPrice,
    minRating: minRating,
  );
  // Hide admin-filtered (e.g. alcohol) items from customer search.
  final words = await ref.watch(menuFilterWordsProvider.future);
  if (words.isEmpty) return results;
  return results
      .where((r) => !isTextFiltered(
          '${r.itemName} ${r.itemCategory ?? ''} ${r.itemDescription ?? ''}',
          words))
      .toList();
});

/// Personalized recommendations
final recommendationsProvider = FutureProvider.autoDispose<List<RecommendationResult>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final service = ref.watch(searchServiceProvider);
  return service.getRecommendations(userId);
});
