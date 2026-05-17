import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../providers/feature_providers.dart';

// ── Supported currencies ────────────────────────────────────────────────────
const _currencies = [
  {'code': 'USD', 'symbol': '\$', 'name': 'US Dollar'},
  {'code': 'KYD', 'symbol': '\$', 'name': 'Cayman Islands Dollar'},
  {'code': 'JMD', 'symbol': '\$', 'name': 'Jamaican Dollar'},
  {'code': 'TTD', 'symbol': '\$', 'name': 'Trinidad & Tobago Dollar'},
  {'code': 'BBD', 'symbol': '\$', 'name': 'Barbados Dollar'},
  {'code': 'CAD', 'symbol': '\$', 'name': 'Canadian Dollar'},
  {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
  {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
];

// ── Config keys managed by this screen ──────────────────────────────────────
const _deliveryConfigKeys = [
  'delivery_base_fee',
  'delivery_per_mile_fee',
  'delivery_per_mile_fee_peak',
  'delivery_base_miles',
  'delivery_max_km',
  'delivery_surge_multiplier',
  'driver_pay_percent',
  'min_delivery_fee',
  'default_delivery_fee',
  'driver_bonus_per_order',
  'peak_addon_fee',
  'peak_hours_start',
  'peak_hours_end',
  'peak_hours_start_2',
  'peak_hours_end_2',
];

// Tax keys are loaded alongside delivery keys but rendered in their own section.
const _taxConfigKeys = ['tax_enabled', 'tax_rate'];

// Card verification charge range — shown to customers in the wallet add-card flow.
const _cardVerificationConfigKeys = [
  'card_verification_charge_min',
  'card_verification_charge_max',
];

// Currency keys stored in app_config.
const _currencyConfigKeys = [
  'currency_code',
  'currency_symbol',
  'currency_name',
];

// ── Provider: fetch delivery + tax + card verification + currency rows ────────
final _deliveryConfigProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = Supabase.instance.client;
      final res = await client
          .from('app_config')
          .select()
          .inFilter('key', [
            ..._deliveryConfigKeys,
            ..._taxConfigKeys,
            ..._cardVerificationConfigKeys,
            ..._currencyConfigKeys,
          ])
          .order('key');
      return List<Map<String, dynamic>>.from(res as List);
    });

// ── Screen ──────────────────────────────────────────────────────────────────

class AdminPricingScreen extends ConsumerStatefulWidget {
  const AdminPricingScreen({super.key});

