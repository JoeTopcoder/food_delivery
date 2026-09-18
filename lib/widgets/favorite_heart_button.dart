import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/premium_providers.dart';
import '../utils/app_feedback_widgets.dart';

/// Circular heart button overlaid on a restaurant card image. Reads and writes
/// the single shared [favoriteRestaurantIdsProvider], so favouriting a
/// restaurant on any card, the detail screen, or the favourites list updates
/// the heart everywhere in the app at once.
class FavoriteHeartButton extends ConsumerWidget {
  final String restaurantId;
  final double size;

  const FavoriteHeartButton({
    super.key,
    required this.restaurantId,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    final isFav = ref
        .watch(favoriteRestaurantIdsProvider)
        .contains(restaurantId);

    return GestureDetector(
      onTap: () async {
        if (userId == null) return;
        try {
          await ref
              .read(favoriteRestaurantIdsProvider.notifier)
              .toggle(restaurantId);
        } catch (_) {
          if (context.mounted) {
            AppSnackbar.error(
              context,
              'Could not update favourite. Please try again.',
            );
          }
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: size * 0.56,
          color: isFav ? AppTheme.accentColor : Colors.grey[700],
        ),
      ),
    );
  }
}
