import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class RestaurantReviewsScreen extends ConsumerWidget {
  final String restaurantId;
  final String restaurantName;
  final bool isOwner;

  const RestaurantReviewsScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.isOwner = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('$restaurantName Reviews'), elevation: 0),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: ref
            .read(restaurantServiceProvider)
            .getRestaurantReviews(restaurantId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator(message: 'Loading reviews...');
          }
          if (snapshot.hasError) {
            return AppErrorState(message: friendlyError(snapshot.error));
          }
          final reviews = snapshot.data ?? [];
          if (reviews.isEmpty) {
            return const AppEmptyState(
              icon: Icons.rate_review_outlined,
              title: 'No reviews yet',
              subtitle: 'Be the first to leave a review!',
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              final hasResponse = review['response_text'] != null;
              return _ReviewCard(
                review: review,
                hasResponse: hasResponse,
                isOwner: isOwner,
                currentUserId: currentUserId,
                onRespond: isOwner && !hasResponse
                    ? () => _showRespondDialog(context, ref, review)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  void _showRespondDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> review,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Respond to Review'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Write your response...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final currentUserId = ref.read(currentUserIdProvider);
                await ref
                    .read(restaurantServiceProvider)
                    .respondToReview(
                      reviewId: review['id'],
                      responseText: text,
                      responderId: currentUserId!,
                    );
                if (context.mounted) {
                  AppSnackbar.success(context, 'Response submitted');
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    // dispose controller when dialog closes
    controller.addListener(() {});
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final bool hasResponse;
  final bool isOwner;
  final String? currentUserId;
  final VoidCallback? onRespond;

  const _ReviewCard({
    required this.review,
    required this.hasResponse,
    required this.isOwner,
    this.currentUserId,
    this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final reviewText = review['review'] as String?;
    final userName = review['users']?['name'] ?? 'Customer';
    final createdAt = review['created_at'] as String?;
    final responseText = review['response_text'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  (userName as String).isNotEmpty
                      ? userName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: i < rating.round() ? Colors.amber : Colors.grey[300],
                  );
                }),
              ),
            ],
          ),
          if (reviewText != null && reviewText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              reviewText,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
          // Owner response
          if (hasResponse && responseText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.store_rounded,
                        size: 14,
                        color: Color(0xFF0284C7),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Restaurant Response',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    responseText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Respond button for owner
          if (onRespond != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRespond,
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: const Text('Respond', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
