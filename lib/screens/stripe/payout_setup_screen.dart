import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/stripe/connected_account_model.dart';
import '../../providers/stripe/connected_account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/stripe/stripe_onboarding_status_card.dart';

// ---------------------------------------------------------------------------
// Country / currency data for Stripe Connect Express supported countries
// ---------------------------------------------------------------------------

class _Country {
  final String code;
  final String name;
  final String currency;
  final String flag;
  const _Country(this.code, this.name, this.currency, this.flag);
}

const _countries = <_Country>[
  // Americas
  _Country('US', 'United States',        'usd', '🇺🇸'),
  _Country('CA', 'Canada',               'cad', '🇨🇦'),
  _Country('MX', 'Mexico',               'mxn', '🇲🇽'),
  _Country('BR', 'Brazil',               'brl', '🇧🇷'),
  _Country('JM', 'Jamaica',              'jmd', '🇯🇲'),
  _Country('TT', 'Trinidad & Tobago',    'ttd', '🇹🇹'),
  _Country('BB', 'Barbados',             'bbd', '🇧🇧'),
  _Country('BS', 'Bahamas',              'bsd', '🇧🇸'),
  _Country('GY', 'Guyana',               'gyd', '🇬🇾'),
  // Europe
  _Country('GB', 'United Kingdom',       'gbp', '🇬🇧'),
  _Country('DE', 'Germany',              'eur', '🇩🇪'),
  _Country('FR', 'France',               'eur', '🇫🇷'),
  _Country('NL', 'Netherlands',          'eur', '🇳🇱'),
  _Country('ES', 'Spain',                'eur', '🇪🇸'),
  _Country('IT', 'Italy',                'eur', '🇮🇹'),
  _Country('PT', 'Portugal',             'eur', '🇵🇹'),
  _Country('BE', 'Belgium',              'eur', '🇧🇪'),
  _Country('AT', 'Austria',              'eur', '🇦🇹'),
  _Country('CH', 'Switzerland',          'chf', '🇨🇭'),
  _Country('SE', 'Sweden',               'sek', '🇸🇪'),
  _Country('NO', 'Norway',               'nok', '🇳🇴'),
  _Country('DK', 'Denmark',              'dkk', '🇩🇰'),
  _Country('FI', 'Finland',              'eur', '🇫🇮'),
  _Country('IE', 'Ireland',              'eur', '🇮🇪'),
  _Country('PL', 'Poland',               'pln', '🇵🇱'),
  _Country('CZ', 'Czech Republic',       'czk', '🇨🇿'),
  _Country('HU', 'Hungary',              'huf', '🇭🇺'),
  _Country('RO', 'Romania',              'ron', '🇷🇴'),
  _Country('BG', 'Bulgaria',             'bgn', '🇧🇬'),
  _Country('HR', 'Croatia',              'eur', '🇭🇷'),
  _Country('SK', 'Slovakia',             'eur', '🇸🇰'),
  _Country('SI', 'Slovenia',             'eur', '🇸🇮'),
  _Country('EE', 'Estonia',              'eur', '🇪🇪'),
  _Country('LV', 'Latvia',               'eur', '🇱🇻'),
  _Country('LT', 'Lithuania',            'eur', '🇱🇹'),
  _Country('LU', 'Luxembourg',           'eur', '🇱🇺'),
  _Country('GR', 'Greece',               'eur', '🇬🇷'),
  _Country('CY', 'Cyprus',               'eur', '🇨🇾'),
  _Country('MT', 'Malta',                'eur', '🇲🇹'),
  _Country('LI', 'Liechtenstein',        'chf', '🇱🇮'),
  // Asia Pacific
  _Country('AU', 'Australia',            'aud', '🇦🇺'),
  _Country('NZ', 'New Zealand',          'nzd', '🇳🇿'),
  _Country('SG', 'Singapore',            'sgd', '🇸🇬'),
  _Country('HK', 'Hong Kong',            'hkd', '🇭🇰'),
  _Country('JP', 'Japan',                'jpy', '🇯🇵'),
  _Country('MY', 'Malaysia',             'myr', '🇲🇾'),
  _Country('TH', 'Thailand',             'thb', '🇹🇭'),
  _Country('PH', 'Philippines',          'php', '🇵🇭'),
  _Country('ID', 'Indonesia',            'idr', '🇮🇩'),
  _Country('IN', 'India',                'inr', '🇮🇳'),
  _Country('PK', 'Pakistan',             'pkr', '🇵🇰'),
  _Country('BD', 'Bangladesh',           'bdt', '🇧🇩'),
  // Africa
  _Country('NG', 'Nigeria',              'ngn', '🇳🇬'),
  _Country('GH', 'Ghana',                'ghs', '🇬🇭'),
  _Country('KE', 'Kenya',                'kes', '🇰🇪'),
  _Country('ZA', 'South Africa',         'zar', '🇿🇦'),
  _Country('TZ', 'Tanzania',             'tzs', '🇹🇿'),
  _Country('MU', 'Mauritius',            'mur', '🇲🇺'),
  _Country('RW', 'Rwanda',               'rwf', '🇷🇼'),
  _Country('EG', 'Egypt',                'egp', '🇪🇬'),
  _Country('ET', 'Ethiopia',             'etb', '🇪🇹'),
  _Country('CI', 'Côte d\'Ivoire',       'xof', '🇨🇮'),
  _Country('SN', 'Senegal',              'xof', '🇸🇳'),
  _Country('MG', 'Madagascar',           'mga', '🇲🇬'),
  _Country('AO', 'Angola',               'aoa', '🇦🇴'),
  _Country('ZM', 'Zambia',               'zmw', '🇿🇲'),
  // Middle East
  _Country('AE', 'UAE',                  'aed', '🇦🇪'),
  _Country('SA', 'Saudi Arabia',         'sar', '🇸🇦'),
  _Country('QA', 'Qatar',                'qar', '🇶🇦'),
  _Country('BH', 'Bahrain',              'bhd', '🇧🇭'),
  _Country('OM', 'Oman',                 'omr', '🇴🇲'),
  _Country('KW', 'Kuwait',               'kwd', '🇰🇼'),
  _Country('JO', 'Jordan',               'jod', '🇯🇴'),
  _Country('IL', 'Israel',               'ils', '🇮🇱'),
  _Country('TR', 'Turkey',               'try', '🇹🇷'),
  // Other
  _Country('UY', 'Uruguay',              'uyu', '🇺🇾'),
  _Country('PR', 'Puerto Rico',          'usd', '🇵🇷'),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PayoutSetupScreen extends ConsumerStatefulWidget {
  final String role;
  const PayoutSetupScreen({super.key, required this.role});

  @override
  ConsumerState<PayoutSetupScreen> createState() => _PayoutSetupScreenState();
}

class _PayoutSetupScreenState extends ConsumerState<PayoutSetupScreen>
    with WidgetsBindingObserver {
  bool _returningFromStripe = false;
  _Country _selectedCountry = _countries.first; // defaults to US

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _returningFromStripe) {
      _returningFromStripe = false;
      _refresh();
    }
  }

  void _refresh() {
    final userId = ref.read(currentUserIdProvider) ?? '';
    ref
        .read(connectedAccountProvider(userId).notifier)
        .refreshStatus(role: widget.role);
  }

  Future<void> _setup() async {
    final userId = ref.read(currentUserIdProvider) ?? '';
    await ref.read(connectedAccountProvider(userId).notifier).setupAccount(
          role: widget.role,
          country: _selectedCountry.code,
          currency: _selectedCountry.currency,
        );
    await _openOnboarding();
  }

  Future<void> _openOnboarding() async {
    final userId = ref.read(currentUserIdProvider) ?? '';
    final url = await ref
        .read(connectedAccountProvider(userId).notifier)
        .getOnboardingUrl(role: widget.role);
    if (url != null && mounted) {
      _returningFromStripe = true;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(selected: _selectedCountry),
    );
    if (picked != null) setState(() => _selectedCountry = picked);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final state = ref.watch(connectedAccountProvider(userId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: const Text('Payout Setup'),
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _body(state.account, state.error),
    );
  }

  Widget _body(ConnectedAccount? account, String? error) {
    if (account == null) return _noAccount(error);
    switch (account.onboardingStatus) {
      case 'complete':
        return _complete(account);
      case 'restricted':
        return _restricted(account);
      default:
        return _pending(account);
    }
  }

  Widget _noAccount(String? error) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 72,
            color: Colors.white38,
          ),
          const SizedBox(height: 24),
          const Text(
            'Set Up Payouts',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Connect your bank account to receive earnings. Stripe supports banks in 40+ countries worldwide.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 32),

          // Country picker
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Your country',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickCountry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2030),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2D3E)),
              ),
              child: Row(
                children: [
                  Text(_selectedCountry.flag, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedCountry.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _selectedCountry.currency.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white38),
                ],
              ),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
              ),
            ),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _setup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue to Stripe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You\'ll be taken to Stripe\'s secure onboarding to verify your identity and add your bank details.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _pending(ConnectedAccount account) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pending_outlined, size: 72, color: Color(0xFFF59E0B)),
          const SizedBox(height: 24),
          const Text(
            'Complete Your Setup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Finish Stripe onboarding to start receiving payouts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue Stripe Setup',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _refresh,
            child: const Text(
              'I already completed setup — refresh status',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _restricted(ConnectedAccount account) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StripeOnboardingStatusCard(account: account, onFix: _openOnboarding),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Fix Stripe Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _complete(ConnectedAccount account) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StripeOnboardingStatusCard(account: account),
          const SizedBox(height: 24),
          const Text(
            'Your account is fully set up. Head to your earnings to request a payout.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh status'),
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Country picker bottom sheet
// ---------------------------------------------------------------------------

class _CountryPickerSheet extends StatefulWidget {
  final _Country selected;
  const _CountryPickerSheet({required this.selected});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _search = TextEditingController();
  List<_Country> _filtered = _countries;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final q = _search.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? _countries
            : _countries
                .where((c) =>
                    c.name.toLowerCase().contains(q) ||
                    c.code.toLowerCase().contains(q) ||
                    c.currency.toLowerCase().contains(q))
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Your Country',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search country or currency...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final c = _filtered[i];
                final isSelected = c.code == widget.selected.code;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    c.currency.toUpperCase(),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle,
                          color: AppTheme.primaryColor, size: 20)
                      : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
