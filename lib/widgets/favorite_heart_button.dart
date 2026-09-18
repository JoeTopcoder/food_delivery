import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/premium_providers.dart';
import '../utils/app_feedback_widgets.dart';

/// Circular heart button overlaid on a restaurant card image. Tapping toggles
/// the restaurant in the customer's favourites with an optimistic update.
/// Shared across the standard [RestaurantCard] and the smart/personalised cards.
class FavoriteHeartButton extends ConsumerStatefulWidget {
  final String restaurantId;
  final double size;

  const FavoriteHeartButton({
    super.key,
    required this.restaurantId,
    this.size = 34,
  });

  @override
  ConsumerState<FavoriteHeartButton> createState() =>
      _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends ConsumerState<FavoriteHeartButton> {
  bool? _override;
  bool _busy = false;

  Future<void> _toggle() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || _busy) return;
    final isFavNow = _override ??
        (ref
                .read(isFavoriteProvider((userId, widget.restaurantId)))
                .valueOrNull ??
            false);
    setState(() {
      _override = !isFavNow;
      _busy = true;
    });
    try {
      await ref
          .read(favoritesServiceProvider)
          .toggleFavorite(userId, widget.restaurantId);
      ref.invalidate(isFavoriteProvider((userId, widget.restaurantId)));
      ref.invalidate(favoriteRestaurantsProvider(userId));
    } catch (_) {
      if (mounted) setState(() => _override = isFavNow);
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not update favourite. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final isFav = _override ??
        (userId == null
            ? false
            : ref
                    .watch(isFavoriteProvider((userId, widget.restaurantId)))
                    .valueOrNull ??
                false);
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: widget.size,
        height: widget.size,
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
          size: widget.size * 0.56,
          color: isFav ? AppTheme.accentColor : Colors.grey[700],
        ),
      ),
    );
  }
}
