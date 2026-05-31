import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/premium_providers.dart';
import '../../models/restaurant_model.dart';
import 'restaurant_detail_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/context_extensions.dart';
import '../../core/utils/responsive.dart';
import '../../modules/car_services/models/car_service_provider.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.favorites),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant_rounded, size: 18), text: 'Restaurants'),
            Tab(icon: Icon(Icons.local_laundry_service_rounded, size: 18), text: 'Laundry'),
            Tab(icon: Icon(Icons.car_repair, size: 18), text: 'Car Services'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _RestaurantFavourites(userId: user.id),
          _LaundryFavourites(userId: user.id),
          _CarServiceFavourites(userId: user.id),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Restaurants tab
// ─────────────────────────────────────────────────────────────────────────────

class _RestaurantFavourites extends ConsumerWidget {
  final String userId;
  const _RestaurantFavourites({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteRestaurantsProvider(userId));
    return favoritesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (favorites) {
        if (favorites.isEmpty) {
          return _EmptyState(
            icon: Icons.restaurant_rounded,
            message: 'No favourite restaurants yet',
            hint: 'Tap ❤️ on a restaurant to save it here',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.all(Responsive.cardPadding(context)),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final restaurantData = favorites[index]['restaurants'] as Map<String, dynamic>?;
            if (restaurantData == null) return const SizedBox.shrink();
            final restaurant = Restaurant.fromJson(restaurantData);
            return _FavCard(
              imageUrl: restaurant.imageUrl,
              title: restaurant.name,
              subtitle: restaurant.cuisineType,
              rating: restaurant.rating,
              trailing: '${restaurant.estimatedDeliveryTime ?? 30} min',
              trailingIcon: Icons.access_time,
              placeholderIcon: Icons.restaurant,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => RestaurantDetailScreen(restaurant: restaurant),
              )),
              onUnfavourite: () async {
                await ref.read(favoritesServiceProvider).toggleFavorite(userId, restaurant.id);
                ref.invalidate(favoriteRestaurantsProvider(userId));
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Laundry tab
// ─────────────────────────────────────────────────────────────────────────────

class _LaundryFavourites extends ConsumerWidget {
  final String userId;
  const _LaundryFavourites({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoriteLaundryProvidersProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (rows) {
        if (rows.isEmpty) {
          return _EmptyState(
            icon: Icons.local_laundry_service_rounded,
            message: 'No favourite laundry providers yet',
            hint: 'Tap ❤️ on a laundry provider to save it here',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.all(Responsive.cardPadding(context)),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final p = rows[index]['laundry_providers'] as Map<String, dynamic>?;
            if (p == null) return const SizedBox.shrink();
            return _FavCard(
              imageUrl: p['logo_url'] as String?,
              title: p['business_name'] as String? ?? 'Laundry Provider',
              subtitle: p['address'] as String?,
              rating: (p['rating'] as num?)?.toDouble(),
              placeholderIcon: Icons.local_laundry_service_rounded,
              onTap: () => Navigator.pushNamed(context, '/laundry'),
              onUnfavourite: () async {
                await Supabase.instance.client
                    .from('user_favorite_laundry_providers')
                    .delete()
                    .eq('user_id', userId)
                    .eq('provider_id', p['id'] as String);
                ref.invalidate(favoriteLaundryProvidersProvider(userId));
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Car Services tab
// ─────────────────────────────────────────────────────────────────────────────

class _CarServiceFavourites extends ConsumerWidget {
  final String userId;
  const _CarServiceFavourites({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoriteCarProvidersProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (rows) {
        if (rows.isEmpty) {
          return _EmptyState(
            icon: Icons.car_repair,
            message: 'No favourite car service providers yet',
            hint: 'Tap ❤️ on a car service provider to save it here',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.all(Responsive.cardPadding(context)),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final p = rows[index]['car_service_providers'] as Map<String, dynamic>?;
            if (p == null) return const SizedBox.shrink();
            return _FavCard(
              imageUrl: p['profile_image_url'] as String?,
              title: p['business_name'] as String? ?? 'Car Service Provider',
              subtitle: p['base_location_address'] as String?,
              rating: (p['rating'] as num?)?.toDouble(),
              placeholderIcon: Icons.car_repair,
              onTap: () {
                final provider = CarServiceProvider.fromMap(p);
                Navigator.pushNamed(
                  context,
                  '/car-services/provider-detail',
                  arguments: provider,
                );
              },
              onUnfavourite: () async {
                await Supabase.instance.client
                    .from('user_favorite_car_providers')
                    .delete()
                    .eq('user_id', userId)
                    .eq('provider_id', p['id'] as String);
                ref.invalidate(favoriteCarProvidersProvider(userId));
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card widget
// ─────────────────────────────────────────────────────────────────────────────

class _FavCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final double? rating;
  final String? trailing;
  final IconData? trailingIcon;
  final IconData placeholderIcon;
  final VoidCallback onTap;
  final VoidCallback onUnfavourite;

  const _FavCard({
    required this.title,
    required this.placeholderIcon,
    required this.onTap,
    required this.onUnfavourite,
    this.imageUrl,
    this.subtitle,
    this.rating,
    this.trailing,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl!,
                        width: 72, height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(placeholderIcon),
                      )
                    : _placeholder(placeholderIcon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (rating != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 15),
                          const SizedBox(width: 3),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          if (trailing != null && trailingIcon != null) ...[
                            const SizedBox(width: 10),
                            Icon(trailingIcon, color: Colors.grey.shade500, size: 13),
                            const SizedBox(width: 3),
                            Text(trailing!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Unfavourite button
              IconButton(
                icon: const Icon(Icons.favorite_rounded, color: Colors.red, size: 22),
                onPressed: onUnfavourite,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(IconData icon) => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.grey.shade400, size: 30),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;
  const _EmptyState({required this.icon, required this.message, required this.hint});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(message,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(hint,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
