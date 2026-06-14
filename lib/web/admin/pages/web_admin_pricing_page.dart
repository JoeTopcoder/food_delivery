import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../providers/feature_providers.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

const _currencies = [
  {'code': 'USD', 'symbol': r'$', 'name': 'US Dollar'},
  {'code': 'KYD', 'symbol': r'$', 'name': 'Cayman Islands Dollar'},
  {'code': 'JMD', 'symbol': r'$', 'name': 'Jamaican Dollar'},
  {'code': 'TTD', 'symbol': r'$', 'name': 'Trinidad & Tobago Dollar'},
  {'code': 'BBD', 'symbol': r'$', 'name': 'Barbados Dollar'},
  {'code': 'CAD', 'symbol': r'$', 'name': 'Canadian Dollar'},
  {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
  {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
];

const _deliveryKeys = [
  'delivery_base_fee', 'delivery_per_mile_fee', 'delivery_per_mile_fee_peak',
  'delivery_base_miles', 'delivery_max_km', 'delivery_surge_multiplier',
  'driver_pay_percent', 'min_delivery_fee', 'default_delivery_fee',
  'driver_bonus_per_order', 'peak_addon_fee',
  'peak_hours_start', 'peak_hours_end', 'peak_hours_start_2', 'peak_hours_end_2',
];

const _cardVerifKeys = ['card_verification_charge_min', 'card_verification_charge_max'];

Map<String, String> get _labels => {
  'delivery_base_fee': 'Base Fee (${AppConstants.currencySymbol})',
  'delivery_per_mile_fee': 'Per-Mile Fee (${AppConstants.currencySymbol})',
  'delivery_per_mile_fee_peak': 'Per-Mile Fee – Peak (${AppConstants.currencySymbol})',
  'delivery_base_miles': 'Included Miles (free range)',
  'delivery_max_km': 'Max Delivery Distance (km)',
  'delivery_surge_multiplier': 'Global Surge Multiplier',
  'driver_pay_percent': 'Driver Pay %',
  'min_delivery_fee': 'Minimum Delivery Fee (${AppConstants.currencySymbol})',
  'default_delivery_fee': 'Default Flat Fee (${AppConstants.currencySymbol})',
  'driver_bonus_per_order': 'Driver Bonus Per Order (${AppConstants.currencySymbol})',
  'peak_addon_fee': 'Peak Hour Add-on (${AppConstants.currencySymbol})',
  'peak_hours_start': 'Peak Hours Start – Lunch (24h)',
  'peak_hours_end': 'Peak Hours End – Lunch (24h)',
  'peak_hours_start_2': 'Peak Hours Start – Dinner (24h)',
  'peak_hours_end_2': 'Peak Hours End – Dinner (24h)',
  'card_verification_charge_min': 'Card Verification Min (${AppConstants.currencySymbol})',
  'card_verification_charge_max': 'Card Verification Max (${AppConstants.currencySymbol})',
};

final _webPricingConfigProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await Supabase.instance.client
      .from('app_config')
      .select()
      .inFilter('key', [..._deliveryKeys, ..._cardVerifKeys, 'tax_enabled', 'tax_rate', 'currency_code', 'currency_symbol', 'currency_name'])
      .order('key');
  return List<Map<String, dynamic>>.from(res as List);
});

class WebAdminPricingPage extends ConsumerStatefulWidget {
  const WebAdminPricingPage({super.key});

  @override
  ConsumerState<WebAdminPricingPage> createState() => _WebAdminPricingPageState();
}

