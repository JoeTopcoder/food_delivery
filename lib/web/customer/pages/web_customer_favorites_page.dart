import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../models/restaurant_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/premium_providers.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerFavoritesPage extends ConsumerWidget {
  final void Function(Restaurant) onRestaurantTapped;
  const WebCustomerFavoritesPage({super.key, required this.onRestaurantTapped});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const AppLoadingIndicator();

    final favsAsync = ref.watch(favoriteRestaurantsProvider(userId));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Favorites', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Your saved restaurants', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(favoriteRestaurantsProvider(userId))),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: favsAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(favoriteRestaurantsProvider(userId))),
              data: (favs) {
                if (favs.isEmpty) {
                  return const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite_border_rounded, size: 64, color: Color(0xFFE2E8F0)),
                      SizedBox(height: 12),
                      Text('No favorites yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      SizedBox(height: 4),
                      Text('Save restaurants you love from the Home tab', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                    ]),
                  );
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: favs.length,
                  itemBuilder: (_, i) => _FavCard(data: favs[i], onTap: onRestaurantTapped),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FavCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(Restaurant) onTap;
  const _FavCard({required this.data, required this.onTap});

  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.data;
    final restaurant = r['restaurants'] as Map<String, dynamic>? ?? r;
    final name = restaurant['name'] as String? ?? 'Restaurant';
    final cuisine = restaurant['cuisine_type'] as String? ?? '';
    final rating = (restaurant['rating'] as num?)?.toDouble();
    final imageUrl = restaurant['image_url'] as String?;
    final deliveryFee = (restaurant['delivery_fee'] as num?)?.toDouble() ?? 0;
    final deliveryTime = restaurant['estimated_delivery_time'] as int? ?? 30;
    final isOpen = restaurant['is_open'] as bool? ?? false;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          try {
            widget.onTap(Restaurant.fromJson(restaurant));
          } catch (_) {}
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hover ? 0.1 : 0.05), blurRadius: _hover ? 14 : 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Banner
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover) : null,
            ),
            child: imageUrl == null ? const Center(child: Icon(Icons.storefront_rounded, size: 40, color: Color(0xFFFF6B35))) : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFEF4444)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Text(cuisine, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                const Spacer(),
                const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                const SizedBox(width: 2),
                Text(rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 3),
                Text('$deliveryTime min', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                const SizedBox(width: 10),
                const Icon(Icons.delivery_dining_rounded, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 3),
                Text('${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(isOpen ? 'Open' : 'Closed', style: TextStyle(fontSize: 10, color: isOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
      ),
    );
  }
}
