import 'package:flutter/material.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _navy = Color(0xFF0F172A);
const _navyLight = Color(0xFF1E293B);
const _gold = Color(0xFFF59E0B);
const _goldLight = Color(0xFFFCD34D);
const _slate = Color(0xFF64748B);
const _bg = Color(0xFFFFFFFF);

class RestaurantLandingPage extends StatefulWidget {
  const RestaurantLandingPage({super.key});

  @override
  State<RestaurantLandingPage> createState() => _RestaurantLandingPageState();
}

class _RestaurantLandingPageState extends State<RestaurantLandingPage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 10;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goSignIn() => Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
  void _goSignUp() => Navigator.of(context).pushNamed('/onboarding/restaurant');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            child: Column(
              children: [
                const SizedBox(height: 72), // navbar clearance
                _HeroSection(onLogin: _goSignIn, onSignUp: _goSignUp),
                _StatsBar(),
                _HowItWorks(),
                _FeaturesSection(),
                _PricingSection(onSignUp: _goSignUp),
                _TestimonialsSection(),
                _CtaSection(onSignUp: _goSignUp),
                _Footer(),
              ],
            ),
          ),
          // Fixed navbar
          Positioned(
            top: 0, left: 0, right: 0,
            child: _Navbar(scrolled: _scrolled, onLogin: _goSignIn, onSignUp: _goSignUp),
          ),
        ],
      ),
    );
  }
}

// ─── Navbar ───────────────────────────────────────────────────────────────────

