import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:food_driver/modules/car_services/models/car_service_offering.dart';
import 'package:food_driver/modules/car_services/models/car_service_provider.dart';
import 'package:food_driver/modules/car_services/models/car_service_provider_image.dart';
import 'package:food_driver/modules/car_services/models/car_service_review.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:intl/intl.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kAmber = Color(0xFFF59E0B);

class CarServiceProviderDetailScreen extends ConsumerStatefulWidget {
  const CarServiceProviderDetailScreen({super.key});

  @override
  ConsumerState<CarServiceProviderDetailScreen> createState() =>
      _CarServiceProviderDetailScreenState();
}

class _CarServiceProviderDetailScreenState
    extends ConsumerState<CarServiceProviderDetailScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  bool _isFav = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _share(CarServiceProvider provider) {
    final rating  = provider.rating.toStringAsFixed(1);
    final address = provider.baseLocationAddress ?? '';
    final msg = StringBuffer()
      ..writeln('🚗 ${provider.businessName}')
      ..writeln('⭐ $rating stars');
    if (address.isNotEmpty) msg.writeln('📍 $address');
    msg.write('\nBook car services on 7Dash 👉 https://sevendash.app');
    Share.share(msg.toString(), subject: provider.businessName);
  }

  void _toggleFav(CarServiceProvider provider) {
    setState(() => _isFav = !_isFav);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_isFav
          ? '❤️ ${provider.businessName} added to favourites'
          : '${provider.businessName} removed from favourites'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider =
        ModalRoute.of(context)!.settings.arguments as CarServiceProvider;
    final offeringsAsync = ref.watch(carServiceOfferingsProvider(provider.id));
    final reviewsAsync = ref.watch(carServiceProviderReviewsProvider(provider.id));

    // Build image list: use provider images if available, else fall back to profileImageUrl
    final images = provider.images ?? [];
    final imageCount = images.isNotEmpty ? images.length : 1;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── Image carousel app bar ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: _kBlueDark,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Carousel
                  _buildCarousel(provider, images),
                  // Gradient scrim at bottom
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.5, 1.0],
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  // Dots indicator
                  if (imageCount > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(imageCount, (i) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _currentPage ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _currentPage
                                  ? Colors.white
                                  : Colors.white.withAlpha(100),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _share(provider),
              ),
              IconButton(
                icon: Icon(
                  _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: _isFav ? Colors.red : null,
                ),
                onPressed: () => _toggleFav(provider),
              ),
            ],
          ),

          // ── Provider info ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    provider.businessName,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (provider.isVerified) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _kBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified_rounded,
                                            size: 13, color: _kBlue),
                                        SizedBox(width: 3),
                                        Text(
                                          'Verified',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: _kBlue,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _StarRow(rating: provider.rating),
                                const SizedBox(width: 6),
                                Text(
                                  provider.rating.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  ' (${provider.totalReviews} reviews)',
                                  style: TextStyle(
                                    fontSize: 13,
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

                  const SizedBox(height: 14),

                  // Stats row
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _InfoChip(
                        icon: Icons.work_outline_rounded,
                        label: '${provider.totalBookings} jobs',
                      ),
                      _InfoChip(
                        icon: Icons.location_on_outlined,
                        label: '${provider.serviceAreaRadiusKm.toInt()} km radius',
                      ),
                      _InfoChip(
                        icon: Icons.access_time_rounded,
                        label: 'Today open',
                      ),
                    ],
                  ),

                  if (provider.bio != null && provider.bio!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      provider.bio!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Services section ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Services',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),

          offeringsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: _kBlue)),
              ),
            ),
            error: (e, _) {
              AppLogger.error('ProviderDetail: offerings error', e);
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            },
            data: (offerings) {
              if (offerings.isEmpty) {
                return SliverToBoxAdapter(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No services listed yet.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _OfferingTile(
                    offering: offerings[i],
                    allOfferings: offerings,
                    provider: provider,
                    isLast: i == offerings.length - 1,
                  ),
                  childCount: offerings.length,
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Reviews section ────────────────────────────────────────────────────
          reviewsAsync.when(
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (reviews) {
              if (reviews.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverToBoxAdapter(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Reviews',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${reviews.length} reviews',
                            style: TextStyle(
                                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...reviews.take(3).map((r) => _ReviewTile(review: r)),
                    ],
                  ),
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildCarousel(
      CarServiceProvider provider, List<CarServiceProviderImage> images) {
    if (images.isEmpty) {
      return _GradientPlaceholder(initial: provider.businessName[0]);
    }

    final sorted = [...images]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return PageView.builder(
      controller: _pageCtrl,
      itemCount: sorted.length,
      onPageChanged: (i) => setState(() => _currentPage = i),
      itemBuilder: (_, i) => Image.network(
        sorted[i].imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _GradientPlaceholder(initial: provider.businessName[0]),
      ),
    );
  }
}

// ── Gradient placeholder ───────────────────────────────────────────────────────

class _GradientPlaceholder extends StatelessWidget {
  final String initial;
  const _GradientPlaceholder({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlueDark, _kBlue],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_car_wash, size: 56, color: Colors.white30),
            const SizedBox(height: 8),
            Text(
              initial.toUpperCase(),
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info chip ──────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: _kBlue, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Offering tile ──────────────────────────────────────────────────────────────

class _OfferingTile extends StatelessWidget {
  final CarServiceOffering offering;
  final List<CarServiceOffering> allOfferings;
  final CarServiceProvider provider;
  final bool isLast;

  const _OfferingTile({
    required this.offering,
    required this.allOfferings,
    required this.provider,
    required this.isLast,
  });

  String get _duration {
    final hrs = offering.durationMinutes ~/ 60;
    final mins = offering.durationMinutes % 60;
    if (hrs > 0 && mins > 0) return '${hrs}h ${mins}m';
    if (hrs > 0) return '${hrs}h';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_car_wash_rounded,
                    color: _kBlue, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offering.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (offering.description != null &&
                        offering.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        offering.description!,
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined,
                            size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          _duration,
                          style: TextStyle(
                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'From \$${offering.basePrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _kBlue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/car-services/book',
                        arguments: {
                          'provider': provider,
                          'offerings': allOfferings,
                        },
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Book',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!isLast)
            Divider(height: 24, color: Theme.of(context).colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

// ── Review tile ────────────────────────────────────────────────────────────────

class _ReviewTile extends StatelessWidget {
  final CarServiceReview review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StarRow(rating: review.rating.toDouble()),
              const Spacer(),
              Text(
                DateFormat('MMM d, y').format(review.createdAt),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.comment!,
              style: TextStyle(
                  fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Star row ───────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final double rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < rating.floor()) {
          return const Icon(Icons.star_rounded, size: 14, color: _kAmber);
        } else if (i < rating) {
          return const Icon(Icons.star_half_rounded, size: 14, color: _kAmber);
        }
        return Icon(Icons.star_outline_rounded,
            size: 14, color: _kAmber.withAlpha(100));
      }),
    );
  }
}
