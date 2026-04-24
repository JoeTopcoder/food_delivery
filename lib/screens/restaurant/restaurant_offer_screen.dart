import 'package:flutter/material.dart';
import '../../config/app_constants.dart';
import '../../utils/app_theme.dart';

/// Showcases the MealHub restaurant partnership offer.
/// Shown during onboarding and accessible from the restaurant dashboard.
class RestaurantOfferScreen extends StatelessWidget {
  /// If true, shows "Get Started" CTA that pops back to signup/setup.
  final bool showGetStarted;

  const RestaurantOfferScreen({super.key, this.showGetStarted = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Limited Spots',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Grow Your\nRestaurant with\nMealHub',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Make more money per order. Bring customers back.\nZero risk.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Risk-Free Trial ─────────────────────────
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: _OfferCard(
                      gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                      icon: Icons.verified_rounded,
                      title: 'Risk-Free Start',
                      subtitle: 'Try us with zero commitment',
                      highlights: const [
                        _Highlight(
                          icon: Icons.money_off_rounded,
                          text: '0% commission for first 14 days',
                        ),
                        _Highlight(
                          icon: Icons.rocket_launch_rounded,
                          text: 'Free onboarding & setup',
                        ),
                        _Highlight(
                          icon: Icons.block_rounded,
                          text: 'No contracts — cancel anytime',
                        ),
                      ],
                    ),
                  ),

                  // ── Profit Advantage ────────────────────────
                  _OfferCard(
                    gradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
                    icon: Icons.trending_up_rounded,
                    title: 'Keep More Profit',
                    subtitle: 'Lowest commission in the market',
                    highlights: [
                      _Highlight(
                        icon: Icons.percent_rounded,
                        text: '10–15% commission (vs 25–30% on Uber Eats)',
                      ),
                      _Highlight(
                        icon: Icons.delivery_dining_rounded,
                        text: '5–10% if you use your own drivers',
                      ),
                      _Highlight(
                        icon: Icons.savings_rounded,
                        text:
                            'Save ${AppConstants.currencySymbol}1,000s per month',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Comparison Table ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.compare_arrows_rounded,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'See The Difference',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Header row
                        Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Text('', style: TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'MealHub',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              flex: 2,
                              child: Text(
                                'Others',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _CompareRow(
                          label: 'Commission',
                          ours: '10–15%',
                          theirs: '25–30%',
                          weWin: true,
                        ),
                        _CompareRow(
                          label: 'Free Trial',
                          ours: '14 days',
                          theirs: 'None',
                          weWin: true,
                        ),
                        _CompareRow(
                          label: 'Marketing',
                          ours: 'Free',
                          theirs: 'Paid',
                          weWin: true,
                        ),
                        _CompareRow(
                          label: 'Payout',
                          ours: '24–48h',
                          theirs: '7–14 days',
                          weWin: true,
                        ),
                        _CompareRow(
                          label: 'Loyalty',
                          ours: 'Built-in',
                          theirs: 'Weak',
                          weWin: true,
                        ),
                        _CompareRow(
                          label: 'Contracts',
                          ours: 'None',
                          theirs: 'Lock-in',
                          weWin: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Free Growth ─────────────────────────────
                  _OfferCard(
                    gradient: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                    icon: Icons.campaign_rounded,
                    title: 'Free Marketing',
                    subtitle: 'We promote you — no charge',
                    highlights: const [
                      _Highlight(
                        icon: Icons.star_rounded,
                        text: 'Featured placement in app',
                      ),
                      _Highlight(
                        icon: Icons.celebration_rounded,
                        text: '"Restaurant of the Week" spotlight',
                      ),
                      _Highlight(
                        icon: Icons.visibility_rounded,
                        text: 'Guaranteed visibility for 30 days',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Repeat Customers ────────────────────────
                  _OfferCard(
                    gradient: const [Color(0xFF7C3AED), Color(0xFF9333EA)],
                    icon: Icons.loyalty_rounded,
                    title: 'Built-In Repeat Customers',
                    subtitle:
                        'We don\'t just send customers — we help you keep them',
                    highlights: const [
                      _Highlight(
                        icon: Icons.stars_rounded,
                        text: 'Customers earn rewards at YOUR restaurant',
                      ),
                      _Highlight(
                        icon: Icons.replay_rounded,
                        text: 'Loyalty tiers encourage repeat orders',
                      ),
                      _Highlight(
                        icon: Icons.trending_up_rounded,
                        text: 'Track retention & engagement in real-time',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Fast Cash Flow ──────────────────────────
                  _OfferCard(
                    gradient: const [Color(0xFFEC4899), Color(0xFFF472B6)],
                    icon: Icons.bolt_rounded,
                    title: 'Fast Cash Flow',
                    subtitle: 'Get paid in 24–48 hours',
                    highlights: const [
                      _Highlight(
                        icon: Icons.speed_rounded,
                        text: 'Payout in 24–48 hours',
                      ),
                      _Highlight(
                        icon: Icons.access_time_rounded,
                        text: 'Competitors: 7–14 day wait',
                      ),
                      _Highlight(
                        icon: Icons.account_balance_rounded,
                        text: 'Direct deposit to your bank',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Full Control ────────────────────────────
                  _OfferCard(
                    gradient: const [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
                    icon: Icons.tune_rounded,
                    title: 'You Stay In Control',
                    subtitle: 'Your restaurant, your rules',
                    highlights: const [
                      _Highlight(
                        icon: Icons.price_change_rounded,
                        text: 'Set your own prices',
                      ),
                      _Highlight(
                        icon: Icons.block_rounded,
                        text: 'No forced discounts',
                      ),
                      _Highlight(
                        icon: Icons.visibility_off_rounded,
                        text: 'No hidden fees — ever',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Quote / CTA ─────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.format_quote_rounded,
                          color: Colors.white38,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'There\'s really no downside — you can try it for free, keep more profit, and see results yourself.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'We\'re only onboarding a limited number of restaurants at this rate.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── CTA Button ──────────────────────────────
                  if (showGetStarted)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch_rounded, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Sign Me Up — It\'s Free',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Offer Card ───────────────────────────────────────────────────────────────

class _OfferCard extends StatelessWidget {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<_Highlight> highlights;

  const _OfferCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlights,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...highlights.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: gradient[0].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(h.icon, color: gradient[0], size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      h.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
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

// ── Compare Row ──────────────────────────────────────────────────────────────

class _CompareRow extends StatelessWidget {
  final String label;
  final String ours;
  final String theirs;
  final bool weWin;

  const _CompareRow({
    required this.label,
    required this.ours,
    required this.theirs,
    required this.weWin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: weWin
                    ? const Color(0xFF10B981).withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ours,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: weWin
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              theirs,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Highlight Model ──────────────────────────────────────────────────────────

class _Highlight {
  final IconData icon;
  final String text;

  const _Highlight({required this.icon, required this.text});
}