  @override
  ConsumerState<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends ConsumerState<AdminPricingScreen> {
  bool _saving = false;
  bool _taxEnabled = true;
  final _taxRateCtrl = TextEditingController();
  String _selectedCurrencyCode = AppConstants.currencyCode;

  // Friendly labels for config keys
  static const _labels = <String, String>{
    'delivery_base_fee': 'Base Fee (\$)',
    'delivery_per_mile_fee': 'Per-Mile Fee (\$)',
    'delivery_per_mile_fee_peak': 'Per-Mile Fee – Peak (\$)',
    'delivery_base_miles': 'Included Miles (free range)',
    'delivery_max_km': 'Maximum Delivery Distance (km)',
    'delivery_surge_multiplier': 'Global Surge Multiplier',
    'driver_pay_percent': 'Driver Pay %',
    'min_delivery_fee': 'Minimum Delivery Fee (\$)',
    'default_delivery_fee': 'Default Flat Fee (\$)',
    'driver_bonus_per_order': 'Driver Bonus Per Order (\$)',
    'peak_addon_fee': 'Peak Hour Add-on (\$)',
    'peak_hours_start': 'Peak Hours Start (Lunch)',
    'peak_hours_end': 'Peak Hours End (Lunch)',
    'peak_hours_start_2': 'Peak Hours Start (Dinner)',
    'peak_hours_end_2': 'Peak Hours End (Dinner)',
  };

  static const _hints = <String, String>{
    'delivery_base_fee': 'Charged for the first N miles',
    'delivery_per_mile_fee': '\$2.00/mi standard rate',
    'delivery_per_mile_fee_peak': '\$2.50/mi during peak hours',
    'delivery_base_miles': 'Miles included in the base fee',
    'delivery_max_km': 'Orders beyond this distance are rejected',
    'delivery_surge_multiplier': '1.0 = no surge; 1.5 = 50 % premium',
    'driver_pay_percent': '0.80 = driver keeps 80 % of the fee',
    'min_delivery_fee': 'Fee will never go below this value',
    'default_delivery_fee': 'Flat fee when restaurant has no GPS',
    'driver_bonus_per_order':
        'Extra flat bonus added per delivery. 0 = no bonus',
    'peak_addon_fee': 'Extra flat fee during peak hours. 0 = disabled',
    'peak_hours_start': '24h format (e.g. 11 = 11 AM)',
    'peak_hours_end': '24h format (e.g. 14 = 2 PM)',
    'peak_hours_start_2': '24h format (e.g. 18 = 6 PM)',
    'peak_hours_end_2': '24h format (e.g. 21 = 9 PM)',
  };

  static const _icons = <String, IconData>{
    'delivery_base_fee': Icons.attach_money,
    'delivery_per_km_fee': Icons.straighten,
    'delivery_base_km': Icons.map_outlined,
    'delivery_max_km': Icons.block,
    'delivery_surge_multiplier': Icons.bolt,
    'driver_pay_percent': Icons.person_outline,
    'min_delivery_fee': Icons.vertical_align_bottom,
    'default_delivery_fee': Icons.local_offer_outlined,
    'driver_bonus_per_order': Icons.card_giftcard,
    'peak_addon_fee': Icons.trending_up,
    'peak_hours_start': Icons.schedule,
    'peak_hours_end': Icons.schedule,
    'peak_hours_start_2': Icons.nightlight_round,
    'peak_hours_end_2': Icons.nightlight_round,
  };

  // Text controllers keyed by config key
  final _controllers = <String, TextEditingController>{};
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _taxRateCtrl.dispose();
    super.dispose();
  }

  bool _taxInitialized = false;
  bool _currencyInitialized = false;

