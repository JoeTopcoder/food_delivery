import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../models/menu_model.dart';
import '../../../models/restaurant_model.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerRestaurantPage extends ConsumerStatefulWidget {
  final Restaurant restaurant;
  final VoidCallback onBack;

  const WebCustomerRestaurantPage({
    super.key,
    required this.restaurant,
    required this.onBack,
  });

  @override
  ConsumerState<WebCustomerRestaurantPage> createState() => _WebCustomerRestaurantPageState();
}

class _WebCustomerRestaurantPageState extends ConsumerState<WebCustomerRestaurantPage> {
  String _selectedCategory = '';

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(restaurantMenuProvider(widget.restaurant.id));
    final r = widget.restaurant;

    return Column(
      children: [
        // Hero header
        _RestaurantHero(restaurant: r, onBack: widget.onBack),

        // Body
        Expanded(
          child: menuAsync.when(
            loading: () => const AppLoadingIndicator(),
            error: (e, _) => AppErrorState(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(restaurantMenuProvider(r.id)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.restaurant_menu_rounded, size: 64, color: Color(0xFFE2E8F0)),
                    SizedBox(height: 12),
                    Text('No menu items yet', style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8))),
                  ]),
                );
              }

              // Group by category
              final categories = items.map((i) => i.category).toSet().toList()..sort();
              if (_selectedCategory.isEmpty) {
                _selectedCategory = categories.first;
              }

              final filtered = items.where((i) => i.category == _selectedCategory).toList();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category sidebar
                  _CategorySidebar(
                    categories: categories,
                    selected: _selectedCategory,
                    onSelect: (c) => setState(() => _selectedCategory = c),
                  ),
                  // Menu items grid
                  Expanded(
                    child: _MenuGrid(items: filtered, restaurant: r),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────

class _RestaurantHero extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onBack;
  const _RestaurantHero({required this.restaurant, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3ED),
        image: r.imageUrl != null
            ? DecorationImage(image: NetworkImage(r.imageUrl!), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken))
            : null,
      ),
      child: Stack(children: [
        // Back button
        Positioned(
          top: 16, left: 16,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              onTap: onBack,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back_rounded, size: 20, color: Color(0xFF1E293B)),
              ),
            ),
          ),
        ),
        // Info overlay
        Positioned(
          left: 24, right: 24, bottom: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Logo
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
                  image: r.imageUrl != null
                      ? DecorationImage(image: NetworkImage(r.imageUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: r.imageUrl == null
                    ? const Icon(Icons.storefront_rounded, size: 36, color: Color(0xFFFF6B35))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (r.cuisineType != null) ...[
                        Text(r.cuisineType!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const Text('  •  ', style: TextStyle(color: Colors.white54)),
                      ],
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 3),
                      Text(r.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Text('  •  ', style: TextStyle(color: Colors.white54)),
                      const Icon(Icons.access_time_rounded, size: 13, color: Colors.white70),
                      const SizedBox(width: 3),
                      Text('${r.estimatedDeliveryTime ?? 30} min', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const Text('  •  ', style: TextStyle(color: Colors.white54)),
                      Text('${AppConstants.currencySymbol}${r.deliveryFee?.toStringAsFixed(2) ?? "0.00"} delivery', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: r.isOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.isOpen ? 'Open Now' : 'Closed', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Category sidebar ──────────────────────────────────────────────────────────

class _CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  const _CategorySidebar({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = cat == selected;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF6B35).withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isSelected ? Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)) : null,
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? const Color(0xFFFF6B35) : const Color(0xFF64748B),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Menu grid ─────────────────────────────────────────────────────────────────

class _MenuGrid extends ConsumerWidget {
  final List<MenuItem> items;
  final Restaurant restaurant;
  const _MenuGrid({required this.items, required this.restaurant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _MenuItemCard(item: items[i]),
    );
  }
}

// ── Menu item card ─────────────────────────────────────────────────────────────

class _MenuItemCard extends ConsumerStatefulWidget {
  final MenuItem item;
  const _MenuItemCard({required this.item});

  @override
  ConsumerState<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<_MenuItemCard> {
  bool _hover = false;
  int _qty = 0;

  void _increment() {
    ref.read(cartProvider.notifier).addItem(widget.item);
    setState(() => _qty++);
  }

  void _decrement() {
    if (_qty <= 0) return;
    final newQty = _qty - 1;
    if (newQty == 0) {
      ref.read(cartProvider.notifier).removeItem(widget.item.id);
    } else {
      ref.read(cartProvider.notifier).updateQuantity(widget.item.id, newQty);
    }
    setState(() => _qty = newQty);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync with actual cart state
    final cart = ref.read(cartProvider);
    final existing = cart.where((c) => c.menuItem.id == widget.item.id);
    _qty = existing.isEmpty ? 0 : existing.first.quantity;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDiscount = (item.discount ?? 0) > 0;
    final unavailable = !item.isAvailable || !item.inStock;

    return MouseRegion(
      cursor: unavailable ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: _hover ? 0.1 : 0.04),
            blurRadius: _hover ? 16 : 6,
            offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: Stack(children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3ED),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                    image: item.imageUrl != null
                        ? DecorationImage(image: NetworkImage(item.imageUrl!), fit: BoxFit.cover,
                            colorFilter: unavailable ? const ColorFilter.mode(Colors.white54, BlendMode.lighten) : null)
                        : null,
                  ),
                  child: item.imageUrl == null
                      ? Center(child: Icon(Icons.fastfood_rounded, size: 36, color: unavailable ? const Color(0xFFCBD5E1) : const Color(0xFFFF6B35)))
                      : null,
                ),
                if (unavailable)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      ),
                      child: const Center(child: Text('Unavailable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                    ),
                  ),
                if (hasDiscount)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
                      child: Text('${item.discount!.toInt()}% OFF', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),

            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: unavailable ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (item.description != null) ...[
                        const SizedBox(height: 2),
                        Text(item.description!, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                          if (hasDiscount)
                            Text('${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), decoration: TextDecoration.lineThrough)),
                        ]),
                        if (!unavailable) _QtyControl(qty: _qty, onIncrement: _increment, onDecrement: _decrement),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Qty control ───────────────────────────────────────────────────────────────

class _QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  const _QtyControl({required this.qty, required this.onIncrement, required this.onDecrement});

  @override
  Widget build(BuildContext context) {
    if (qty == 0) {
      return GestureDetector(
        onTap: onIncrement,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('Add', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _CircleBtn(icon: Icons.remove_rounded, onTap: onDecrement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$qty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFF6B35))),
        ),
        _CircleBtn(icon: Icons.add_rounded, onTap: onIncrement),
      ]),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(color: Color(0xFFFF6B35), shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}