class _Navbar extends StatelessWidget {
  final bool scrolled;
  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  const _Navbar({required this.scrolled, required this.onLogin, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 72,
      decoration: BoxDecoration(
        color: scrolled ? _navy.withValues(alpha: 0.97) : Colors.transparent,
        boxShadow: scrolled ? [const BoxShadow(color: Colors.black26, blurRadius: 12)] : [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          children: [
            // Logo
            Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_gold, _goldLight]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: _navy, size: 20),
                ),
                const SizedBox(width: 10),
                Text('MealHub', style: TextStyle(
                  color: scrolled ? Colors.white : _navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.5,
                )),
              ],
            ),
            const Spacer(),
            // Nav links (hidden on small width)
            if (MediaQuery.of(context).size.width > 900) ...[
              for (final link in ['Why MealHub', 'How It Works', 'Pricing', 'Support'])
                Padding(
                  padding: const EdgeInsets.only(right: 28),
                  child: Text(link, style: TextStyle(
                    color: scrolled ? Colors.white70 : _slate,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  )),
                ),
            ],
            OutlinedButton(
              onPressed: onLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: scrolled ? Colors.white : _navy,
                side: BorderSide(color: scrolled ? Colors.white38 : const Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Log In', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: onSignUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _navy,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Get Onboarded', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  const _HeroSection({required this.onLogin, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 580),
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left copy ──────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded, color: _gold, size: 14),
                      SizedBox(width: 6),
                      Text('0% Commission for Your First 30 Days', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('More Orders.', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _navy, height: 1.1)),
                const Text('Lower Commissions.', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _navy, height: 1.1)),
                const Text('Grow Your Restaurant.', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _gold, height: 1.1)),
                const SizedBox(height: 20),
                const Text(
                  'Join MealHub and keep more of your hard-earned revenue\nwhile we help you reach more local customers.',
                  style: TextStyle(fontSize: 16, color: _slate, height: 1.6),
                ),
                const SizedBox(height: 28),
                // Feature pills
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: const [
                    _FeaturePill(icon: Icons.percent_rounded, label: 'Lower Commissions', sub: 'Keep More Profit'),
                    _FeaturePill(icon: Icons.storefront_rounded, label: 'More Local Customers', sub: 'Grow Your Business'),
                    _FeaturePill(icon: Icons.bolt_rounded, label: 'Fast Payouts', sub: 'Get Paid Quickly'),
                    _FeaturePill(icon: Icons.headset_mic_rounded, label: 'Dedicated Support', sub: "We're Here to Help"),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onSignUp,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('Get Onboarded Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _navy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: _navy),
                      label: const Text('Learn More', style: TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 14, color: _slate),
                    const SizedBox(width: 6),
                    Text(
                      'No Setup Fee  ·  No Long-Term Contracts  ·  0% Commission for 30 Days',
                      style: TextStyle(fontSize: 12, color: _slate.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
          // ── Right visual ───────────────────────────────────────────
          Expanded(
            flex: 4,
            child: SizedBox(
              height: 480,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Main image card
                  Container(
                    width: double.infinity,
                    height: 420,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background pattern
                        Opacity(
                          opacity: 0.06,
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 4, crossAxisSpacing: 4),
                            itemCount: 48,
                            itemBuilder: (_, __) => Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        // Central icon
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 2),
                              ),
                              child: const Icon(Icons.restaurant_rounded, color: _gold, size: 48),
                            ),
                            const SizedBox(height: 16),
                            const Text('Your Restaurant', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                            const Text('on MealHub', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Promo floating card
                  Positioned(
                    top: -10,
                    right: -16,
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _navy,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.rocket_launch_rounded, color: _gold, size: 14),
                              const SizedBox(width: 5),
                              Text('Limited Time Offer', style: TextStyle(color: _gold.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('0%', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, height: 1)),
                          const Text('Commission\nfor the First', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 11)),
                          const Text('30 Days!', style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  // Testimonial card
                  Positioned(
                    bottom: 20,
                    left: -20,
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            for (int i = 0; i < 5; i++)
                              const Icon(Icons.star_rounded, color: _gold, size: 14),
                          ]),
                          const SizedBox(height: 6),
                          const Text('"MealHub helped us reduce fees and increase our online orders. It\'s a win-win!"', style: TextStyle(fontSize: 11, color: _navyLight, fontStyle: FontStyle.italic, height: 1.4)),
                          const SizedBox(height: 6),
                          const Text('– Michael T., Restaurant Owner', style: TextStyle(fontSize: 10, color: _slate, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  const _FeaturePill({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: _gold.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: _gold, size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
            Text(sub, style: const TextStyle(fontSize: 11, color: _slate)),
          ],
        ),
      ],
    );
  }
}

// ─── Stats Bar ────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _navy,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trusted by Restaurants', style: TextStyle(color: Colors.white70, fontSize: 14)),
                RichText(text: const TextSpan(
                  text: 'Across the ',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  children: [TextSpan(text: 'USA', style: TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 16))],
                )),
              ],
            ),
          ),
          for (final stat in [
            (Icons.storefront_rounded, '500+', 'Restaurants'),
            (Icons.people_rounded, '250K+', 'Happy Customers'),
            (Icons.receipt_long_rounded, '1M+', 'Orders Delivered'),
            (Icons.star_rounded, '4.8★', 'Average Rating'),
          ])
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Icon(stat.$1, color: _gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                      Text(stat.$3, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── How It Works ─────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 64),
      child: Column(
        children: [
          const Text('How MealHub Works for Your Restaurant', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 6),
          Container(width: 48, height: 3, decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 48),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      Expanded(
                        child: _StepCard(
                          number: '${i + 1}',
                          icon: _steps[i].$1,
                          title: _steps[i].$2,
                          desc: _steps[i].$3,
                        ),
                      ),
                      if (i < _steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.grey.shade300, size: 24),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // CTA card
              Container(
                width: 220,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _gold.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ready to Grow\nYour Restaurant?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy, height: 1.3)),
                    const SizedBox(height: 8),
                    Text('Join MealHub today and start receiving more orders with lower commissions.', style: TextStyle(fontSize: 12, color: _slate, height: 1.5)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _navy,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Get Onboarded Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(child: Text('It only takes 2 minutes!', style: TextStyle(fontSize: 11, color: _slate))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _steps = [
    (Icons.assignment_rounded, 'Get Onboarded', 'Fill out our quick form and we\'ll take care of the rest.'),
    (Icons.storefront_rounded, 'Go Live', 'We set up your menu, store, and start listing your restaurant.'),
    (Icons.delivery_dining_rounded, 'Get Orders', 'Receive more orders from local customers on MealHub.'),
    (Icons.payments_rounded, 'Get Paid', 'Enjoy fast payouts and keep more of your hard-earned money.'),
  ];
}

class _StepCard extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String desc;
  const _StepCard({required this.number, required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Icon(icon, color: _gold, size: 28),
            ),
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 20, height: 20,
                decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                child: Center(child: Text(number, style: const TextStyle(color: _navy, fontSize: 10, fontWeight: FontWeight.w800))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
        const SizedBox(height: 4),
        Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: _slate, height: 1.5)),
      ],
    );
  }
}