  void _initControllers(List<Map<String, dynamic>> configs) {
    for (final row in configs) {
      final key = row['key'] as String;
      final raw = row['value']?.toString() ?? '';
      if (key == 'tax_enabled') {
        if (!_taxInitialized)
          _taxEnabled = raw == '1' || raw.toLowerCase() == 'true';
        continue;
      }
      if (key == 'tax_rate') {
        if (!_taxInitialized && _taxRateCtrl.text.isEmpty)
          _taxRateCtrl.text = raw;
        continue;
      }
      if (key == 'currency_code') {
        if (!_currencyInitialized && raw.isNotEmpty) {
          _selectedCurrencyCode = raw.toUpperCase();
        }
        continue;
      }
      if (key == 'currency_symbol' || key == 'currency_name') continue;
      _controllers.putIfAbsent(key, () => TextEditingController(text: raw));
    }
    _taxInitialized = true;
    _currencyInitialized = true;
    // Ensure all keys exist even if missing from DB
    for (final key in [..._deliveryConfigKeys, ..._cardVerificationConfigKeys]) {
      _controllers.putIfAbsent(key, () => TextEditingController(text: ''));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;
      for (final key in [..._deliveryConfigKeys, ..._cardVerificationConfigKeys]) {
        final value = _controllers[key]?.text.trim() ?? '';
        if (value.isEmpty) continue;
        // Update existing row (all keys are pre-seeded via migrations)
        await client
            .from('app_config')
            .update({
              'value': value,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('key', key);
      }

      // Tax settings
      await client
          .from('app_config')
          .update({
            'value': _taxEnabled ? '1' : '0',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('key', 'tax_enabled');
      final rateText = _taxRateCtrl.text.trim();
      if (rateText.isNotEmpty) {
        await client
            .from('app_config')
            .update({
              'value': rateText,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('key', 'tax_rate');
      }

      // Currency settings
      final selectedCurrency = _currencies.firstWhere(
        (c) => c['code'] == _selectedCurrencyCode,
        orElse: () => _currencies.first,
      );
      for (final entry in {
        'currency_code': selectedCurrency['code']!,
        'currency_symbol': selectedCurrency['symbol']!,
        'currency_name': selectedCurrency['name']!,
      }.entries) {
        await client
            .from('app_config')
            .upsert({
              'key': entry.key,
              'value': entry.value,
              'value_type': 'string',
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'key');
      }

      // Update in-memory constants immediately
      _applyToConstants();

      // Clear delivery fee in-memory cache so new prices take effect
      ref.read(deliveryFeeServiceProvider).clearCache();

      // Clear delivery fee caches so new prices take effect
      try {
        await client
            .from('delivery_fee_cache')
            .delete()
            .lt(
              'expires_at',
              DateTime.now().add(const Duration(days: 365)).toIso8601String(),
            );
      } catch (_) {
        // Table may not exist yet — non-fatal
      }

      if (mounted) {
        ref.invalidate(_deliveryConfigProvider);
        ref.invalidate(deliveryFeeProvider);
        AppSnackbar.success(context, 'Pricing settings saved');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _applyToConstants() {
    double parseVal(String key, double fallback) {
      final v = double.tryParse(_controllers[key]?.text.trim() ?? '');
      return v ?? fallback;
    }

    AppConstants.deliveryBaseFee = parseVal(
      'delivery_base_fee',
      AppConstants.deliveryBaseFee,
    );
    AppConstants.deliveryPerKmFee = parseVal(
      'delivery_per_km_fee',
      AppConstants.deliveryPerKmFee,
    );
    AppConstants.deliveryBaseKm = parseVal(
      'delivery_base_km',
      AppConstants.deliveryBaseKm,
    );
    AppConstants.deliveryMaxKm = parseVal(
      'delivery_max_km',
      AppConstants.deliveryMaxKm,
    );
    AppConstants.deliverySurgeMultiplier = parseVal(
      'delivery_surge_multiplier',
      AppConstants.deliverySurgeMultiplier,
    );
    AppConstants.driverPayPercent = parseVal(
      'driver_pay_percent',
      AppConstants.driverPayPercent,
    );
    AppConstants.minDeliveryFee = parseVal(
      'min_delivery_fee',
      AppConstants.minDeliveryFee,
    );
    AppConstants.defaultDeliveryFee = parseVal(
      'default_delivery_fee',
      AppConstants.defaultDeliveryFee,
    );
    AppConstants.driverBonusPerOrder = parseVal(
      'driver_bonus_per_order',
      AppConstants.driverBonusPerOrder,
    );
    AppConstants.peakAddonFee = parseVal(
      'peak_addon_fee',
      AppConstants.peakAddonFee,
    );
    AppConstants.peakHoursStart = parseVal(
      'peak_hours_start',
      AppConstants.peakHoursStart.toDouble(),
    ).toInt();
    AppConstants.peakHoursEnd = parseVal(
      'peak_hours_end',
      AppConstants.peakHoursEnd.toDouble(),
    ).toInt();
    AppConstants.peakHoursStart2 = parseVal(
      'peak_hours_start_2',
      AppConstants.peakHoursStart2.toDouble(),
    ).toInt();
    AppConstants.peakHoursEnd2 = parseVal(
      'peak_hours_end_2',
      AppConstants.peakHoursEnd2.toDouble(),
    ).toInt();
    AppConstants.cardVerificationChargeMin = parseVal(
      'card_verification_charge_min',
      AppConstants.cardVerificationChargeMin,
    );
    AppConstants.cardVerificationChargeMax = parseVal(
      'card_verification_charge_max',
      AppConstants.cardVerificationChargeMax,
    );

    // Currency
    final selectedCurrency = _currencies.firstWhere(
      (c) => c['code'] == _selectedCurrencyCode,
      orElse: () => _currencies.first,
    );
    AppConstants.currencyCode = selectedCurrency['code']!;
    AppConstants.currencySymbol = selectedCurrency['symbol']!;
    AppConstants.currencyName = selectedCurrency['name']!;
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_deliveryConfigProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Delivery Pricing',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save',
              onPressed: _save,
            ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (configs) {
          _initControllers(configs);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              children: [
                // ── Info banner ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'These settings control delivery fee calculation across the platform. '
                          'Changes take effect immediately for new orders.',
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Fee formula preview ─────────────────────────────────
                _formulaPreview(context),
                const SizedBox(height: 20),

                // ── Config fields ───────────────────────────────────────
                ..._deliveryConfigKeys.map((key) => _configField(context, key)),

                const SizedBox(height: 12),
                _taxSection(context),

                const SizedBox(height: 12),
                _cardVerificationSection(context),

                const SizedBox(height: 12),
                _currencySection(context),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Saving…' : 'Save Changes'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xFF004E89),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _formulaPreview(BuildContext context) {
    final baseFee = _controllers['delivery_base_fee']?.text ?? '5.0';
    final perKm = _controllers['delivery_per_km_fee']?.text ?? '1.50';
    final baseKm = _controllers['delivery_base_km']?.text ?? '3';
    final surge = _controllers['delivery_surge_multiplier']?.text ?? '1.0';
    final driverPct = _controllers['driver_pay_percent']?.text ?? '0.80';
    final minFee = _controllers['min_delivery_fee']?.text ?? '3.0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fee Formula',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'fee = max( (\$$baseFee + extra_km × \$$perKm) × $surge , \$$minFee )',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'extra_km = max(0, distance − $baseKm)',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'driver_pay = fee × $driverPct',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _taxSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Tax',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            value: _taxEnabled,
            onChanged: (v) => setState(() => _taxEnabled = v),
            title: const Text('Charge tax on customer orders'),
            subtitle: Text(
              _taxEnabled
                  ? 'Tax is added to the order subtotal'
                  : 'No tax is added to customer bills',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          if (_taxEnabled) ...[
            const SizedBox(height: 4),
            TextFormField(
              controller: _taxRateCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Tax Rate',
                helperText: 'Decimal — e.g. 0.10 = 10%, 0.15 = 15%',
                prefixIcon: const Icon(Icons.percent),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
              validator: (v) {
                if (!_taxEnabled) return null;
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                final n = double.tryParse(t);
                if (n == null) return 'Enter a valid number';
                if (n < 0 || n > 1) return 'Must be between 0.0 and 1.0';
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardVerificationSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Card Verification Charge',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The range shown to customers when they add a card to their wallet. '
            'A micro-charge within this range is sent to verify ownership.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _controllers['card_verification_charge_min'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Min (\$)',
                    prefixIcon: const Icon(Icons.arrow_downward_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = double.tryParse(v.trim());
                    if (n == null) return 'Invalid number';
                    if (n < 0) return 'Must be ≥ 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _controllers['card_verification_charge_max'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Max (\$)',
                    prefixIcon: const Icon(Icons.arrow_upward_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = double.tryParse(v.trim());
                    if (n == null) return 'Invalid number';
                    if (n < 0) return 'Must be ≥ 0';
                    final minText = _controllers['card_verification_charge_min']?.text.trim() ?? '';
                    final minVal = double.tryParse(minText);
                    if (minVal != null && n < minVal) return 'Max must be ≥ Min';
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currencySection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = _currencies.firstWhere(
      (c) => c['code'] == _selectedCurrencyCode,
      orElse: () => _currencies.first,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Payment Currency',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sets the currency used for Stripe payments. '
            'Must be a currency supported by Stripe. '
            'Changing this affects all new orders.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedCurrencyCode,
            decoration: InputDecoration(
              labelText: 'Currency',
              prefixIcon: Text(
                selected['symbol']!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: cs.surfaceContainerLowest,
            ),
            items: _currencies
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c['code'],
                    child: Text('${c['code']} — ${c['name']} (${c['symbol']})'),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedCurrencyCode = v);
            },
          ),
          if (_selectedCurrencyCode == 'JMD')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'JMD amounts may fall below Stripe\'s \$0.50 USD minimum. '
                      'Consider using USD for reliable Stripe payments.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _configField(BuildContext context, String key) {
    final label = _labels[key] ?? key;
    final hint = _hints[key] ?? '';
    final icon = _icons[key] ?? Icons.settings;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 2,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty)
            return null; // allow empty (use default)
          final n = double.tryParse(v.trim());
          if (n == null) return 'Enter a valid number';
          if (n < 0) return 'Must be ≥ 0';
          if (key == 'driver_pay_percent' && (n < 0 || n > 1)) {
            return 'Must be between 0.0 and 1.0';
          }
          return null;
        },
      ),
    );
  }
}
