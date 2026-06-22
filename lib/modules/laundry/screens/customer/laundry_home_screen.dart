import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../config/app_constants.dart';

const _kNavy = Color(0xFF0B3D6B);
const _kBlue = Color(0xFF1565C0);

// Service category filters
const _kCategories = [
  _Cat('All',            Icons.apps_rounded),
  _Cat('Wash & Fold',    Icons.local_laundry_service_rounded),
  _Cat('Dry Cleaning',   Icons.dry_cleaning_rounded),
  _Cat('Ironing',        Icons.iron_rounded),
  _Cat('Express',        Icons.bolt_rounded),
  _Cat('Bedding',        Icons.bed_rounded),
];

class _Cat {
  final String label;
  final IconData icon;
  const _Cat(this.label, this.icon);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class LaundryHomeScreen extends ConsumerStatefulWidget {
  const LaundryHomeScreen({super.key});

  @override
  ConsumerState<LaundryHomeScreen> createState() => _LaundryHomeScreenState();
}

class _LaundryHomeScreenState extends ConsumerState<LaundryHomeScreen> {
  final _searchCtrl  = TextEditingController();
  final _scrollCtrl  = ScrollController();
  String _query      = '';
  int    _catIndex   = 0;
  bool   _searchMode = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = _query.isEmpty
        ? ref.watch(laundryProvidersProvider)
        : ref.watch(laundryProviderSearchProvider(_query));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: NestedScrollView(
        controller: _scrollCtrl,
        headerSliverBuilder: (ctx, innerScrolled) => [
          _buildAppBar(context),
        ],
        body: providersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _EmptyState(query: _query),
          data: (all) {
            final providers = _filterByCategory(all);
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(laundryProvidersProvider),
              color: _kBlue,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // ── Promo banner ──────────────────────────────────────────
                  const SliverToBoxAdapter(child: _PromoBanner()),

                  // ── Category chips ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _CategoryBar(
                      selected: _catIndex,
                      onSelect: (i) => setState(() => _catIndex = i),
                    ),
                  ),

