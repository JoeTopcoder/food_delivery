import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../providers/feature_providers.dart';

// ── Config keys managed by this screen ──────────────────────────────────────
const _deliveryConfigKeys = [
  'delivery_base_fee',
  'delivery_per_km_fee',
  'delivery_base_km',
  'delivery_max_km',
  'delivery_surge_multiplier',
  'driver_pay_percent',
  'min_delivery_fee',
  'default_delivery_fee',
  'driver_bonus_per_order',
];

// ── Provider: fetch delivery-related rows from app_config ───────────────────
final _deliveryConfigProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = Supabase.instance.client;
      final res = await client
          .from('app_config')
          .select()
          .inFilter('key', _deliveryConfigKeys)
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

  // Friendly labels for config keys
  static const _labels = <String, String>{
    'delivery_base_fee': 'Base Fee (\$)',
    'delivery_per_km_fee': 'Per-km Fee (\$)',
    'delivery_base_km': 'Included km (free range)',
    'delivery_max_km': 'Maximum Delivery Distance (km)',
    'delivery_surge_multiplier': 'Global Surge Multiplier',
    'driver_pay_percent': 'Driver Pay %',
    'min_delivery_fee': 'Minimum Delivery Fee (\$)',
    'default_delivery_fee': 'Default Flat Fee (\$)',
    'driver_bonus_per_order': 'Driver Bonus Per Order (\$)',
  };

  static const _hints = <String, String>{
    'delivery_base_fee': 'Charged for the first N km',
    'delivery_per_km_fee': 'Added for each km beyond the base range',
    'delivery_base_km': 'Km included in the base fee',
    'delivery_max_km': 'Orders beyond this distance are rejected',
    'delivery_surge_multiplier': '1.0 = no surge; 1.5 = 50 % premium',
    'driver_pay_percent': '0.80 = driver keeps 80 % of the fee',
    'min_delivery_fee': 'Fee will never go below this value',
    'default_delivery_fee': 'Flat fee when restaurant has no GPS',
    'driver_bonus_per_order':
        'Extra flat bonus added per delivery. 0 = no bonus',
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
  };

  // Text controllers keyed by config key
  final _controllers = <String, TextEditingController>{};
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(List<Map<String, dynamic>> configs) {
    for (final row in configs) {
      final key = row['key'] as String;
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: row['value']?.toString() ?? ''),
      );
    }
    // Ensure all keys exist even if missing from DB
    for (final key in _deliveryConfigKeys) {
      _controllers.putIfAbsent(key, () => TextEditingController(text: ''));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;
      for (final key in _deliveryConfigKeys) {
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
