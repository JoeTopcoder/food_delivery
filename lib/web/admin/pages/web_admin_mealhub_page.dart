import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../providers/feature_providers.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Config keys managed by this page ─────────────────────────────────────────

const _subConfigKeys = [
  'subscription_basic_price',
  'subscription_basic_deliveries',
  'subscription_pro_price',
  'subscription_pro_deliveries',
  'subscription_min_cart',
  'subscription_service_fee_discount',
];

// ── Providers ─────────────────────────────────────────────────────────────────

final _webSubConfigProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(configVersionProvider);
  final res = await Supabase.instance.client
      .from('app_config')
      .select()
      .inFilter('key', _subConfigKeys)
      .order('key');
  return List<Map<String, dynamic>>.from(res as List);
});

final _webActiveSubCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final res = await Supabase.instance.client
      .from('user_subscriptions')
      .select()
      .eq('status', 'active')
      .not('plan_type', 'is', null)
      .count(CountOption.exact);
  return res.count;
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminMealhubPage extends ConsumerStatefulWidget {
  const WebAdminMealhubPage({super.key});

  @override
  ConsumerState<WebAdminMealhubPage> createState() => _WebAdminMealhubPageState();
}

class _WebAdminMealhubPageState extends ConsumerState<WebAdminMealhubPage> {
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;

  static const _labels = <String, String>{
    'subscription_basic_price': 'Basic Plan Price',
    'subscription_basic_deliveries': 'Basic Free Deliveries / month',
    'subscription_pro_price': 'Pro Plan Price',
    'subscription_pro_deliveries': 'Pro Free Deliveries / month',
    'subscription_min_cart': 'Min Cart for Free Delivery',
    'subscription_service_fee_discount': 'Service Fee Discount (0.5 = 50%)',
  };

  static const _icons = <String, IconData>{
    'subscription_basic_price': Icons.star_outline_rounded,
    'subscription_basic_deliveries': Icons.local_shipping_outlined,
    'subscription_pro_price': Icons.workspace_premium_rounded,
    'subscription_pro_deliveries': Icons.local_shipping_rounded,
    'subscription_min_cart': Icons.shopping_cart_outlined,
    'subscription_service_fee_discount': Icons.discount_outlined,
  };

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  void _initControllers(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final key = row['key'] as String;
      if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: row['value']?.toString() ?? '');
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
      try {
        await client.from('app_config').upsert({'key': key, 'value': newVal});
      } catch (_) {
        ok = false;
      }
    }
    ref.invalidate(_webSubConfigProvider);
    ref.read(configVersionProvider.notifier).state++;
    if (mounted) {
      setState(() => _saving = false);
      if (ok) {
        AppSnackbar.success(context, 'MealHub+ settings saved');
      } else {
        AppSnackbar.error(context, 'Some settings failed to save');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_webSubConfigProvider);
    final subCountAsync = ref.watch(_webActiveSubCountProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MealHub+', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Subscription plan configuration', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(_webSubConfigProvider)),
          ]),
          const SizedBox(height: 20),

          // ── Active subscribers banner ───────────────────────────────────
          subCountAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (count) => Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF9C4DCC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.card_membership_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Active Subscribers', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('$count', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                ]),
              ]),
            ),
          ),

          // ── Config form ─────────────────────────────────────────────────
          configAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webSubConfigProvider)),
            data: (rows) {
              _initControllers(rows);
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                      child: const Row(children: [
                        Icon(Icons.settings_rounded, size: 18, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Text('Subscription Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B))),
                      ]),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          ..._subConfigKeys.map((key) {
                            final ctrl = _controllers[key];
                            if (ctrl == null) return const SizedBox.shrink();
                            final label = _labels[key] ?? key;
                            final icon = _icons[key] ?? Icons.settings_rounded;
                            final isPrice = key.contains('price') || key.contains('cart');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: isPrice ? '$label (${AppConstants.currencySymbol})' : label,
                                  prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
                                  labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                  filled: true, fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2)),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _saving ? null : () => _saveAll(rows),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _saving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                          ),
                        ],
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
