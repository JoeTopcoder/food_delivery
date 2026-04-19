import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../providers/feature_providers.dart';
import '../../services/app_config_service.dart';

// ── Config keys managed by this screen ──────────────────────────────────────
const _subConfigKeys = [
  'subscription_basic_price',
  'subscription_basic_deliveries',
  'subscription_pro_price',
  'subscription_pro_deliveries',
  'subscription_min_cart',
  'subscription_service_fee_discount',
];

// ── Provider: fetch subscription config rows ────────────────────────────────
final _subConfigProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      // Refresh when admin changes values via Realtime
      ref.watch(configVersionProvider);
      final client = Supabase.instance.client;
      final res = await client
          .from('app_config')
          .select()
          .inFilter('key', _subConfigKeys)
          .order('key');
      return List<Map<String, dynamic>>.from(res as List);
    });

// ── Provider: active subscriber count ───────────────────────────────────────
final _activeSubCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final res = await Supabase.instance.client
      .from('user_subscriptions')
      .select()
      .eq('status', 'active')
      .not('plan_type', 'is', null)
      .count(CountOption.exact);
  return res.count;
});

// ── Screen ──────────────────────────────────────────────────────────────────

class AdminMealhubScreen extends ConsumerStatefulWidget {
  const AdminMealhubScreen({super.key});

  @override
  ConsumerState<AdminMealhubScreen> createState() => _AdminMealhubScreenState();
}

class _AdminMealhubScreenState extends ConsumerState<AdminMealhubScreen> {
  bool _saving = false;

  static const _labels = <String, String>{
    'subscription_basic_price': 'Basic Plan Price (\$)',
    'subscription_basic_deliveries': 'Basic Free Deliveries',
    'subscription_pro_price': 'Pro Plan Price (\$)',
    'subscription_pro_deliveries': 'Pro Free Deliveries',
    'subscription_min_cart': 'Min Cart for Free Delivery (\$)',
    'subscription_service_fee_discount': 'Service Fee Discount',
  };

  static const _hints = <String, String>{
    'subscription_basic_price': 'Monthly price for MealHub Basic',
    'subscription_basic_deliveries': 'Free deliveries per month (Basic)',
    'subscription_pro_price': 'Monthly price for MealHub Pro',
    'subscription_pro_deliveries': 'Free deliveries per month (Pro)',
    'subscription_min_cart': 'Order must exceed this to use free delivery',
    'subscription_service_fee_discount': '0.50 = 50% off service fee',
  };

  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final key = row['key'] as String;
      if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(
          text: row['value']?.toString() ?? '',
        );
      }
    }
  }

  Future<void> _saveAll(List<Map<String, dynamic>> rows) async {
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    var ok = true;

    for (final row in rows) {
      final key = row['key'] as String;
      final newVal = _controllers[key]?.text.trim() ?? '';
      if (newVal == (row['value']?.toString() ?? '')) continue;

      final resp = await client
          .from('app_config')
          .update({'value': newVal})
          .eq('key', key)
          .select()
          .maybeSingle();
      if (resp == null) ok = false;
    }

    // Reload config into AppConstants
    await AppConfigService(client).load();
    ref.invalidate(_subConfigProvider);

    if (!mounted) return;
    setState(() => _saving = false);
    ok
        ? AppSnackbar.success(context, 'MealHub+ settings saved')
        : AppSnackbar.error(context, 'Some values failed to save');
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_subConfigProvider);
    final subCount = ref.watch(_activeSubCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MealHub+ Plans',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_subConfigProvider);
              ref.invalidate(_activeSubCountProvider);
            },
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => AppErrorState(message: friendlyError(e)),
        data: (rows) {
          _initControllers(rows);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats banner
                _StatsBanner(subCount: subCount),
                const SizedBox(height: 20),

                // Basic Plan section
                _SectionHeader(
                  title: 'MealHub Basic',
                  color: const Color(0xFF2196F3),
                ),
                const SizedBox(height: 8),
                _ConfigField(
                  configKey: 'subscription_basic_price',
                  controller: _controllers['subscription_basic_price'],
                  label: _labels['subscription_basic_price']!,
                  hint: _hints['subscription_basic_price']!,
                  isNumber: true,
                ),
                const SizedBox(height: 10),
                _ConfigField(
                  configKey: 'subscription_basic_deliveries',
                  controller: _controllers['subscription_basic_deliveries'],
                  label: _labels['subscription_basic_deliveries']!,
                  hint: _hints['subscription_basic_deliveries']!,
                  isInt: true,
                ),

                const SizedBox(height: 24),

                // Pro Plan section
                _SectionHeader(
                  title: 'MealHub Pro',
                  color: const Color(0xFF6C63FF),
                ),
                const SizedBox(height: 8),
                _ConfigField(
                  configKey: 'subscription_pro_price',
                  controller: _controllers['subscription_pro_price'],
                  label: _labels['subscription_pro_price']!,
                  hint: _hints['subscription_pro_price']!,
                  isNumber: true,
                ),
                const SizedBox(height: 10),
                _ConfigField(
                  configKey: 'subscription_pro_deliveries',
                  controller: _controllers['subscription_pro_deliveries'],
                  label: _labels['subscription_pro_deliveries']!,
                  hint: _hints['subscription_pro_deliveries']!,
                  isInt: true,
                ),

                const SizedBox(height: 24),

                // General settings
                _SectionHeader(
                  title: 'General Settings',
                  color: const Color(0xFF059669),
                ),
                const SizedBox(height: 8),
                _ConfigField(
                  configKey: 'subscription_min_cart',
                  controller: _controllers['subscription_min_cart'],
                  label: _labels['subscription_min_cart']!,
                  hint: _hints['subscription_min_cart']!,
                  isNumber: true,
                ),
                const SizedBox(height: 10),
                _ConfigField(
                  configKey: 'subscription_service_fee_discount',
                  controller: _controllers['subscription_service_fee_discount'],
                  label: _labels['subscription_service_fee_discount']!,
                  hint: _hints['subscription_service_fee_discount']!,
                  isNumber: true,
                ),

                const SizedBox(height: 28),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : () => _saveAll(rows),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving ? 'Saving...' : 'Save All Changes',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Stats Banner ────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  final AsyncValue<int> subCount;
  const _StatsBanner({required this.subCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.card_membership_rounded,
            size: 40,
            color: Colors.white,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MealHub+ Subscribers',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                subCount.when(
                  data: (c) => Text(
                    '$c active',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  error: (_, __) => const Text(
                    '—',
                    style: TextStyle(fontSize: 28, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Config Field ────────────────────────────────────────────────────────────

class _ConfigField extends StatelessWidget {
  final String configKey;
  final TextEditingController? controller;
  final String label;
  final String hint;
  final bool isNumber;
  final bool isInt;

  const _ConfigField({
    required this.configKey,
    required this.controller,
    required this.label,
    required this.hint,
    this.isNumber = false,
    this.isInt = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      keyboardType: (isNumber || isInt)
          ? TextInputType.numberWithOptions(decimal: isNumber)
          : TextInputType.text,
    );
  }
}
