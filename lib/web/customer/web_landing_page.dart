import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

class WebLandingPage extends ConsumerWidget {
  final VoidCallback onBrowseFood;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final void Function(Restaurant) onRestaurantTapped;

  const WebLandingPage({
    super.key,
    required this.onBrowseFood,
    required this.onSignIn,
    required this.onSignUp,
    required this.onRestaurantTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(topRatedRestaurantsProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroSection(onBrowseFood: onBrowseFood, onSignUp: onSignUp),
          _PortalCardsSection(onOrderFood: onBrowseFood, onSignIn: onSignIn),
          _FeaturedSection(topAsync: topAsync, onRestaurantTapped: onRestaurantTapped),
          const _HowItWorksSection(),
          const _StatsBanner(),
          const _FooterSection(),
        ],
      ),
    );
  }
}

// ── HERO ──────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final VoidCallback onBrowseFood;
  final VoidCallback onSignUp;
  const _HeroSection({required this.onBrowseFood, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 500),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF0F2D47)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -60, top: -60, child: _Bubble(260, Colors.white, 0.025)),
          Positioned(right: 180, bottom: -80, child: _Bubble(180, Color(0xFFFF6B35), 0.07)),
          Positioned(left: -40, bottom: 30, child: _Bubble(130, Colors.white, 0.03)),
          Padding(
            padding: const EdgeInsets.fromLTRB(80, 64, 80, 64),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 55, child: _HeroLeft(onBrowseFood: onBrowseFood, onSignUp: onSignUp)),
                const SizedBox(width: 60),
                const Expanded(flex: 45, child: _HeroVisual()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Bubble(this.size, this.color, this.opacity);
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: opacity)),
  );
}