class _WebAdminPricingPageState extends ConsumerState<WebAdminPricingPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _taxRateCtrl = TextEditingController();
  bool _taxEnabled = true;
  bool _saving = false;
  bool _initialized = false;
  String _selectedCurrencyCode = AppConstants.currencyCode;

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    _taxRateCtrl.dispose();
    super.dispose();
  }

  void _init(List<Map<String, dynamic>> configs) {
    if (_initialized) return;
    for (final row in configs) {
      final key = row['key'] as String;
      final raw = row['value']?.toString() ?? '';
      if (key == 'tax_enabled') { _taxEnabled = raw == '1' || raw.toLowerCase() == 'true'; continue; }
      if (key == 'tax_rate') { if (_taxRateCtrl.text.isEmpty) _taxRateCtrl.text = raw; continue; }
      if (key == 'currency_code' && raw.isNotEmpty) { _selectedCurrencyCode = raw.toUpperCase(); continue; }
      if (key == 'currency_symbol' || key == 'currency_name') continue;
      _controllers.putIfAbsent(key, () => TextEditingController(text: raw));
    }
    for (final key in [..._deliveryKeys, ..._cardVerifKeys]) {
      _controllers.putIfAbsent(key, () => TextEditingController(text: ''));
    }
    _initialized = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      for (final key in [..._deliveryKeys, ..._cardVerifKeys]) {
        final val = _controllers[key]?.text.trim() ?? '';
        if (val.isEmpty) continue;
        await client.from('app_config').update({'value': val, 'updated_at': DateTime.now().toIso8601String()}).eq('key', key);
      }
      await client.from('app_config').update({'value': _taxEnabled ? '1' : '0', 'updated_at': DateTime.now().toIso8601String()}).eq('key', 'tax_enabled');
      final rateText = _taxRateCtrl.text.trim();
      if (rateText.isNotEmpty) {
        await client.from('app_config').update({'value': rateText, 'updated_at': DateTime.now().toIso8601String()}).eq('key', 'tax_rate');
      }
      final cur = _currencies.firstWhere((c) => c['code'] == _selectedCurrencyCode, orElse: () => _currencies.first);
      for (final entry in {'currency_code': cur['code']!, 'currency_symbol': cur['symbol']!, 'currency_name': cur['name']!}.entries) {
        await client.from('app_config').upsert({'key': entry.key, 'value': entry.value, 'value_type': 'string', 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'key');
      }
      ref.read(deliveryFeeServiceProvider).clearCache();
      ref.invalidate(_webPricingConfigProvider);
      if (mounted) AppSnackbar.success(context, 'Pricing settings saved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_webPricingConfigProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pricing & Config', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Delivery fees, surge, tax settings, and currency', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          configAsync.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webPricingConfigProvider)),
            data: (configs) {
              _init(configs);
              return Form(
                key: _formKey,
                child: Column(
                  children: [
                    _Section(
                      title: 'Delivery Fees',
                      icon: Icons.delivery_dining_rounded,
                      color: const Color(0xFF6366F1),
                      children: _deliveryKeys.map((k) => _FieldRow(key: ValueKey(k), label: _labels[k] ?? k, controller: _controllers[k]!)).toList(),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Card Verification',
                      icon: Icons.credit_card_rounded,
                      color: const Color(0xFF8B5CF6),
                      children: _cardVerifKeys.map((k) => _FieldRow(key: ValueKey(k), label: _labels[k] ?? k, controller: _controllers[k]!)).toList(),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Tax Settings',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF10B981),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(children: [
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Enable Tax', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text('Show tax line on receipts and checkout', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ])),
                            Switch.adaptive(value: _taxEnabled, onChanged: (v) => setState(() => _taxEnabled = v), activeTrackColor: const Color(0xFF10B981)),
                          ]),
                        ),
                        _FieldRow(label: 'Tax Rate (e.g. 0.15 = 15%)', controller: _taxRateCtrl),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Currency',
                      icon: Icons.currency_exchange_rounded,
                      color: const Color(0xFFF59E0B),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCurrencyCode,
                            decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
                            items: _currencies.map((c) => DropdownMenuItem(value: c['code'] as String, child: Text('${c['code']} (${c['symbol']}) — ${c['name']}'))).toList(),
                            onChanged: (v) => setState(() => _selectedCurrencyCode = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                        label: const Text('Save All Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004E89),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  const _Section({required this.title, required this.icon, required this.color, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ]),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

class _FieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _FieldRow({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
}
