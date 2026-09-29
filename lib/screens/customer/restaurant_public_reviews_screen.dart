import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/app_cached_image.dart';
import '../../utils/rating_format.dart';
import '../../utils/friendly_error.dart';

/// Customer-facing reviews page: a compact header with the restaurant's info
/// and rating, then the list of customer reviews. Opened from the Reviews
/// button on the restaurant detail page. (Distinct from the owner-facing
/// RestaurantReviewsScreen, which supports responding to reviews.)
class RestaurantPublicReviewsScreen extends ConsumerWidget {
  final Restaurant restaurant;
  const RestaurantPublicReviewsScreen({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final reviewsAsync = ref.watch(restaurantReviewsProvider(restaurant.id));
    final rating = restaurant.rating;
    final count = restaurant.reviewCount ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(restaurantReviewsProvider(restaurant.id)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: restaurant.imageUrl != null &&
                              restaurant.imageUrl!.isNotEmpty
                          ? AppCachedImage(
                              url: restaurant.imageUrl,
                              width: 60,
                              height: 60,
                              decodeWidth: 120,
                            )
                          : Container(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.restaurant_rounded,
                                  color: scheme.onSurfaceVariant),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        if (restaurant.cuisineType != null)
                          Text(
                            restaurant.cuisineType!,
                            style: TextStyle(
                                fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    formatRating(rating),
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StarRow(rating: rating ?? 0, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        rating != null
                            ? '${rating.toStringAsFixed(1)} out of 5'
                                '${count > 0 ? '  ($count Ratings)' : ''}'
                            : 'No ratings yet',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            reviewsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(friendlyError(e))),
              ),
              data: (reviews) {
                if (reviews.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No reviews yet. Be the first to review!',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    ...reviews.map((r) => _ReviewCard(review: r)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i;
        return Icon(
          half
              ? Icons.star_half_rounded
              : (filled ? Icons.star_rounded : Icons.star_outline_rounded),
          size: size,
          color: const Color(0xFFF59E0B),
        );
      }),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (review['reviewer_name'] ?? 'Customer').toString();
    final text = (review['review_text'] ?? '').toString().trim();
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final createdRaw = review['created_at']?.toString();
    final created = createdRaw != null ? DateTime.tryParse(createdRaw) : null;
    final dateStr = created != null
        ? '${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}'
        : '';
    final response = (review['response_text'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.person_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StarRow(rating: rating, size: 15),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 13.5, height: 1.3)),
          ],
          if (response.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Response from the restaurant',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary)),
                  const SizedBox(height: 3),
                  Text(response, style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
