import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../providers/feature_providers.dart';
import '../../models/banner_model.dart' as app;
import '../../utils/app_theme.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/smart_home_widgets.dart';
import '../../widgets/search_bar.dart' as search_bar;
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';
import 'meals_by_category_screen.dart';
import 'grocery_screen.dart';
import '../../core/utils/responsive.dart';

/// Emits the current peak-hour status every 30 seconds so the UI updates
/// in real time when a peak window starts or ends.
final isPeakHourProvider = StreamProvider<bool>((ref) {
  return Stream.periodic(
    const Duration(seconds: 30),
    (_) => AppConstants.isPeakHour,
  ).distinct();
});

// Fallback categories used when the DB hasn't loaded yet or returns empty.
// Sourced from [AppConstants.homeFoodCategories] so the restaurant menu
// dialog and the customer home stay in sync.
const _fallbackCategories = AppConstants.homeFoodCategories;

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
    // Only show ad popup when the food/home tab is visible (tab index 0)
    if (ref.read(currentTabIndexProvider) != 0) return;
    try {
      final adminService = ref.read(adminServiceProvider);
      final adsList = await adminService.getActiveAds();
      if (kDebugMode)
        debugPrint('[AdPopup] Fetched ${adsList.length} active ads from DB');
      if (adsList.isEmpty || !mounted || _adPopupShown) {
        if (kDebugMode)
          debugPrint('[AdPopup] No ads or already shown — skipping popup');
        return;
      }
      final ads = adsList
          .map((json) => RestaurantAd.fromJson(json))
          .where((ad) => ad.isCurrentlyActive)
          .toList();
      if (kDebugMode)
        debugPrint('[AdPopup] ${ads.length} currently active after filter');
      if (ads.isEmpty || !mounted) return;

      // ── AI-powered ad selection when multiple ads exist ──
      RestaurantAd bestAd;
      if (ads.length == 1) {
        bestAd = ads.first;
      } else {
        bestAd = await _pickBestAdForUser(ads);
      }
      if (kDebugMode) {
        debugPrint(
          '[AdPopup] Showing ad: "${bestAd.title}" (cuisine: ${bestAd.cuisineType})',
        );
      }

      _adPopupShown = true;
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
        builder: (ctx) => _AdPopupDialog(ad: bestAd, ref: ref),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AdPopup] Error fetching ads: $e');
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

      if (kDebugMode) {
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
      }

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
          if (topCuisine != null && adCuisine == topCuisine.toLowerCase()) {
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

        if (kDebugMode) {
          debugPrint(
            '[Brain AI] "${ad.title}" → ${score.toStringAsFixed(1)} $breakdown',
          );
        }
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
      if (kDebugMode) {
        debugPrint(
          '═══ [Brain AI] Winner: "${winner.ad.title}" (score: ${winner.score.toStringAsFixed(1)}, p: ${(probabilities[selectedIdx] * 100).toStringAsFixed(1)}%) ═══',
        );
        for (int i = 0; i < scored.length; i++) {
          debugPrint(
            '[Brain AI] #${i + 1} "${scored[i].ad.title}" → ${scored[i].score.toStringAsFixed(1)}pts (${(probabilities[i] * 100).toStringAsFixed(1)}%)',
          );
        }
      }

      return winner.ad;
    } catch (e) {
      if (kDebugMode)
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
    // Only show coupon popup when the food/home tab is visible (tab index 0)
    if (ref.read(currentTabIndexProvider) != 0) return;
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        cacheExtent: 2000,
        slivers: [
          SliverAppBar(
            floating: true,
            elevation: 0,
            automaticallyImplyLeading: false,
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
                Flexible(
                  child: Text(
                    'MealHub',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final isPeak = ref.watch(isPeakHourProvider).valueOrNull ??
                        AppConstants.isPeakHour;
                    if (!isPeak) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B35), Color(0xFFFF3D00)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'PEAK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shopping_cart_outlined,
                      color: Theme.of(context).colorScheme.onSurface,
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
                        );
                      },
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
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
                margin: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
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
                          Text(
                            'Deliver to',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            userAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
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

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Search bar + Taxi button
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
              child: search_bar.CustomSearchBar(
                hintText: 'Search for restaurant or food',
                onChanged: (q) {
                  setState(() => _searchQuery = q);
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

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          if (isSearching && searchAsync != null)
            ..._buildSearchResults(searchAsync),

          if (!isSearching) ...[
            // AI-powered smart offer banner
            const SliverToBoxAdapter(child: SmartOfferBanner()),

            // Dynamic Promotional Banners
            SliverToBoxAdapter(
              child: RepaintBoundary(child: _DynamicBannerCarousel()),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 6)),

            // Browse by Category (right below banners)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 4,
                ),
                child: Text(
                  'Browse by Category',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: SizedBox(
                  height: 84,
                  child: Builder(
                    builder: (context) {
                      final categoriesAsync = ref.watch(foodCategoriesProvider);
                      final categories =
                          categoriesAsync.valueOrNull?.isNotEmpty == true
                          ? categoriesAsync.value!
                          : _fallbackCategories;
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: false,
                        padding: EdgeInsets.symmetric(
                          horizontal: Responsive.horizontalPadding(context),
                          vertical: 4,
                        ),
                        itemCount: categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final cat = categories[index];
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MealsByCategoryScreen(
                                    categoryName: cat['name']!,
                                    categoryEmoji: cat['emoji'],
                                  ),
                                ),
                              );
                            },
                            child: SizedBox(
                              width: 58,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      cat['emoji']!,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    cat['name']!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // Quick Services row
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                    child: Text(
                      'More Services',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                    child: Row(
                      children: [
                        _ServiceCard(
                          icon: Icons.directions_car,
                          label: 'Book a Ride',
                          color: const Color(0xFF1E40AF),
                          onTap: () => Navigator.pushNamed(context, '/ride-home'),
                        ),
                        const SizedBox(width: 12),
                        _ServiceCard(
                          icon: Icons.local_grocery_store,
                          label: 'Grocery',
                          color: const Color(0xFF059669),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GroceryScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ServiceCard(
                          icon: Icons.local_car_wash,
                          label: 'Car Services',
                          color: const Color(0xFF7C3AED),
                          onTap: () => Navigator.pushNamed(context, '/car-services'),
                        ),
                        const SizedBox(width: 12),
                        _ServiceCard(
                          icon: Icons.local_laundry_service_rounded,
                          label: 'Laundry',
                          color: const Color(0xFF0F4C81),
                          onTap: () => Navigator.pushNamed(context, '/laundry'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

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
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 8,
                ),
                child: Text(
                  'All Restaurants',
                  style: TextStyle(
                    fontSize: Responsive.headingMedium(context),
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),

            allRestaurantsAsync.when(
              data: (restaurants) {
                final display = restaurants.take(15).toList();
                return SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
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
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
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
          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context), vertical: 8),
          child: Text(
            'Search Results',
            style: TextStyle(fontSize: Responsive.headingMedium(context), fontWeight: FontWeight.w700),
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
            padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
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
            onViewAll: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _RestaurantSectionViewAllScreen(
                  title: title,
                  restaurants: restaurants,
                ),
              ),
            ),
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
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HorizontalRestaurantRow extends StatelessWidget {
  final String title;
  final List<Restaurant> restaurants;
  final VoidCallback? onViewAll;

  const _HorizontalRestaurantRow({
    required this.title,
    required this.restaurants,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context), vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Responsive.headingMedium(context),
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            addAutomaticKeepAlives: false,
            padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
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

class _RestaurantSectionViewAllScreen extends StatelessWidget {
  final String title;
  final List<Restaurant> restaurants;

  const _RestaurantSectionViewAllScreen({
    required this.title,
    required this.restaurants,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 12, Responsive.horizontalPadding(context), 32),
        itemCount: restaurants.length,
        itemBuilder: (context, i) {
          final r = restaurants[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RestaurantCard(
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                  ? Image.network(
                      restaurant.imageUrl!,
                      height: 110,
                      width: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : _placeholder(),
                    )
                  : _placeholder(),
            ),
            Padding(
              padding: EdgeInsets.all(Responsive.cardPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: Responsive.bodyText(context),
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    restaurant.cuisineType ?? 'Multi-cuisine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${restaurant.estimatedDeliveryTime ?? 30} min',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
  int _bannerCount = 0;
  Timer? _autoScrollTimer;

  void _startAutoScroll(int count) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _bannerCount = count;
    if (count <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % _bannerCount;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(activeBannersProvider);

    // ref.listen fires on every provider transition (loading→data, data→data).
    // This is the correct Riverpod hook for triggering side effects.
    ref.listen<AsyncValue<List<app.Banner>>>(activeBannersProvider, (_, next) {
      next.whenData((banners) {
        if (banners.length != _bannerCount || _autoScrollTimer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startAutoScroll(banners.length);
          });
        }
      });
    });

    return bannersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();

        // ref.listen doesn't fire for the value already available on first
        // build, so kick off the timer here if it hasn't started yet.
        if (_autoScrollTimer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startAutoScroll(banners.length);
          });
        }

        return Column(
          children: [
            SizedBox(
              height: 118,
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
                          : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
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
        margin: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
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
              Image.network(
                banner.imageUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
                errorBuilder: (_, __, ___) => Container(
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
                    child: Icon(
                      Icons.local_offer_rounded,
                      size: 120,
                      color: Colors.white.withValues(alpha: 0.15),
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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    banner.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (banner.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      banner.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
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
            color: Theme.of(context).cardColor,
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
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
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
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            color: Colors.grey[700],
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
                                  color: Colors.grey[700],
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
                          backgroundColor: Theme.of(context).colorScheme.onSurface,
                          foregroundColor: Theme.of(context).colorScheme.surface,
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
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultAdBg(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _defaultAdBg(),
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

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