class _HeroLeft extends StatelessWidget {
  final VoidCallback onBrowseFood;
  final VoidCallback onSignUp;
  const _HeroLeft({required this.onBrowseFood, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt, size: 13, color: Color(0xFFFF6B35)),
            SizedBox(width: 5),
            Text('Fast Delivery · Cayman Islands', style: TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 22),
        const Text(
          'Food, Groceries\n& More — Delivered.',
          style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1.5),
        ),
        const SizedBox(height: 16),
        const Text(
          'Browse hundreds of restaurants, track your order live,\nand enjoy fast doorstep delivery.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 32),
        Row(children: [
          ElevatedButton.icon(
            onPressed: onBrowseFood,
            icon: const Icon(Icons.restaurant_rounded, size: 18),
            label: const Text('Browse Restaurants', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onSignUp,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
        const SizedBox(height: 28),
        Wrap(spacing: 20, runSpacing: 8, children: const [
          _TrustBadge(Icons.star_rounded, '4.8★ Avg Rating'),
          _TrustBadge(Icons.storefront_rounded, '200+ Restaurants'),
          _TrustBadge(Icons.timer_rounded, '30 min avg delivery'),
        ]),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: Colors.white30),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
  ]);
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  static const _foods = [
    (emoji: '🍔', color: Color(0xFFFF6B35), dx: -90.0, dy: -50.0),
    (emoji: '🍕', color: Color(0xFF10B981), dx: 90.0, dy: -80.0),
    (emoji: '🍜', color: Color(0xFF6366F1), dx: -110.0, dy: 50.0),
    (emoji: '🍗', color: Color(0xFFF59E0B), dx: 100.0, dy: 60.0),
    (emoji: '🥗', color: Color(0xFF14B8A6), dx: 5.0, dy: 130.0),
    (emoji: '🍰', color: Color(0xFFEC4899), dx: -30.0, dy: -140.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 360,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 150, height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.fastfood_rounded, color: Color(0xFFFF6B35), size: 48),
                SizedBox(height: 10),
                Text('7DASH', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
                SizedBox(height: 2),
                Text('Order. Track. Enjoy.', style: TextStyle(color: Colors.white30, fontSize: 10)),
              ]),
            ),
            for (final f in _foods)
              Transform.translate(
                offset: Offset(f.dx, f.dy),
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    color: f.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: f.color.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Center(child: Text(f.emoji, style: const TextStyle(fontSize: 26))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── PORTAL CARDS ──────────────────────────────────────────────────────────────

class _PortalCardsSection extends StatelessWidget {
  final VoidCallback onOrderFood;
  final VoidCallback onSignIn;
  const _PortalCardsSection({required this.onOrderFood, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(80, 72, 80, 72),
      child: Column(children: [
        const Text('One Platform. Every Role.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
        const SizedBox(height: 10),
        const Text(
          'Whether you\'re hungry, a restaurant owner, a driver, or managing the platform —\n7DASH has a dedicated portal for you.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Color(0xFF64748B), height: 1.6),
        ),
        const SizedBox(height: 52),
        Row(children: [
          Expanded(child: _PortalCard(
            gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
            icon: Icons.shopping_bag_rounded,
            badge: 'For Customers',
            title: 'Order Food',
            subtitle: 'Browse restaurants, build your cart, track your delivery in real-time.',
            features: const ['200+ Restaurants', 'Real-time tracking', 'Loyalty rewards'],
            ctaLabel: 'Order Now',
            ctaIcon: Icons.arrow_forward_rounded,
            onTap: onOrderFood,
          )),
          const SizedBox(width: 20),
          Expanded(child: _PortalCard(
            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
            icon: Icons.storefront_rounded,
            badge: 'For Restaurants',
            title: 'Restaurant Portal',
            subtitle: 'Manage orders, update your menu, view analytics, and grow your business.',
            features: const ['Order management', 'Menu builder', 'Sales analytics'],
            ctaLabel: 'Log In as Restaurant',
            ctaIcon: Icons.login_rounded,
            onTap: onSignIn,
          )),
          const SizedBox(width: 20),
          Expanded(child: _PortalCard(
            gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
            icon: Icons.delivery_dining_rounded,
            badge: 'For Drivers',
            title: 'Driver Portal',
            subtitle: 'Accept deliveries, track your earnings, and manage your availability.',
            features: const ['Available orders', 'Earnings dashboard', 'Performance stats'],
            ctaLabel: 'Start Driving',
            ctaIcon: Icons.login_rounded,
            onTap: onSignIn,
          )),
          const SizedBox(width: 20),
          Expanded(child: _PortalCard(
            gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
            icon: Icons.admin_panel_settings_rounded,
            badge: 'For Admins',
            title: 'Admin Panel',
            subtitle: 'Manage users, restaurants, drivers, orders, and platform settings.',
            features: const ['Full analytics', 'User management', 'Platform controls'],
            ctaLabel: 'Admin Login',
            ctaIcon: Icons.login_rounded,
            onTap: onSignIn,
          )),
        ]),
      ]),
    );
  }
}

class _PortalCard extends StatefulWidget {
  final LinearGradient gradient;
  final IconData icon;
  final String badge;
  final String title;
  final String subtitle;
  final List<String> features;
  final String ctaLabel;
  final IconData ctaIcon;
  final VoidCallback onTap;

  const _PortalCard({
    required this.gradient,
    required this.icon,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.onTap,
  });

  @override
  State<_PortalCard> createState() => _PortalCardState();
}

class _PortalCardState extends State<_PortalCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.12 : 0.05),
                blurRadius: _hover ? 28 : 10,
                offset: Offset(0, _hover ? 10 : 4),
              ),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Icon + badge
            Row(children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(gradient: widget.gradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(widget.icon, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.gradient.colors.first.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: widget.gradient.colors.first)),
              ),
            ]),
            const SizedBox(height: 16),
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
            const SizedBox(height: 8),
            Text(widget.subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5)),
            const SizedBox(height: 16),
            // Feature list
            ...widget.features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: widget.gradient.colors.first, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(f, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
              ]),
            )),
            const SizedBox(height: 20),
            // CTA row
            Row(children: [
              Text(widget.ctaLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: widget.gradient.colors.first)),
              const SizedBox(width: 4),
              Icon(widget.ctaIcon, size: 14, color: widget.gradient.colors.first),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── FEATURED RESTAURANTS ──────────────────────────────────────────────────────

class _FeaturedSection extends StatelessWidget {
  final AsyncValue<List<Restaurant>> topAsync;
  final void Function(Restaurant) onRestaurantTapped;
  const _FeaturedSection({required this.topAsync, required this.onRestaurantTapped});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(80, 64, 80, 64),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🔥 Popular Right Now', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
            SizedBox(height: 4),
            Text('Top-rated restaurants ordered by customers like you', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          ])),
        ]),
        const SizedBox(height: 28),
        topAsync.when(
          loading: () => const SizedBox(height: 170, child: AppLoadingIndicator()),
          error: (e, _) => SizedBox(height: 80, child: AppErrorState(message: friendlyError(e))),
          data: (list) => SizedBox(
            height: 210,
            child: list.isEmpty
                ? const Center(child: Text('No restaurants available', style: TextStyle(color: Color(0xFF94A3B8))))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length > 10 ? 10 : list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) => _RestCard(restaurant: list[i], onTap: onRestaurantTapped),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _RestCard extends StatefulWidget {
  final Restaurant restaurant;
  final void Function(Restaurant) onTap;
  const _RestCard({required this.restaurant, required this.onTap});
  @override
  State<_RestCard> createState() => _RestCardState();
}

class _RestCardState extends State<_RestCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onTap(r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hover ? 0.10 : 0.05), blurRadius: _hover ? 16 : 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 116,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                image: r.imageUrl != null ? DecorationImage(image: NetworkImage(r.imageUrl!), fit: BoxFit.cover) : null,
              ),
              child: r.imageUrl == null
                  ? const Center(child: Icon(Icons.storefront_rounded, size: 40, color: Color(0xFFFF6B35)))
                  : Stack(children: [
                      if (!r.isOpen)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                          ),
                          child: const Center(child: Text('Closed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                        ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 3),
                  Text(r.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 3),
                  Text('${r.estimatedDeliveryTime ?? 30} min', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                ]),
                if (r.deliveryFee != null) ...[
                  const SizedBox(height: 2),
                  Text('${AppConstants.currencySymbol}${r.deliveryFee!.toStringAsFixed(2)} delivery', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── HOW IT WORKS ──────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(80, 64, 80, 64),
      child: Column(children: [
        const Text('How It Works', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
        const SizedBox(height: 8),
        const Text('Get your favourite food in three easy steps', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
        const SizedBox(height: 52),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Step('01', Icons.search_rounded, 'Browse & Choose', 'Search restaurants, explore menus, and add items to your cart with a tap.')),
            _Connector(),
            Expanded(child: _Step('02', Icons.credit_card_rounded, 'Place Your Order', 'Checkout securely with your wallet, card, or cash on delivery.')),
            _Connector(),
            Expanded(child: _Step('03', Icons.delivery_dining_rounded, 'Track & Enjoy', 'Follow your driver in real-time on the map and enjoy your meal.')),
          ],
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final IconData icon;
  final String title;
  final String desc;
  const _Step(this.num, this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Stack(alignment: Alignment.topRight, children: [
        Container(
          width: 76, height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFFFF6B35), size: 34),
        ),
        Container(
          width: 24, height: 24,
          decoration: const BoxDecoration(color: Color(0xFFFF6B35), shape: BoxShape.circle),
          child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))),
        ),
      ]),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
      const SizedBox(height: 8),
      Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5)),
    ]);
  }
}

