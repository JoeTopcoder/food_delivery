import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feature_providers.dart';
import '../core/utils/responsive.dart';
import '../screens/customer/grocery_screen.dart';
import '../screens/customer/restaurants_by_category_screen.dart';

/// "What are you ordering today?" — the unified HotBite service launcher.
///
/// A native HotBite entry point that ties Food, Groceries, Drinks & Snacks and
/// the remaining services into one ecosystem. Every tile is gated by the
/// existing admin-controlled [serviceEnabledProvider] (backed by `app_config`),
/// so a service the admin turns off simply isn't shown — no app update needed.
/// Each tile opens the EXISTING experience; nothing here duplicates food or
/// grocery functionality.
class ServiceLauncherGrid extends ConsumerWidget {
  const ServiceLauncherGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(configVersionProvider); // rebuild when admin flips a service

    final foodOn = ref.watch(serviceEnabledProvider('food'));
    final groceryOn = ref.watch(serviceEnabledProvider('grocery'));
    final ridesOn = ref.watch(serviceEnabledProvider('rides'));
    final laundryOn = ref.watch(serviceEnabledProvider('laundry'));
    final carOn = ref.watch(serviceEnabledProvider('car_service'));

    // The "More" hub only appears when there's at least one extra service
    // behind it.
    final hasMore = ridesOn || laundryOn || carOn;

    final tiles = <Widget>[
      if (foodOn)
        _ServiceTile(
          icon: Icons.restaurant_rounded,
          emoji: '🍔',
          label: 'Food',
          color: const Color(0xFFFF5A1F),
          onTap: () => Navigator.pushNamed(context, '/all-restaurants'),
        ),
      if (groceryOn)
        _ServiceTile(
          icon: Icons.local_grocery_store_rounded,
          emoji: '🛒',
          label: 'Groceries',
          color: const Color(0xFF059669),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GroceryScreen()),
          ),
        ),
      // Drinks & Snacks browses the existing "Drinks" food category — it reuses
      // the category browse screen, it does not create a new catalogue.
      if (foodOn)
        _ServiceTile(
          icon: Icons.local_cafe_rounded,
          emoji: '🥤',
          label: 'Drinks & Snacks',
          color: const Color(0xFF7C3AED),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RestaurantsByCategoryScreen(
                categoryName: 'Drinks',
                categoryEmoji: '🥤',
              ),
            ),
          ),
        ),
      if (hasMore)
        _ServiceTile(
          icon: Icons.grid_view_rounded,
          emoji: '🏪',
          label: 'More',
          color: const Color(0xFF2563EB),
          onTap: () => _showMoreSheet(
            context,
            ridesOn: ridesOn,
            laundryOn: laundryOn,
            carOn: carOn,
          ),
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();

    final hPad = Responsive.horizontalPadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 10),
          child: Text(
            'What are you ordering today?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                SizedBox(width: 158, child: tiles[i]),
          ),
        ),
      ],
    );
  }

  void _showMoreSheet(
    BuildContext context, {
    required bool ridesOn,
    required bool laundryOn,
    required bool carOn,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 4),
                child: Text('More HotBite services',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (ridesOn)
                _MoreRow(
                  icon: Icons.directions_car_rounded,
                  label: 'Book a Ride',
                  color: const Color(0xFF1E40AF),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/ride-home');
                  },
                ),
              if (carOn)
                _MoreRow(
                  icon: Icons.local_car_wash_rounded,
                  label: 'Car Services',
                  color: const Color(0xFF0E9384),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/car-services');
                  },
                ),
              if (laundryOn)
                _MoreRow(
                  icon: Icons.local_laundry_service_rounded,
                  label: 'Laundry',
                  color: const Color(0xFF0F4C81),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/laundry');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
