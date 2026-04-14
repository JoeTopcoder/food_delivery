import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../models/restaurant_model.dart';
import '../../models/restaurant_ad_model.dart';
import '../../models/user_event_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/banner_provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/recommendation_provider.dart';
import '../../models/banner_model.dart' as app;
import '../../utils/app_theme.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/smart_home_widgets.dart';
import '../../widgets/search_bar.dart' as search_bar;
import '../../utils/friendly_error.dart';

// Emoji categories for the Browse by Category grid
const _emojiCategories = <Map<String, String>>[
  {'emoji': '\u{1F373}', 'name': 'Breakfast'},
  {'emoji': '\u{1F354}', 'name': 'Fast Food'},
  {'emoji': '\u{1F355}', 'name': 'Pizza'},
  {'emoji': '\u{1F357}', 'name': 'Chicken'},
  {'emoji': '\u{1F32E}', 'name': 'Mexican'},
  {'emoji': '\u{1F35C}', 'name': 'Chinese'},
  {'emoji': '\u{1F363}', 'name': 'Sushi'},
  {'emoji': '\u{1F957}', 'name': 'Healthy'},
  {'emoji': '\u{1F370}', 'name': 'Dessert'},
  {'emoji': '\u{2615}', 'name': 'Coffee'},
  {'emoji': '\u{1F964}', 'name': 'Drinks'},
  {'emoji': '\u{1F331}', 'name': 'Vegan'},
];

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  String _searchQuery = '';
  bool _trackedOpen = false;
  bool _couponPopupShown = false;
  bool _adPopupShown = false;

  @override
  void initState() {
    super.initState();
    // Fetch and show ad popup once when the screen first loads
    // Use a short delay to ensure navigation transitions are complete
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _fetchAndShowAd();
    });
  }

  Future<void> _fetchAndShowAd() async {
    if (_adPopupShown || !mounted) return;
    try {
      final adminService = ref.read(adminServiceProvider);
      final adsList = await adminService.getActiveAds();
      debugPrint('[AdPopup] Fetched ${adsList.length} active ads from DB');
      if (adsList.isEmpty || !mounted || _adPopupShown) {
        debugPrint('[AdPopup] No ads or already shown — skipping popup');
        return;
      }
      final ads = adsList
          .map((json) => RestaurantAd.fromJson(json))
          .where((ad) => ad.isCurrentlyActive)
          .toList();
      debugPrint('[AdPopup] ${ads.length} currently active after filter');
      if (ads.isEmpty || !mounted) return;

      // ── AI-powered ad selection when multiple ads exist ──
      RestaurantAd bestAd;
      if (ads.length == 1) {
        bestAd = ads.first;
      } else {
        bestAd = await _pickBestAdForUser(ads);
      }
      debugPrint(
        '[AdPopup] Showing ad: "${bestAd.title}" (cuisine: ${bestAd.cuisineType})',
      );

      _adPopupShown = true;
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
        builder: (ctx) => _AdPopupDialog(ad: bestAd, ref: ref),
      );
    } catch (e) {
      debugPrint('[AdPopup] Error fetching ads: $e');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// Top-tier AI Ad Ranking Engine
  /// ═══════════════════════════════════════════════════════════════════════
  /// Uses 8 intelligence dimensions to produce a weighted relevance score
  /// for each ad, then applies temperature-scaled softmax sampling so the
  /// top-ranked ad almost always wins but occasionally a runner-up breaks
  /// through (exploration vs exploitation — standard in recommendation AI).
  ///
  /// Dimensions & weight budget (total ≈ 100):
  ///   1. Cuisine Affinity        → 0-30  (profile cuisine_scores + top match)
  ///   2. Behavioral Recency      → 0-20  (recent restaurant_view / category_tap)
  ///   3. Time-of-Day Alignment   → 0-10  (preferred_order_times vs now)
  ///   4. Segment Strategy        → 0-10  (new_user / power_user / inactive / churning)
  ///   5. Churn Recovery Boost    → 0-8   (high churn_risk → win-back ads)
  ///   6. Deal Sensitivity        → 0-7   (deal_sensitivity + price_sensitivity)
  ///   7. Freshness Decay         → 0-8   (newer ads score higher, logarithmic)
  ///   8. Real-time Session Boost → 0-7   (in-session taps from realtimeBoostProvider)
  /// ═══════════════════════════════════════════════════════════════════════
  Future<RestaurantAd> _pickBestAdForUser(List<RestaurantAd> ads) async {
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return ads.first;

      // ── Gather all intelligence signals in parallel ──────────────────
      final recService = ref.read(recommendationServiceProvider);
      final trackingService = ref.read(behaviorTrackingProvider);

      final results = await Future.wait([
        recService.getProfile(userId), // [0] profile
        trackingService.getRecentEvents(userId, limit: 80), // [1] events
      ]);

      final profile = results[0] as dynamic;
      final recentEvents = results[1] as List<UserEvent>;

      // Brain engine cache (already computed on home load)
      final brainAsync = ref.read(brainEngineProvider);
      String? brainTopCuisine;
      String brainSegment = 'new_user';
      double brainChurnRisk = 0;
      brainAsync.whenData((brain) {
        brainTopCuisine = brain.topCuisine;
        brainSegment = brain.userSegment;
        brainChurnRisk = brain.churnRisk;
      });

      // Profile data (richer, from DB)
      final Map<String, double> cuisineScores =
          profile?.cuisineScores as Map<String, double>? ?? {};
      final double dealSensitivity =
          (profile?.dealSensitivity as double?) ?? 0.5;
      final double priceSensitivity =
          (profile?.priceSensitivity as double?) ?? 0.5;
      final double churnRisk =
          (profile?.churnRisk as double?) ?? brainChurnRisk;
      final String userSegment =
          (profile?.userSegment as String?) ?? brainSegment;
      final String? topCuisine =
          brainTopCuisine ?? (profile?.topCuisine as String?);
      final List<String> favoriteCategories =
          (profile?.favoriteCategories as List<String>?) ?? [];
      final Map<String, int> preferredOrderTimes =
          (profile?.preferredOrderTimes as Map<String, int>?) ?? {};
      final int totalOrders = (profile?.totalOrders as int?) ?? 0;
      final double activityScore = (profile?.activityScore as double?) ?? 0;

      // Real-time session boosts
      final sessionBoosts = ref.read(realtimeBoostProvider);

      // ── Pre-compute behavioral signals from recent events ───────────
      // Count restaurant views per restaurant (last 80 events)
      final restaurantViewCounts = <String, int>{};
      final cuisineTapCounts = <String, int>{};
      for (final evt in recentEvents) {
        if (evt.eventType == EventTypes.restaurantView) {
          final rid = evt.metadata['restaurant_id'] as String?;
          if (rid != null)
            restaurantViewCounts[rid] = (restaurantViewCounts[rid] ?? 0) + 1;
          final c = evt.metadata['cuisine'] as String?;
          if (c != null)
            cuisineTapCounts[c.toLowerCase()] =
                (cuisineTapCounts[c.toLowerCase()] ?? 0) + 1;
        } else if (evt.eventType == EventTypes.categoryTap) {
          final cat = evt.metadata['category'] as String?;
          if (cat != null)
            cuisineTapCounts[cat.toLowerCase()] =
                (cuisineTapCounts[cat.toLowerCase()] ?? 0) + 1;
        } else if (evt.eventType == EventTypes.searchQuery) {
          final q = (evt.metadata['query'] as String? ?? '').toLowerCase();
          if (q.isNotEmpty)
            cuisineTapCounts[q] = (cuisineTapCounts[q] ?? 0) + 1;
        }
      }

      // Current hour bucket for time-of-day matching
      final currentHour = DateTime.now().hour;
      final String timeSlot;
      if (currentHour >= 6 && currentHour < 11) {
        timeSlot = 'morning';
      } else if (currentHour >= 11 && currentHour < 15) {
        timeSlot = 'lunch';
      } else if (currentHour >= 15 && currentHour < 18) {
        timeSlot = 'afternoon';
      } else if (currentHour >= 18 && currentHour < 22) {
        timeSlot = 'dinner';
      } else {
        timeSlot = 'late_night';
      }

      debugPrint('═══ [Brain AI] Ad Ranking Engine ═══');
      debugPrint(
        '[Brain AI] Segment: $userSegment | TopCuisine: $topCuisine | ChurnRisk: ${churnRisk.toStringAsFixed(2)}',
      );
      debugPrint(
        '[Brain AI] DealSens: ${dealSensitivity.toStringAsFixed(2)} | PriceSens: ${priceSensitivity.toStringAsFixed(2)} | Orders: $totalOrders',
      );
      debugPrint(
        '[Brain AI] TimeSlot: $timeSlot | Activity: ${activityScore.toStringAsFixed(2)}',
      );
      debugPrint('[Brain AI] RecentViews: $restaurantViewCounts');
      debugPrint('[Brain AI] CuisineTaps: $cuisineTapCounts');
      debugPrint('[Brain AI] SessionBoosts: $sessionBoosts');

      // ══════════════════════════════════════════════════════════════════
      // SCORING FUNCTION — 8 dimensions
      // ══════════════════════════════════════════════════════════════════
      double scoreAd(RestaurantAd ad) {
        double score = 0;
        final adCuisine = ad.cuisineType?.toLowerCase() ?? '';
        final breakdown = <String, double>{};

        // ── 1. Cuisine Affinity (0-30) ───────────────────────────────
        double cuisineScore = 0;
        if (adCuisine.isNotEmpty) {
          // Direct match with #1 cuisine
          if (topCuisine != null && adCuisine == topCuisine?.toLowerCase()) {
            cuisineScore += 20;
          }
          // Weighted score from cuisine_scores map (0-1 normalized → 0-15)
          for (final entry in cuisineScores.entries) {
            if (entry.key.toLowerCase() == adCuisine) {
              cuisineScore += entry.value * 15;
              break;
            }
          }
          // Favorite categories match (0-5)
          for (final fav in favoriteCategories) {
            if (fav.toLowerCase() == adCuisine ||
                adCuisine.contains(fav.toLowerCase())) {
              cuisineScore += 5;
              break;
            }
          }
        }
        cuisineScore = cuisineScore.clamp(0, 30);
        score += cuisineScore;
        breakdown['cuisine'] = cuisineScore;

        // ── 2. Behavioral Recency (0-20) ─────────────────────────────
        double behaviorScore = 0;
        // Did user recently view this exact restaurant?
        final viewCount = restaurantViewCounts[ad.restaurantId] ?? 0;
        if (viewCount > 0) {
          behaviorScore += (viewCount * 4.0).clamp(0, 12); // up to 12 pts
        }
        // Did user recently tap on this cuisine?
        final cuisineTaps = cuisineTapCounts[adCuisine] ?? 0;
        if (cuisineTaps > 0) {
          behaviorScore += (cuisineTaps * 2.0).clamp(0, 8); // up to 8 pts
        }
        behaviorScore = behaviorScore.clamp(0, 20);
        score += behaviorScore;
        breakdown['behavior'] = behaviorScore;

        // ── 3. Time-of-Day Alignment (0-10) ──────────────────────────
        double timeScore = 0;
        final slotOrders = preferredOrderTimes[timeSlot] ?? 0;
        final totalTimeOrders = preferredOrderTimes.values.fold(
          0,
          (a, b) => a + b,
        );
        if (totalTimeOrders > 0 && slotOrders > 0) {
          // User orders in this time slot → boost all ads (user is active now)
          final timeAffinity = slotOrders / totalTimeOrders;
          timeScore = timeAffinity * 10;
        } else {
          // Time slot with no data — mild base score
          timeScore = 3;
        }
        // Breakfast ads boosted in morning, etc.
        if (adCuisine.contains('breakfast') && timeSlot == 'morning')
          timeScore += 3;
        if (adCuisine.contains('coffee') &&
            (timeSlot == 'morning' || timeSlot == 'afternoon'))
          timeScore += 2;
        if (adCuisine.contains('dessert') &&
            (timeSlot == 'dinner' || timeSlot == 'late_night'))
          timeScore += 2;
        timeScore = timeScore.clamp(0, 10);
        score += timeScore;
        breakdown['time'] = timeScore;

        // ── 4. Segment Strategy (0-10) ───────────────────────────────
        double segmentScore = 0;
        switch (userSegment) {
          case 'new_user':
            // New users → show popular/trendy ads (newest ones)
            final ageHours = DateTime.now().difference(ad.createdAt).inHours;
            segmentScore = (ageHours < 48)
                ? 10
                : (ageHours < 168)
                ? 7
                : 4;
            break;
          case 'power_user':
            // Power users → reward loyalty, boost cuisine match further
            segmentScore = cuisineScore > 15 ? 10 : 5;
            break;
          case 'inactive':
            // Inactive users → win-back with any engaging content
            segmentScore = 8;
            break;
          case 'regular':
            segmentScore = 6;
            break;
          default:
            segmentScore = 5;
        }
        score += segmentScore;
        breakdown['segment'] = segmentScore;

        // ── 5. Churn Recovery Boost (0-8) ────────────────────────────
        double churnScore = 0;
        if (churnRisk > 0.7) {
          // High risk → strong boost for any engaging ad
          churnScore = 8;
        } else if (churnRisk > 0.4) {
          churnScore = 4;
        } else {
          churnScore = 1;
        }
        score += churnScore;
        breakdown['churn'] = churnScore;

        // ── 6. Deal & Price Sensitivity (0-7) ────────────────────────
        double dealScore = 0;
        // Higher deal sensitivity → more interested in any promo
        dealScore += dealSensitivity * 4; // 0-4
        // Price sensitive users → boost lower-end / deal-style ads
        dealScore += priceSensitivity * 3; // 0-3
        dealScore = dealScore.clamp(0, 7);
        score += dealScore;
        breakdown['deal'] = dealScore;

        // ── 7. Freshness Decay (0-8) ─────────────────────────────────
        double freshnessScore = 0;
        final adAgeHours = DateTime.now()
            .difference(ad.createdAt)
            .inHours
            .clamp(1, 10000);
        // Logarithmic decay: fresh ads score higher, old ads plateau
        freshnessScore = 8 - (log(adAgeHours) / log(10000) * 8);
        freshnessScore = freshnessScore.clamp(0, 8);
        score += freshnessScore;
        breakdown['freshness'] = freshnessScore;

        // ── 8. Real-time Session Boost (0-7) ─────────────────────────
        double sessionScore = 0;
        if (adCuisine.isNotEmpty) {
          final boost = ref
              .read(realtimeBoostProvider.notifier)
              .boostFor(adCuisine);
          sessionScore = ((boost - 1.0) * 14).clamp(
            0,
            7,
          ); // boost 1.0-1.5 → 0-7
        }
        // Also boost if user tapped this restaurant's category in-session
        for (final key in sessionBoosts.keys) {
          if (adCuisine.contains(key.toLowerCase()) ||
              (ad.restaurantName?.toLowerCase().contains(key.toLowerCase()) ??
                  false)) {
            sessionScore = (sessionScore + 3).clamp(0, 7);
            break;
          }
        }
        score += sessionScore;
        breakdown['session'] = sessionScore;

        debugPrint(
          '[Brain AI] "${ad.title}" → ${score.toStringAsFixed(1)} $breakdown',
        );
        return score;
      }

      // ── Score all ads ──────────────────────────────────────────────
      final scored = ads.map((ad) => (ad: ad, score: scoreAd(ad))).toList();

      // ── Softmax sampling (temperature=0.3 → heavily favors top) ───
      // Instead of always picking #1, softmax gives a small chance to
      // runner-ups, preventing the same ad from always winning.
      const temperature = 0.3;
      final maxScore = scored.map((s) => s.score).reduce(max);
      final expScores = scored
          .map((s) => exp((s.score - maxScore) / temperature))
          .toList();
      final sumExp = expScores.fold(0.0, (a, b) => a + b);
      final probabilities = expScores.map((e) => e / sumExp).toList();

      // Weighted random selection
      final rand = Random().nextDouble();
      double cumulative = 0;
      int selectedIdx = 0;
      for (int i = 0; i < probabilities.length; i++) {
        cumulative += probabilities[i];
        if (rand <= cumulative) {
          selectedIdx = i;
          break;
        }
      }

      final winner = scored[selectedIdx];
      debugPrint(
        '═══ [Brain AI] Winner: "${winner.ad.title}" (score: ${winner.score.toStringAsFixed(1)}, p: ${(probabilities[selectedIdx] * 100).toStringAsFixed(1)}%) ═══',
      );
      for (int i = 0; i < scored.length; i++) {
        debugPrint(
          '[Brain AI] #${i + 1} "${scored[i].ad.title}" → ${scored[i].score.toStringAsFixed(1)}pts (${(probabilities[i] * 100).toStringAsFixed(1)}%)',
        );
      }

      return winner.ad;
    } catch (e) {
      debugPrint('[Brain AI] Engine error, falling back to first ad: $e');
      return ads.first;
    }
  }

  void _trackAppOpen() {
    if (_trackedOpen) return;
    _trackedOpen = true;
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) {
      ref.read(behaviorTrackingProvider).trackAppOpen(userId);
    }
  }

  void _showCouponPopupOnce() {
    if (_couponPopupShown) return;
    final brainState = ref.read(brainEngineProvider);
    brainState.whenData((brain) {
      if (brain.activeCoupon != null && !_couponPopupShown && mounted) {
        _couponPopupShown = true;
        showCouponPopup(context, brain.activeCoupon!, brain.userSegment);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Track first build as app open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackAppOpen();
      _showCouponPopupOnce();
    });

    final currentUser = ref.watch(currentUserProvider);
    final defaultAddrAsync = currentUser != null
        ? ref.watch(defaultAddressProvider(currentUser.id))
        : null;
    final userAddress =
        defaultAddrAsync?.valueOrNull?.address ??
        currentUser?.address ??
        'Tap to set delivery address';

    final isSearching = _searchQuery.isNotEmpty;
    final searchAsync = isSearching
        ? ref.watch(restaurantSearchProvider(_searchQuery))
        : null;

    final newlyAddedAsync = ref.watch(newlyAddedRestaurantsProvider);
    final topRatedAsync = ref.watch(topRatedRestaurantsProvider);
    final breakfastAsync = ref.watch(breakfastRestaurantsProvider);
    final mustTryAsync = ref.watch(mustTryRestaurantsProvider);
    final allRestaurantsAsync = ref.watch(allRestaurantsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        cacheExtent: 500,
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'FoodHub',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppTheme.textPrimary,
                    ),
                    onPressed: () => Navigator.pushNamed(context, '/cart'),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final cartItems = ref.watch(cartProvider);
                        if (cartItems.isEmpty) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
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
                        );
                      },
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppTheme.textPrimary,
                ),
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // Location picker
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/address-book'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Deliver to',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            userAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: search_bar.CustomSearchBar(
                hintText: 'Search for restaurant or food',
                onChanged: (q) {
                  setState(() => _searchQuery = q);
                  // Track search queries for AI engine
                  if (q.length >= 3) {
                    final userId = ref.read(currentUserIdProvider);
                    if (userId != null) {
                      ref.read(behaviorTrackingProvider).trackSearch(userId, q);
                    }
                  }
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          if (isSearching && searchAsync != null)
            ..._buildSearchResults(searchAsync),

          if (!isSearching) ...[
            // AI-powered smart offer banner
            const SliverToBoxAdapter(child: SmartOfferBanner()),

            // Dynamic Promotional Banners
            SliverToBoxAdapter(child: _DynamicBannerCarousel()),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // Browse by Category (right below banners)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: const Text(
                  'Browse by Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _emojiCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final cat = _emojiCategories[index];
                    return GestureDetector(
                      onTap: () {
                        final userId = ref.read(currentUserIdProvider);
                        if (userId != null) {
                          ref
                              .read(behaviorTrackingProvider)
                              .trackCategoryTap(userId, cat['name']!);
                          ref
                              .read(realtimeBoostProvider.notifier)
                              .recordInteraction(cat['name']!);
                        }
                        Navigator.pushNamed(
                          context,
                          '/all-restaurants',
                          arguments: cat['name'],
                        );
                      },
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                cat['emoji']!,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat['name']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // AI-powered smart sections (Made for You, Because you love X, etc.)
            SliverToBoxAdapter(
              child: SmartHomeSections(
                onRestaurantTap: (rec) async {
                  final restaurant = await ref
                      .read(restaurantServiceProvider)
                      .getRestaurantById(rec.restaurantId);
                  if (restaurant != null && context.mounted) {
                    Navigator.pushNamed(
                      context,
                      '/restaurant-detail',
                      arguments: restaurant,
                    );
                  }
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            _buildHorizontalSection(
              title: 'You might love these \u{2764}\u{FE0F}',
              asyncValue: topRatedAsync,
            ),

            _buildHorizontalSection(
              title: 'Newly Added \u{1F195}',
              asyncValue: newlyAddedAsync,
            ),

            _buildHorizontalSection(
              title: 'Breakfast \u{1F373}',
              asyncValue: breakfastAsync,
            ),

            _buildHorizontalSection(
              title: 'Must Try \u{1F525}',
              asyncValue: mustTryAsync,
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: const Text(
                  'All Restaurants',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),

            allRestaurantsAsync.when(
              data: (restaurants) {
                final display = restaurants.take(15).toList();
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final r = display[index];
                      return RepaintBoundary(
                        child: RestaurantCard(
                          restaurant: r,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/restaurant-detail',
                            arguments: r,
                          ),
                        ),
                      );
                    }, childCount: display.length),
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(child: _loadingIndicator()),
              error: (err, _) => SliverToBoxAdapter(
                child: _emptyPlaceholder(friendlyError(err)),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/all-restaurants'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'See All Restaurants',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildSearchResults(AsyncValue<List<Restaurant>> asyncValue) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: const Text(
            'Search Results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      asyncValue.when(
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return SliverToBoxAdapter(
              child: _emptyPlaceholder('No restaurants found'),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final r = restaurants[index];
                return RestaurantCard(
                  restaurant: r,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/restaurant-detail',
                    arguments: r,
                  ),
                );
              }, childCount: restaurants.length),
            ),
          );
        },
        loading: () => SliverToBoxAdapter(child: _loadingIndicator()),
        error: (err, _) =>
            SliverToBoxAdapter(child: _emptyPlaceholder(friendlyError(err))),
      ),
    ];
  }

  Widget _buildHorizontalSection({
    required String title,
    required AsyncValue<List<Restaurant>> asyncValue,
  }) {
    return SliverToBoxAdapter(
      child: asyncValue.when(
        data: (restaurants) {
          if (restaurants.isEmpty) return const SizedBox.shrink();
          return _HorizontalRestaurantRow(
            title: title,
            restaurants: restaurants,
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _loadingIndicator() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: CircularProgressIndicator(color: AppTheme.primaryColor),
    ),
  );

  Widget _emptyPlaceholder(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.restaurant_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    ),
  );
}

class _HorizontalRestaurantRow extends StatelessWidget {
  final String title;
  final List<Restaurant> restaurants;

  const _HorizontalRestaurantRow({
    required this.title,
    required this.restaurants,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: restaurants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final r = restaurants[index];
              return RepaintBoundary(
                child: _CompactRestaurantCard(
                  restaurant: r,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/restaurant-detail',
                    arguments: r,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CompactRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const _CompactRestaurantCard({required this.restaurant, required this.onTap});

  static final _placeholderColors = [
    AppTheme.primaryColor.withValues(alpha: 0.15),
    AppTheme.primaryColor.withValues(alpha: 0.05),
  ];
  static final _placeholderIconColor = AppTheme.primaryColor.withValues(
    alpha: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child:
                  restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: restaurant.imageUrl!,
                      height: 110,
                      width: 180,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    restaurant.cuisineType ?? 'Multi-cuisine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${restaurant.rating ?? '-'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${restaurant.estimatedDeliveryTime ?? 30} min',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    height: 110,
    width: 180,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _placeholderColors,
      ),
    ),
    child: Icon(
      Icons.restaurant_rounded,
      size: 36,
      color: _placeholderIconColor,
    ),
  );
}

// ─── Dynamic Banner Carousel ──────────────────────────────────────────────────

class _DynamicBannerCarousel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DynamicBannerCarousel> createState() =>
      _DynamicBannerCarouselState();
}

class _DynamicBannerCarouselState
    extends ConsumerState<_DynamicBannerCarousel> {
  final PageController _pageCtrl = PageController(viewportFraction: 1.0);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(activeBannersProvider);

    return bannersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final banner = banners[index];
                  return _bannerCard(context, banner);
                },
              ),
            ),
            if (banners.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  banners.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentPage == i ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? AppTheme.primaryColor
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _bannerCard(BuildContext context, app.Banner banner) {
    return GestureDetector(
      onTap: () async {
        try {
          final data = await SupabaseConfig.client
              .from('restaurants')
              .select()
              .eq('id', banner.restaurantId)
              .single();
          final restaurant = Restaurant.fromJson(data);
          if (context.mounted) {
            Navigator.pushNamed(
              context,
              '/restaurant-detail',
              arguments: restaurant,
            );
          }
        } catch (_) {
          // Silently fail if restaurant not found
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor,
              AppTheme.primaryColor.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
                errorWidget: (_, _, _) => Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryColor.withValues(alpha: 0.75),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 0, bottom: 0),
                        child: Icon(
                          Icons.local_offer_rounded,
                          size: 120,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (banner.imageUrl == null || banner.imageUrl!.isEmpty)
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  Icons.local_offer_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    banner.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (banner.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      banner.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Visit ${banner.restaurantName ?? 'Restaurant'}',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Featured Ad Popup Dialog (auto-shows on home screen) ───────────────────

class _AdPopupDialog extends StatelessWidget {
  final RestaurantAd ad;
  final WidgetRef ref;
  const _AdPopupDialog({required this.ad, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hero image with close button overlaid
                  Stack(
                    children: [
                      SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: _buildAdImage(),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Sponsored tag
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF6B6B,
                            ).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'SPONSORED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      ad.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  if (ad.description != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        ad.description!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Restaurant name
                  if (ad.restaurantName != null) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront,
                            size: 15,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              ad.restaurantName!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          if (ad.cuisineType != null)
                            Flexible(
                              child: Text(
                                ' · ${ad.cuisineType}',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // "Order now" button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final nav = Navigator.of(
                            context,
                            rootNavigator: true,
                          );
                          nav.pop(); // close dialog
                          final restaurant = await ref
                              .read(restaurantServiceProvider)
                              .getRestaurantById(ad.restaurantId);
                          if (restaurant != null) {
                            // Mark that we came from an ad
                            ref.read(_activeAdProvider.notifier).state = ad;
                            nav.pushNamed(
                              '/restaurant-detail',
                              arguments: restaurant,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Order now',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdImage() {
    final url = ad.restaurantImageUrl ?? ad.imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _defaultAdBg(),
      );
    }
    return _defaultAdBg();
  }

  Widget _defaultAdBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B35), Color(0xFFFF3D00)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.restaurant_menu, color: Colors.white24, size: 80),
      ),
    );
  }
}

/// Provider to track when a customer navigated from a featured ad.
/// If non-null, any order placed should get +5% commission boost.
final _activeAdProvider = StateProvider<RestaurantAd?>((ref) => null);

/// Public getter for the active ad (used in checkout)
final activeAdForOrderProvider = Provider<RestaurantAd?>((ref) {
  return ref.watch(_activeAdProvider);
});

/// Clear the active ad (call after order is placed)
void clearActiveAd(WidgetRef ref) {
  ref.read(_activeAdProvider.notifier).state = null;
}