                  // ── Section header ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                      child: Row(
                        children: [
                          Text(
                            providers.isEmpty
                                ? 'Providers'
                                : '${providers.length} Provider${providers.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── List / Empty ──────────────────────────────────────────
                  providers.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(query: _query),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _ProviderCard(
                                provider: providers[i],
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  '/laundry/provider-detail',
                                  arguments: providers[i],
                                ),
                              ),
                              childCount: providers.length,
                            ),
                          ),
                        ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<LaundryProvider> _filterByCategory(List<LaundryProvider> all) {
    if (_catIndex == 0) return all;
    final cat = _kCategories[_catIndex].label.toLowerCase();
    return all.where((p) =>
      p.services?.any((s) =>
        (s.serviceName ?? '').toLowerCase().contains(cat)) ?? false,
    ).toList();
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      stretch: true,
      backgroundColor: _kNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchMode
                ? const Icon(Icons.close_rounded, key: ValueKey('close'))
                : const Icon(Icons.search_rounded, key: ValueKey('search')),
          ),
          onPressed: () {
            setState(() {
              _searchMode = !_searchMode;
              if (!_searchMode) {
                _searchCtrl.clear();
                _query = '';
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.history_rounded),
          onPressed: () => Navigator.pushNamed(context, '/laundry/history'),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kNavy, _kBlue],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_laundry_service_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Laundry Services',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Pickup • Clean • Deliver',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Search bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: _searchMode ? 42 : 0,
                    child: _searchMode
                        ? TextField(
                            controller: _searchCtrl,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (v) =>
                                setState(() => _query = v.trim()),
                            decoration: InputDecoration(
                              hintText: 'Search laundromats…',
                              hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6)),
                              prefixIcon: Icon(Icons.search,
                                  color:
                                      Colors.white.withValues(alpha: 0.7)),
                              filled: true,
                              fillColor:
                                  Colors.white.withValues(alpha: 0.15),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Promo Banner
// ─────────────────────────────────────────────────────────────────────────────

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              right: 30, bottom: -30,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Large icon
            Positioned(
              right: 24,
              top: 0, bottom: 0,
              child: Center(
                child: Icon(
                  Icons.local_laundry_service_rounded,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ),
            // Text
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'HASSLE-FREE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Fresh laundry,\ndelivered to your door',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
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

// ─────────────────────────────────────────────────────────────────────────────
// Category Chips
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _CategoryBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: _kCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final cat      = _kCategories[i];
          final isActive = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? _kBlue
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive
                      ? _kBlue
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 15,
                    color: isActive
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderCard extends ConsumerStatefulWidget {
  final LaundryProvider provider;
  final VoidCallback onTap;

  const _ProviderCard({required this.provider, required this.onTap});

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  bool _isFav = false;
  bool _favLoading = false;

  static final _db = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadFav();
  }

  Future<void> _loadFav() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final row = await _db
        .from('user_favorite_laundry_providers')
        .select('id')
        .eq('user_id', uid)
        .eq('provider_id', widget.provider.id)
        .maybeSingle();
    if (mounted) setState(() => _isFav = row != null);
  }

  Future<void> _toggleFav() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || _favLoading) return;
    setState(() => _favLoading = true);
    try {
      if (_isFav) {
        await _db
            .from('user_favorite_laundry_providers')
            .delete()
            .eq('user_id', uid)
            .eq('provider_id', widget.provider.id);
      } else {
        await _db.from('user_favorite_laundry_providers').upsert({
          'user_id':     uid,
          'provider_id': widget.provider.id,
        }, onConflict: 'user_id,provider_id');
      }
      if (mounted) setState(() => _isFav = !_isFav);
    } catch (_) {
      // silently fail — icon snaps back
    } finally {
      if (mounted) setState(() => _favLoading = false);
    }
  }

  void _share() {
    final p       = widget.provider;
    final rating  = p.rating > 0 ? '⭐ ${p.rating.toStringAsFixed(1)}' : '';
    final address = p.address ?? '';
    final msg = StringBuffer()
      ..writeln('👕 ${p.businessName}');
    if (rating.isNotEmpty)  msg.writeln(rating);
    if (address.isNotEmpty) msg.writeln('📍 $address');
    msg.write('\nBook laundry pickup on 7Dash 👉 https://sevendash.app');
    SharePlus.instance.share(ShareParams(text: msg.toString(), subject: p.businessName));
  }

  LaundryProvider get provider => widget.provider;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner / Hero image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                children: [
                  // Image or gradient placeholder
                  provider.bannerUrl != null
                      ? Image.network(
                          provider.bannerUrl!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _bannerPlaceholder(),
                        )
                      : _bannerPlaceholder(),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Open / Closed badge
                  Positioned(
                    top: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: provider.isActive
                            ? AppTheme.successColor
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: provider.isActive
                                  ? Colors.white
                                  : Colors.white60,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            provider.isActive ? 'Open' : 'Closed',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Rating badge
                  if (provider.rating > 0)
                    Positioned(
                      top: 12, right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              provider.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Info section
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: provider.logoUrl != null
                            ? Image.network(
                                provider.logoUrl!,
                                width: 40, height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _logoFallback(),
                              )
                            : _logoFallback(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.businessName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (provider.address != null)
                              Text(
                                provider.address!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Share button
                      GestureDetector(
                        onTap: _share,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _kBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.share_rounded,
                              color: _kBlue, size: 17),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Favourite button
                      GestureDetector(
                        onTap: _favLoading ? null : _toggleFav,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _isFav
                                ? Colors.red.withValues(alpha: 0.1)
                                : _kBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _favLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _kBlue),
                                )
                              : Icon(
                                  _isFav
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: _isFav ? Colors.red : _kBlue,
                                  size: 17,
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Book button
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Book',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Services chips
                  if (provider.services != null &&
                      provider.services!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 26,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: provider.services!
                            .where((s) => s.isAvailable)
                            .take(5)
                            .length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final svc = provider.services!
                              .where((s) => s.isAvailable)
                              .toList()[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              svc.serviceName ?? '',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _kBlue,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // Fees row
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _InfoPill(
                        Icons.local_shipping_rounded,
                        provider.pricing?.deliveryFee == 0
                            ? 'Free delivery'
                            : '${AppConstants.currencySymbol}${provider.pricing?.deliveryFee.toStringAsFixed(2) ?? '-'} delivery',
                      ),
                      if (provider.reviewCount > 0) ...[
                        const SizedBox(width: 8),
                        _InfoPill(
                          Icons.reviews_rounded,
                          '${provider.reviewCount} review${provider.reviewCount == 1 ? '' : 's'}',
                        ),
                      ],
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

  Widget _bannerPlaceholder() => Container(
        height: 140,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kNavy, _kBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.local_laundry_service_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      );

  Widget _logoFallback() => Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _kBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.local_laundry_service_rounded,
            color: _kBlue, size: 20),
      );
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kNavy, _kBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _kBlue.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_laundry_service_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              query.isNotEmpty ? 'No results for "$query"' : 'Coming soon!',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              query.isNotEmpty
                  ? 'Try searching with a different term.'
                  : 'Laundry providers are being onboarded.\nCheck back soon!',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, '/laundry/history'),
              icon: const Icon(Icons.history_rounded),
              label: const Text('My Orders'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBlue,
                side: const BorderSide(color: _kBlue),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