// ─── Features ─────────────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 64),
      child: Column(
        children: [
          const Text('Everything You Need to Succeed', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 6),
          const Text('Powerful tools built for restaurant owners', style: TextStyle(color: _slate, fontSize: 15)),
          const SizedBox(height: 40),
          Row(
            children: [
              for (final f in _features)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: f.$3.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(f.$1, color: f.$3, size: 24),
                          ),
                          const SizedBox(height: 14),
                          Text(f.$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _navy)),
                          const SizedBox(height: 6),
                          Text(f.$4, style: const TextStyle(fontSize: 13, color: _slate, height: 1.5)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static const _features = [
    (Icons.percent_rounded, 'Low Commission Rates', _gold, 'Keep more of your revenue. Our rates are among the lowest in the industry.'),
    (Icons.analytics_rounded, 'Real-Time Analytics', Color(0xFF6366F1), 'Track orders, revenue, and customer trends with a beautiful live dashboard.'),
    (Icons.bolt_rounded, 'Instant Payouts', Color(0xFF10B981), 'Get paid quickly with automatic payouts straight to your bank account.'),
    (Icons.restaurant_menu_rounded, 'Easy Menu Management', Color(0xFF0EA5E9), 'Update your menu, prices, and availability in seconds from any device.'),
    (Icons.headset_mic_rounded, '24/7 Support', Color(0xFFEC4899), 'Dedicated support team ready to help you grow your restaurant business.'),
    (Icons.loyalty_rounded, 'Loyalty Programs', Color(0xFFF59E0B), 'Build a loyal customer base with built-in points and rewards programs.'),
  ];
}

// ─── Pricing ──────────────────────────────────────────────────────────────────

class _PricingSection extends StatelessWidget {
  final VoidCallback onSignUp;
  const _PricingSection({required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 64),
      child: Column(
        children: [
          const Text('Simple, Transparent Pricing', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 6),
          Container(width: 48, height: 3, decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          const Text('No hidden fees. No long-term contracts. Cancel anytime.', style: TextStyle(color: _slate, fontSize: 15)),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PricingCard(
                name: 'Starter',
                price: '8%',
                priceLabel: 'commission per order',
                color: const Color(0xFF6366F1),
                features: const ['Up to 100 orders/month', 'Basic analytics', 'Standard support', 'Menu management', 'Customer reviews'],
                isPopular: false,
                onSignUp: onSignUp,
              ),
              const SizedBox(width: 20),
              _PricingCard(
                name: 'Growth',
                price: '5%',
                priceLabel: 'commission per order',
                color: _gold,
                features: const ['Unlimited orders', 'Advanced analytics', 'Priority support', 'Menu management', 'Loyalty programs', 'Promotional tools'],
                isPopular: true,
                onSignUp: onSignUp,
              ),
              const SizedBox(width: 20),
              _PricingCard(
                name: 'Enterprise',
                price: '3%',
                priceLabel: 'commission per order',
                color: const Color(0xFF10B981),
                features: const ['Unlimited orders', 'Full analytics suite', 'Dedicated account manager', 'Custom integrations', 'All Growth features', 'White-label options'],
                isPopular: false,
                onSignUp: onSignUp,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String name;
  final String price;
  final String priceLabel;
  final Color color;
  final List<String> features;
  final bool isPopular;
  final VoidCallback onSignUp;

  const _PricingCard({
    required this.name, required this.price, required this.priceLabel,
    required this.color, required this.features, required this.isPopular,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isPopular ? _navy : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPopular ? _gold : const Color(0xFFE2E8F0), width: isPopular ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isPopular ? 0.2 : 0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(20)),
              child: const Text('Most Popular', style: TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isPopular ? Colors.white : _navy)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color, height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(priceLabel, style: TextStyle(fontSize: 11, color: isPopular ? Colors.white54 : _slate)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: color, size: 16),
                  const SizedBox(width: 8),
                  Text(f, style: TextStyle(fontSize: 13, color: isPopular ? Colors.white70 : _slate)),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSignUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPopular ? _gold : color.withValues(alpha: 0.1),
                foregroundColor: isPopular ? _navy : color,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isPopular ? _navy : color)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Testimonials ─────────────────────────────────────────────────────────────

class _TestimonialsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 64),
      child: Column(
        children: [
          const Text('What Restaurant Owners Say', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 6),
          Container(width: 48, height: 3, decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 40),
          Row(
            children: [
              for (final t in _testimonials)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [for (int i = 0; i < 5; i++) const Icon(Icons.star_rounded, color: _gold, size: 16)]),
                          const SizedBox(height: 12),
                          Text('"${t.$1}"', style: const TextStyle(fontSize: 13, color: _navyLight, fontStyle: FontStyle.italic, height: 1.5)),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _gold.withValues(alpha: 0.15),
                                child: Text(t.$2[0], style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 14)),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
                                  Text(t.$3, style: const TextStyle(fontSize: 11, color: _slate)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static const _testimonials = [
    ('MealHub helped us cut delivery fees by 40%. Our monthly profit went up significantly in just the first month.', 'Michael T.', 'Pizza Palace, New York'),
    ('The dashboard is incredibly easy to use and the payouts are always on time. Best platform we\'ve worked with!', 'Sarah K.', 'Sushi Bistro, Los Angeles'),
    ('Customer support is outstanding. They helped us set everything up in under an hour and orders started coming in immediately.', 'James R.', 'The Burger Joint, Chicago'),
  ];
}

// ─── Final CTA ────────────────────────────────────────────────────────────────

class _CtaSection extends StatelessWidget {
  final VoidCallback onSignUp;
  const _CtaSection({required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _navy,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 72),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('🚀  Limited Time: 0% Commission for 30 Days', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          const Text('Start Growing Your Restaurant Today', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 12),
          Text('Join 500+ restaurants already using MealHub to reach more customers\nand keep more of their hard-earned revenue.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.7), height: 1.6)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: onSignUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: _navy,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                child: const Text('Get Onboarded Free →'),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Watch Demo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('No credit card required  ·  Setup in 2 minutes  ·  Cancel anytime',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45))),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0F1A),
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_gold, _goldLight]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: _navy, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text('MealHub', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('More orders. Lower commissions.\nGrow your restaurant.', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.6)),
              ],
            ),
          ),
          // Links
          for (final col in _footerCols)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  for (final link in col.$2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(link, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _footerCols = [
    ('PRODUCT', ['Features', 'Pricing', 'Analytics', 'Integrations']),
    ('COMPANY', ['About Us', 'Blog', 'Careers', 'Press']),
    ('SUPPORT', ['Help Center', 'Contact Us', 'Privacy Policy', 'Terms of Service']),
  ];
}
