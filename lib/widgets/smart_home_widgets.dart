import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/recommendation_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/restaurant_card.dart';
import 'package:food_driver/config/app_constants.dart';

// ════════════════════════════════════════════════════════════════
// Smart Offer Banner — shows AI-generated coupon at top of screen
// ════════════════════════════════════════════════════════════════

class SmartOfferBanner extends ConsumerWidget {
  const SmartOfferBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Apology coupons (code starts with SORRY) take priority and override
    // every other offer banner — the user just had a bad experience.
    final activeCouponsAsync = ref.watch(activeCouponsProvider);
    final apology = activeCouponsAsync.maybeWhen(
      data: (list) {
        for (final c in list) {
          if (c.code.toUpperCase().startsWith('SORRY')) return c;
        }
        return null;
      },
      orElse: () => null,
    );
    if (apology != null) {
      return _ApologyCouponBanner(coupon: apology);
    }

    // Banner is now just a thin reminder strip — main offer is in popup
    final brainAsync = ref.watch(brainEngineProvider);

    return brainAsync.when(
      data: (brain) {
        final coupon = brain.activeCoupon;
        if (coupon == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => showCouponPopup(context, coupon, brain.userSegment),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    brain.userSegment == 'new_user' ||
                        brain.userSegment == 'inactive'
                    ? [const Color(0xFFFF6B35), const Color(0xFFFF8C5A)]
                    : [const Color(0xFF6366F1), const Color(0xFF818CF8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_offer_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${coupon.discountPercent}% OFF — Tap to view your code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white70,
                  size: 14,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Coupon Popup Dialog — full-screen overlay with coupon details
// ════════════════════════════════════════════════════════════════

void showCouponPopup(BuildContext context, SmartCoupon coupon, String segment) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss coupon',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) =>
        _CouponPopupContent(coupon: coupon, segment: segment),
    transitionBuilder: (_, animation, __, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _CouponPopupContent extends StatelessWidget {
  final SmartCoupon coupon;
  final String segment;

  const _CouponPopupContent({required this.coupon, required this.segment});

  @override
  Widget build(BuildContext context) {
    final isWelcome = segment == 'new_user';
    final primaryColor = isWelcome
        ? const Color(0xFFFF6B35)
        : const Color(0xFF6366F1);
    final secondaryColor = isWelcome
        ? const Color(0xFFFF8C5A)
        : const Color(0xFF818CF8);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gradient header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isWelcome ? '\u{1F389}' : '\u{1F381}',
                        style: const TextStyle(fontSize: 30),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${coupon.discountPercent}% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          coupon.reason,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Code section
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Column(
                    children: [
                      Text(
                        'Your promo code',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.3),
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: primaryColor.withValues(alpha: 0.05),
                        ),
                        child: Center(
                          child: Text(
                            coupon.code,
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (coupon.minOrder > 0)
                        Text(
                          'Min. order: \$${coupon.minOrder.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 11,
                          ),
                        ),
                      Text(
                        'Expires in ${coupon.expiresInHours ~/ 24} days',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy + Close buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: coupon.code));
                            HapticFeedback.mediumImpact();
                            Navigator.of(context).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final messenger = ScaffoldMessenger.maybeOf(
                                context,
                              );
                              messenger?.showSnackBar(
                                SnackBar(
                                  content: Text('Code ${coupon.code} copied!'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Code & Start Ordering'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Maybe later',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Smart Recommendation Section — horizontal scrolling row
// ════════════════════════════════════════════════════════════════

class SmartRecommendationSection extends StatelessWidget {
  final String title;
  final String emoji;
  final List<SmartRecommendation> recommendations;
  final VoidCallback? onSeeAll;
  final void Function(SmartRecommendation rec)? onTap;
  final Color? accentColor;

  const SmartRecommendationSection({
    super.key,
    required this.title,
    this.emoji = '',
    required this.recommendations,
    this.onSeeAll,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) return const SizedBox.shrink();

    final accent = accentColor ?? AppTheme.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Vibrant section header ──────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.12),
                accent.withValues(alpha: 0.04),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              if (emoji.isNotEmpty) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent.computeLuminance() > 0.5
                        ? const Color(0xFF1F2937)
                        : accent,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recommendations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final rec = recommendations[index];
              return RepaintBoundary(
                child: _SmartRestaurantCard(
                  rec: rec,
                  onTap: () => onTap?.call(rec),
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

class _SmartRestaurantCard extends StatelessWidget {
  final SmartRecommendation rec;
  final VoidCallback? onTap;

  const _SmartRestaurantCard({required this.rec, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: rec.imageUrl != null && rec.imageUrl!.isNotEmpty
                  ? Image.network(
                      rec.imageUrl!,
                      height: 110,
                      width: 180,
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                      errorBuilder: (_, _, _) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.restaurantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        rec.rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (rec.cuisineType != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '·',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            rec.cuisineType!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Reason badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withValues(alpha: 0.15),
                          AppTheme.primaryColor.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      rec.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rec.estimatedDeliveryTime != null) ...[
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${rec.estimatedDeliveryTime} min',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${AppConstants.currencySymbol}${rec.deliveryFee.toStringAsFixed(0)} delivery',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
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

  static final _placeholderColors = [
    AppTheme.primaryColor.withValues(alpha: 0.15),
    AppTheme.primaryColor.withValues(alpha: 0.05),
  ];
  static final _placeholderIconColor = AppTheme.primaryColor.withValues(
    alpha: 0.4,
  );

  Widget _imagePlaceholder() => Container(
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

// ════════════════════════════════════════════════════════════════
// Smart Home Sections — Assembles all AI-powered sections
// ════════════════════════════════════════════════════════════════

class SmartHomeSections extends ConsumerWidget {
  final void Function(SmartRecommendation rec)? onRestaurantTap;

  const SmartHomeSections({super.key, this.onRestaurantTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brainAsync = ref.watch(brainEngineProvider);

    return brainAsync.when(
      data: (brain) {
        if (!brain.hasPersonalizedContent && brain.activeCoupon == null) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Made for You" — AI-driven
            SmartRecommendationSection(
              title: 'Made for You',
              emoji: '\u{1F9E0}',
              accentColor: const Color(0xFF6366F1),
              recommendations: brain.forYou,
              onTap: onRestaurantTap,
              onSeeAll: brain.forYou.isEmpty ? null : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SmartSectionViewAllScreen(
                    title: 'Made for You',
                    recommendations: brain.forYou,
                  ),
                ),
              ),
            ),

            // "Because you love [cuisine]" — behavior-based
            if (brain.becauseYouLove.isNotEmpty && brain.topCuisine != null)
              SmartRecommendationSection(
                title: 'Because you love ${brain.topCuisine}',
                emoji: '\u{1F355}',
                accentColor: const Color(0xFFE11D48),
                recommendations: brain.becauseYouLove,
                onTap: onRestaurantTap,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartSectionViewAllScreen(
                      title: 'Because you love ${brain.topCuisine}',
                      recommendations: brain.becauseYouLove,
                    ),
                  ),
                ),
              ),

            // "Deals you'll like" — for deal-sensitive users
            if (brain.dealsForYou.isNotEmpty)
              SmartRecommendationSection(
                title: 'Deals you\'ll like',
                emoji: '\u{1F381}',
                accentColor: const Color(0xFF10B981),
                recommendations: brain.dealsForYou,
                onTap: onRestaurantTap,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartSectionViewAllScreen(
                      title: 'Deals you\'ll like',
                      recommendations: brain.dealsForYou,
                    ),
                  ),
                ),
              ),

            // "Quick delivery" — for time-sensitive users
            if (brain.quickDelivery.isNotEmpty)
              SmartRecommendationSection(
                title: 'Quick delivery',
                emoji: '\u{26A1}',
                accentColor: const Color(0xFFF59E0B),
                recommendations: brain.quickDelivery,
                onTap: onRestaurantTap,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartSectionViewAllScreen(
                      title: 'Quick delivery',
                      recommendations: brain.quickDelivery,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const _SmartSectionsLoading(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _SmartSectionsLoading extends StatelessWidget {
  const _SmartSectionsLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 20,
            width: 160,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) => Container(
              width: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Grocery Smart Sections — AI-powered grocery recommendations
// ════════════════════════════════════════════════════════════════

class GrocerySmartSections extends ConsumerWidget {
  final void Function(SmartRecommendation rec)? onStoreTap;

  const GrocerySmartSections({super.key, this.onStoreTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brainAsync = ref.watch(groceryBrainEngineProvider);

    return brainAsync.when(
      data: (brain) {
        if (!brain.hasPersonalizedContent && brain.activeCoupon == null) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SmartRecommendationSection(
              title: 'Stores for You',
              emoji: '\u{1F6D2}',
              accentColor: const Color(0xFF6366F1),
              recommendations: brain.forYou,
              onTap: onStoreTap,
            ),

            if (brain.becauseYouLove.isNotEmpty)
              SmartRecommendationSection(
                title: 'Top Rated Stores',
                emoji: '\u{2B50}',
                accentColor: const Color(0xFFE11D48),
                recommendations: brain.becauseYouLove,
                onTap: onStoreTap,
              ),

            if (brain.dealsForYou.isNotEmpty)
              SmartRecommendationSection(
                title: 'Great Delivery Deals',
                emoji: '\u{1F4B0}',
                accentColor: const Color(0xFF10B981),
                recommendations: brain.dealsForYou,
                onTap: onStoreTap,
              ),

            if (brain.quickDelivery.isNotEmpty)
              SmartRecommendationSection(
                title: 'Quick Delivery',
                emoji: '\u{26A1}',
                accentColor: const Color(0xFFF59E0B),
                recommendations: brain.quickDelivery,
                onTap: onStoreTap,
              ),
          ],
        );
      },
      loading: () => const _SmartSectionsLoading(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Apology Coupon Banner — overrides every other home offer when
// the user just had a bad experience (low review or cancellation).
// ════════════════════════════════════════════════════════════════

class _ApologyCouponBanner extends ConsumerWidget {
  const _ApologyCouponBanner({required this.coupon});

  final SmartCoupon coupon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: coupon.code));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code ${coupon.code} copied — apply at checkout'),
            backgroundColor: const Color(0xFFB91C1C),
            duration: const Duration(seconds: 3),
          ),
        );
        showCouponPopup(context, coupon, 'apology');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB91C1C).withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "We're sorry — here's a gift",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${coupon.discountPercent}% OFF your next order — code ${coupon.code}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SmartSectionViewAllScreen — full vertical list for a smart section
// ════════════════════════════════════════════════════════════════

class SmartSectionViewAllScreen extends ConsumerStatefulWidget {
  final String title;
  final List<SmartRecommendation> recommendations;

  const SmartSectionViewAllScreen({
    super.key,
    required this.title,
    required this.recommendations,
  });

  @override
  ConsumerState<SmartSectionViewAllScreen> createState() =>
      _SmartSectionViewAllScreenState();
}

class _SmartSectionViewAllScreenState
    extends ConsumerState<SmartSectionViewAllScreen> {
  List<Restaurant>? _restaurants;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(restaurantServiceProvider);
    final results = await Future.wait(
      widget.recommendations.map((r) => service.getRestaurantById(r.restaurantId)),
    );
    if (mounted) {
      setState(() {
        _restaurants = results.whereType<Restaurant>().toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: _restaurants == null
          ? const Center(child: CircularProgressIndicator())
          : _restaurants!.isEmpty
              ? const Center(child: Text('Nothing to show right now.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: _restaurants!.length,
                  itemBuilder: (context, i) {
                    final r = _restaurants![i];
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
