import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/catalog/menu_model.dart';
import '../../../models/catalog/restaurant_model.dart';
import '../../../providers/auth_user/user_provider.dart';
import '../../../services/catalog/catalog_cache.dart';
import '../../../providers/rewards/premium_providers.dart';
import '../../../utils/friendly_error.dart';
import '../../../providers/auth_user/auth_provider.dart';
import '../../../providers/catalog/recommendation_provider.dart';
import '../../../providers/platform/feature_providers.dart';
import '../../../utils/app_theme.dart';
import '../../../widgets/menu/menu_item_card.dart';
import '../../../widgets/menu/menu_item_actions.dart';
import '../../../config/app_constants.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../ordering/group_order_detail_screen.dart';
import '../home/restaurant_public_reviews_screen.dart';

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;

  /// When coming from a group order, these link the cart back to the participant.
  final String? groupOrderId;
  final String? groupParticipantId;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurant,
    this.groupOrderId,
    this.groupParticipantId,
  });

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  late ScrollController _scrollController;
  bool _showAppBar = false;
  String? _selectedCategory;
  bool _startingGroupOrder = false;
  bool _savingToGroup = false;

  // Menu is rendered as one continuous, scrollable list of all categories. The
  // category chips jump to a section; as the customer scrolls, the chip of the
  // section currently at the top stays highlighted. These track that.
  final Map<String, GlobalKey> _categoryKeys = {};
  List<String> _orderedCategories = const [];
  final ScrollController _chipsController = ScrollController();
  bool _chipJumpInProgress = false;

  void _openReviews() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RestaurantPublicReviewsScreen(restaurant: widget.restaurant),
      ),
    );
  }

  Future<void> _openMenuSearch() async {
    final items =
        ref.read(restaurantMenuProvider(widget.restaurant.id)).valueOrNull ??
        const <MenuItem>[];
    if (items.isEmpty) {
      AppSnackbar.info(context, 'Menu is still loading — try again in a moment.');
      return;
    }
    final selected = await showSearch<MenuItem?>(
      context: context,
      delegate: _MenuSearchDelegate(
        restaurantName: widget.restaurant.displayBrand,
        items: items,
      ),
    );
    if (selected != null && mounted) {
      _showMenuItemDetail(context, selected);
    }
  }

  Future<void> _toggleFav() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      // Uses the same shared favourites store as every heart button, so the
      // detail screen and all cards stay in sync.
      await ref
          .read(favoriteRestaurantIdsProvider.notifier)
          .toggle(widget.restaurant.id);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not update favourite. Please try again.',
        );
      }
    }
  }

  Future<void> _saveToGroupOrder() async {
    final participantId = widget.groupParticipantId;
    final groupOrderId = widget.groupOrderId;
    if (participantId == null) return;
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      AppSnackbar.info(context, 'Add some items first!');
      return;
    }
    setState(() => _savingToGroup = true);
    try {
      final service = ref.read(groupOrderServiceProvider);

      // Fetch the current participant's existing items so we can MERGE,
      // not replace. This allows adding items across multiple trips.
      List<dynamic> existingItems = [];
      if (groupOrderId != null) {
        final groupOrder = await service.getGroupOrder(groupOrderId);
        final parts = groupOrder?.participants ?? [];
        final participant = parts.isNotEmpty
            ? parts.firstWhere(
                (p) => p.id == participantId,
                orElse: () => parts.first,
              )
            : null;
        existingItems = List<dynamic>.from(participant?.items ?? []);
      }

      // Merge: for each new cart item, check if an identical item (same
      // menu item id + same sides + same options) already exists — if so,
      // increment its quantity; otherwise append as new.
      final merged = List<Map<String, dynamic>>.from(
        existingItems.cast<Map<String, dynamic>>(),
      );
      for (final cartItem in cartItems) {
        final newJson = cartItem.toJson();
        final newId = (newJson['menuItem'] as Map)['id'] as String?;
        final newSides = (newJson['selectedSides'] as List)
            .map((s) => (s as Map)['id'] ?? (s)['name'])
            .toSet();
        final newOpts = (newJson['selectedOptions'] as Map).values
            .expand(
              (v) => (v as List).map((c) => (c as Map)['id'] ?? c['name']),
            )
            .toSet();

        int? matchIdx;
        for (int i = 0; i < merged.length; i++) {
          final e = merged[i];
          final eId = (e['menuItem'] as Map)['id'] as String?;
          if (eId != newId) continue;
          final eSides = (e['selectedSides'] as List? ?? [])
              .map((s) => (s as Map)['id'] ?? (s)['name'])
              .toSet();
          final eOpts = (e['selectedOptions'] as Map? ?? {}).values
              .expand(
                (v) => (v as List).map((c) => (c as Map)['id'] ?? c['name']),
              )
              .toSet();
          if (eSides.length == newSides.length &&
              eOpts.length == newOpts.length &&
              eSides.containsAll(newSides) &&
              eOpts.containsAll(newOpts)) {
            matchIdx = i;
            break;
          }
        }

        if (matchIdx != null) {
          final existing = Map<String, dynamic>.from(merged[matchIdx]);
          existing['quantity'] =
              ((existing['quantity'] as int? ?? 1) + cartItem.quantity);
          merged[matchIdx] = existing;
        } else {
          merged.add(newJson);
        }
      }

      final subtotal = merged.fold<double>(0.0, (sum, itemJson) {
        final json = itemJson;
        final qty = (json['quantity'] as int? ?? 1).toDouble();
        final price =
            ((json['menuItem'] as Map)['price'] as num?)?.toDouble() ?? 0.0;
        final sidesTotal = (json['selectedSides'] as List? ?? []).fold<double>(
          0.0,
          (s, side) => s + ((side as Map)['price'] as num? ?? 0).toDouble(),
        );
        final optsTotal = (json['selectedOptions'] as Map? ?? {}).values
            .fold<double>(
              0.0,
              (s, choices) =>
                  s +
                  (choices as List).fold<double>(
                    0.0,
                    (cs, c) =>
                        cs + ((c as Map)['price'] as num? ?? 0).toDouble(),
                  ),
            );
        return sum + (price + sidesTotal + optsTotal) * qty;
      });

      final ok = await service.updateParticipantItems(
        participantId: participantId,
        items: merged,
        subtotal: subtotal,
      );
      if (!mounted) return;
      if (ok) {
        final totalItems = merged.fold<int>(
          0,
          (sum, j) => sum + ((j as Map)['quantity'] as int? ?? 1),
        );
        AppSnackbar.success(
          context,
          'Saved! You now have $totalItems item${totalItems != 1 ? 's' : ''} in the group order.',
        );
        ref.read(cartProvider.notifier).clearCart();
        Navigator.pop(context);
      } else {
        AppSnackbar.error(context, 'Failed to save items. Try again.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingToGroup = false);
    }
  }

  Future<void> _startGroupOrder() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    setState(() => _startingGroupOrder = true);
    try {
      final service = ref.read(groupOrderServiceProvider);
      final cartItems = ref.read(cartProvider);

      final group = await service.createGroupOrder(
        hostUserId: userId,
        restaurantId: widget.restaurant.id,
        name: '${widget.restaurant.displayBrand} Group Order',
        deadlineMinutes: 60,
      );
      if (group == null) throw Exception('Failed to create group order');

      // If the host already had items in the cart, save them to their
      // participant record so they're included in the group order.
      if (cartItems.isNotEmpty) {
        // Re-fetch the group order to get the host participant row ID
        final freshGroup = await service.getGroupOrder(group.id);
        final hostParticipant = freshGroup?.participants
            .where((p) => p.userId == userId)
            .firstOrNull;
        if (hostParticipant != null) {
          final items = cartItems.map((c) => c.toJson()).toList();
          final subtotal = cartItems.fold(0.0, (sum, c) => sum + c.subtotal);
          await service.updateParticipantItems(
            participantId: hostParticipant.id,
            items: items,
            subtotal: subtotal,
          );
          // Clear cart — items are now stored in the group order
          ref.read(cartProvider.notifier).clearCart();
        }
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupOrderDetailScreen(groupOrderId: group.id),
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _startingGroupOrder = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // Track restaurant view for AI engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        ref
            .read(behaviorTrackingProvider)
            .trackRestaurantView(
              userId,
              widget.restaurant.id,
              cuisineType: widget.restaurant.cuisineType,
            );
        // Record for real-time session boost
        if (widget.restaurant.cuisineType != null) {
          ref
              .read(realtimeBoostProvider.notifier)
              .recordInteraction(widget.restaurant.cuisineType!);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _chipsController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.offset > 200;
    if (show != _showAppBar) setState(() => _showAppBar = show);
    if (!_chipJumpInProgress) _syncActiveCategoryToScroll();
  }

  /// Highlights the chip of the menu section currently at the top of the
  /// viewport as the customer scrolls the continuous menu list.
  void _syncActiveCategoryToScroll() {
    if (_orderedCategories.isEmpty) return;
    // Anchor just below the sticky app bar area.
    const anchor = 160.0;
    String? current;
    for (final cat in _orderedCategories) {
      final ctx = _categoryKeys[cat]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= anchor) {
        current = cat; // last section whose header has passed the anchor
      } else {
        break;
      }
    }
    current ??= _orderedCategories.first;
    if (current != _selectedCategory) {
      setState(() => _selectedCategory = current);
      _ensureChipVisible(current);
    }
  }

  /// Scrolls the menu list to a category's section (chip tap).
  Future<void> _jumpToCategory(String cat) async {
    setState(() => _selectedCategory = cat);
    _ensureChipVisible(cat);
    final ctx = _categoryKeys[cat]?.currentContext;
    if (ctx == null) return;
    _chipJumpInProgress = true;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.0, // bring the section header to the top
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    _chipJumpInProgress = false;
  }

  /// Keeps the active chip visible in the horizontal chip row.
  void _ensureChipVisible(String cat) {
    if (!_chipsController.hasClients) return;
    final i = _orderedCategories.indexOf(cat);
    if (i < 0) return;
    const chipApprox = 110.0; // average pill width + gap
    final target = (i * chipApprox - 60).clamp(
      0.0,
      _chipsController.position.maxScrollExtent,
    );
    _chipsController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final menuItemsAsync = ref.watch(
      restaurantMenuProvider(widget.restaurant.id),
    );
    final currentUserId = ref.watch(currentUserIdProvider);
    final isFav = currentUserId != null &&
        ref.watch(favoriteRestaurantIdsProvider).contains(widget.restaurant.id);

    return Scaffold(
      appBar: _showAppBar
          ? AppBar(
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.restaurant.displayBrand,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: _openMenuSearch,
                ),
                // Cart button (replaces the favourite button here) — always
                // visible, with a count badge when the cart has items.
                Consumer(
                  builder: (context, ref, _) {
                    final cartItems = ref.watch(cartProvider);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shopping_cart_outlined,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () =>
                              Navigator.pushNamed(context, '/cart'),
                        ),
                        if (cartItems.isNotEmpty)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '${cartItems.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () {
                    final id = widget.restaurant.id;
                    final name = widget.restaurant.displayBrand;
                    final cuisine =
                        widget.restaurant.cuisineType ?? 'great food';
                    final rating = widget.restaurant.rating != null
                        ? ' ⭐ ${widget.restaurant.rating}'
                        : '';
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            '🍽️ $name$rating\n'
                            '$cuisine • Order on HotBite\n\n'
                            'Use code NEWUSER for 30% off your first order!\n'
                            'https://hotbite.app/restaurant/$id',
                        subject: 'Check out $name on HotBite!',
                      ),
                    );
                  },
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant Hero Image
                Stack(
                  children: [
                    ClipRRect(
                      child:
                          widget.restaurant.imageUrl != null &&
                              widget.restaurant.imageUrl!.isNotEmpty
                          ? Image.network(
                              widget.restaurant.imageUrl!,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 260,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.primaryColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      AppTheme.primaryColor.withValues(
                                        alpha: 0.05,
                                      ),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.restaurant_rounded,
                                  size: 64,
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              height: 260,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppTheme.primaryColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    AppTheme.primaryColor.withValues(
                                      alpha: 0.05,
                                    ),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.restaurant_rounded,
                                size: 64,
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 40,
                      left: 16,
                      child: _showAppBar
                          ? const SizedBox.shrink()
                          : GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.arrow_back,
                                  size: 24,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final cartItems = ref.watch(cartProvider);
                        if (cartItems.isEmpty) return const SizedBox.shrink();
                        return Positioned(
                          top: 40,
                          right: 68,
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/cart'),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 24,
                                    color: Colors.black87,
                                  ),
                                ),
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentColor,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      '${cartItems.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Menu search — search this restaurant's menu from here.
                    Positioned(
                      top: 40,
                      right: 64,
                      child: GestureDetector(
                        onTap: _openMenuSearch,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.search_rounded,
                            size: 24,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      right: 16,
                      child: GestureDetector(
                        onTap: _toggleFav,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_outline,
                            size: 24,
                            color: isFav ? Colors.red : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Restaurant Info
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.restaurant.displayBrand,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Hide the specific branch address for multi-location
                      // chains — the customer orders from the brand, not a named
                      // location; the order routes to the nearest branch behind
                      // the scenes (resolve_fulfillment_store).
                      if (widget.restaurant.address != null &&
                          (widget.restaurant.chainId == null ||
                              widget.restaurant.chainId!.trim().isEmpty))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.restaurant.address!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Status + rating row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.restaurant.isCurrentlyOpen
                                  ? AppTheme.successColor.withValues(alpha: 0.1)
                                  : AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.restaurant.isCurrentlyOpen
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  size: 14,
                                  color: widget.restaurant.isCurrentlyOpen
                                      ? AppTheme.successColor
                                      : AppTheme.accentColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.restaurant.isCurrentlyOpen
                                      ? 'Open Now'
                                      : 'Closed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.restaurant.isCurrentlyOpen
                                        ? AppTheme.successColor
                                        : AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.restaurant.formattedTodayHours != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.restaurant.formattedTodayHours!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${widget.restaurant.rating ?? '-'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                if (widget.restaurant.reviewCount != null) ...[
                                  Text(
                                    ' (${widget.restaurant.reviewCount})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Small button that jumps to the reviews section.
                          GestureDetector(
                            onTap: _openReviews,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.rate_review_outlined,
                                    size: 14,
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reviews',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delivery_dining_rounded,
                                  size: 16,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.restaurant.estimatedDeliveryTime ?? 30} min',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Cuisine + delivery fee row
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.restaurant.cuisineType ?? 'Multi-cuisine',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            // toStringAsFixed(2), else a 6.0 fee renders as
                            // "$6.0" — and hardcoding "$" ignores the app's
                            // configured currency.
                            'Delivery: ${AppConstants.currencySymbol}${(widget.restaurant.deliveryFee ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (widget.restaurant.description != null &&
                          widget.restaurant.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.restaurant.description!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Closed banner — shown at top so it's immediately visible
                if (!widget.restaurant.isCurrentlyOpen)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.accentColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This restaurant is closed. '
                            '${widget.restaurant.nextOpenLabel}. '
                            'You can schedule an order.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Menu Items
                Builder(
                  builder: (context) {
                    // Seed from the disk cache so the menu paints instantly on
                    // a cold launch; the live provider swaps in fresh items
                    // silently once it resolves.
                    final menuItems = menuItemsAsync.valueOrNull ??
                        CatalogCache.menu(widget.restaurant.id);
                    if (menuItems == null) {
                      if (menuItemsAsync.hasError) {
                        return AppErrorState(
                          message: friendlyError(menuItemsAsync.error),
                        );
                      }
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: AppLoadingIndicator(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      );
                    }
                    // Group items by category
                    final grouped = <String, List<MenuItem>>{};
                    for (final item in menuItems) {
                      grouped.putIfAbsent(item.category, () => []).add(item);
                    }
                    final categories = grouped.keys.toList();
                    if (categories.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(child: Text('No menu items yet')),
                      );
                    }

                    // Track the section order + a stable key per section so the
                    // chips can jump to a section and the scroll listener can
                    // highlight the section currently in view.
                    _orderedCategories = categories;
                    for (final cat in categories) {
                      _categoryKeys.putIfAbsent(cat, () => GlobalKey());
                    }
                    final activeCategory =
                        _selectedCategory ?? categories.first;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Menu section chips. Tapping one jumps to that section;
                        // the whole menu is one scrollable list, so a customer
                        // can also just scroll through every category in order.
                        SizedBox(
                          height: 52,
                          child: ListView.separated(
                            controller: _chipsController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            itemCount: categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final cat = categories[index];
                              final isActive = cat == activeCategory;
                              return GestureDetector(
                                onTap: () => _jumpToCategory(cat),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.primaryColor
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: isActive
                                          ? AppTheme.primaryColor
                                          : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      cat,
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Every category rendered in order: a section header
                        // (keyed, so chips can scroll to it) followed by its
                        // items. The customer can scroll straight through all of
                        // them, or jump via the chips above.
                        for (final cat in categories) ...[
                          Padding(
                            key: _categoryKeys[cat],
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${grouped[cat]!.length} item${grouped[cat]!.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...grouped[cat]!.map(
                            (item) => MenuItemCard(
                              item: item,
                              onTap: () => _showMenuItemDetail(context, item),
                              onAddTap: () => _showMenuItemDetail(context, item),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 140),
              ],
            ),
          ),
          // Footer with View Cart / Schedule Order
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Group Order mode: save items back to participant ──
                    if (widget.groupOrderId != null) ...[
                      Consumer(
                        builder: (context, ref, _) {
                          final count = ref.watch(cartItemCountProvider);
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _savingToGroup
                                  ? null
                                  : _saveToGroupOrder,
                              icon: _savingToGroup
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.group_add_rounded,
                                      size: 20,
                                    ),
                              label: Text(
                                count > 0
                                    ? 'Save $count item${count != 1 ? 's' : ''} to Group Order'
                                    : 'Save to Group Order',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      // ── Normal mode ─────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            // View Cart / Schedule Order (fills remaining space)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (!widget.restaurant.isCurrentlyOpen) {
                                    Navigator.pushNamed(
                                      context,
                                      '/cart',
                                      arguments: {
                                        'forceSchedule': true,
                                        'restaurant': widget.restaurant,
                                      },
                                    );
                                  } else {
                                    Navigator.pushNamed(context, '/cart');
                                  }
                                },
                                icon: Icon(
                                  widget.restaurant.isCurrentlyOpen
                                      ? Icons.shopping_cart_rounded
                                      : Icons.schedule_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  widget.restaurant.isCurrentlyOpen
                                      ? 'View Cart'
                                      : 'Schedule Order',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      widget.restaurant.isCurrentlyOpen
                                      ? AppTheme.primaryColor
                                      : AppTheme.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Group Order — icon-only square button
                            SizedBox(
                              height: 50,
                              width: 50,
                              child: OutlinedButton(
                                onPressed: _startingGroupOrder
                                    ? null
                                    : _startGroupOrder,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryColor,
                                  side: BorderSide(
                                    color: AppTheme.primaryColor,
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _startingGroupOrder
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.group_add_rounded,
                                        size: 22,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ], // end else (normal mode)
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<List<MenuItemSide>?> _showSidesSheet(
    BuildContext context,
    MenuItem item,
  ) async {
    final availableSides = item.sides!.where((s) => s.isAvailable).toList();
    final selected = <String, bool>{
      for (final s in availableSides) s.id: false,
    };

    return showModalBottomSheet<List<MenuItemSide>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final chosenSides = availableSides
                .where((s) => selected[s.id] == true)
                .toList();
            final sidesTotal = chosenSides.fold(0.0, (sum, s) => sum + s.price);

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add sides to ${item.name}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select any extras you\'d like',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...availableSides.map(
                    (side) => CheckboxListTile(
                      activeColor: AppTheme.primaryColor,
                      title: Text(side.name),
                      subtitle: Text('+ \$${side.price.toStringAsFixed(2)}'),
                      value: selected[side.id],
                      onChanged: (v) =>
                          setSheetState(() => selected[side.id] = v!),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx, chosenSides),
                      child: Text(
                        sidesTotal > 0
                            ? 'Add to Cart (+\$${sidesTotal.toStringAsFixed(2)})'
                            : 'Add to Cart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMenuItemDetail(BuildContext context, MenuItem item) =>
      presentMenuItemAndAddToCart(context, ref, item);
}

/// Full-screen search over one restaurant's menu — a familiar, friendly search
/// UX (system search bar, live results, tap to open the item). Returns the
/// chosen [MenuItem] so the caller can present it.
class _MenuSearchDelegate extends SearchDelegate<MenuItem?> {
  final String restaurantName;
  final List<MenuItem> items;

  _MenuSearchDelegate({required this.restaurantName, required this.items})
      : super(searchFieldLabel: 'Search the menu');

  List<MenuItem> _matches() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (m) =>
              m.name.toLowerCase().contains(q) ||
              (m.description ?? '').toLowerCase().contains(q) ||
              m.category.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = _matches();
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No menu items match "$query"',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final item = results[i];
        return MenuItemCard(
          item: item,
          onTap: () => close(context, item),
          onAddTap: () => close(context, item),
        );
      },
    );
  }
}