class _Connector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 56),
      child: SizedBox(
        width: 48,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(height: 2, color: const Color(0xFFE2E8F0),
              margin: const EdgeInsets.symmetric(horizontal: 4)),
        ]),
      ),
    );
  }
}

// ── STATS BANNER ──────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  const _StatsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 52),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat('200+', 'Restaurants'),
          _StatDivider(),
          _Stat('1,000+', 'Active Drivers'),
          _StatDivider(),
          _Stat('50K+', 'Orders Delivered'),
          _StatDivider(),
          _Stat('4.8 ★', 'Average Rating'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
  ]);
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 56, color: Colors.white24);
}

// ── FOOTER ────────────────────────────────────────────────────────────────────

class _FooterSection extends StatelessWidget {
  const _FooterSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1B2A),
      padding: const EdgeInsets.fromLTRB(80, 52, 80, 36),
      child: Column(children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('7DASH', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ]),
              const SizedBox(height: 14),
              const Text('Fast, reliable food delivery\nacross the Cayman Islands.', style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.7)),
            ])),
            const SizedBox(width: 40),
            Expanded(child: _FooterCol('For Customers', ['Browse Restaurants', 'My Orders', 'Loyalty Rewards', 'Track Delivery'])),
            const SizedBox(width: 24),
            Expanded(child: _FooterCol('For Partners', ['Restaurant Portal', 'Driver Sign Up', 'Partner Benefits', 'Contact Sales'])),
            const SizedBox(width: 24),
            Expanded(child: _FooterCol('Company', ['About 7DASH', 'Privacy Policy', 'Terms of Service', 'Support'])),
          ],
        ),
        const SizedBox(height: 44),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 20),
        const Text('© 2026 7DASH · All rights reserved · Cayman Islands',
            style: TextStyle(color: Colors.white24, fontSize: 12)),
      ]),
    );
  }
}

class _FooterCol extends StatelessWidget {
  final String title;
  final List<String> links;
  const _FooterCol(this.title, this.links);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        ...links.map((l) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        )),
      ],
    );
  }
}
