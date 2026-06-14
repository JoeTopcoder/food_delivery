import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/supabase_config.dart';
import '../../../providers/feature_providers.dart';
import '../../../services/app_config_service.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

final _webServiceTogglesProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('app_config')
      .select('key, value')
      .inFilter('key', [
        'service_food_enabled',
        'service_grocery_enabled',
        'service_rides_enabled',
        'service_laundry_enabled',
        'service_car_service_enabled',
      ]);
  final map = <String, bool>{};
  for (final r in rows as List) {
    map[r['key'] as String] = (r['value'] as String?) == 'true';
  }
  map.putIfAbsent('service_food_enabled', () => true);
  map.putIfAbsent('service_grocery_enabled', () => true);
  map.putIfAbsent('service_rides_enabled', () => true);
  map.putIfAbsent('service_laundry_enabled', () => true);
  map.putIfAbsent('service_car_service_enabled', () => true);
  return map;
});

const _serviceDefs = [
  (key: 'service_food_enabled', label: 'Food Delivery', subtitle: 'Restaurants, menus & order placement', icon: Icons.fastfood_rounded, color: Color(0xFFFF6B35)),
  (key: 'service_grocery_enabled', label: 'Grocery', subtitle: 'Grocery store browsing & orders', icon: Icons.local_grocery_store_rounded, color: Color(0xFF059669)),
  (key: 'service_rides_enabled', label: 'Ride Sharing', subtitle: 'Taxi & ride booking', icon: Icons.directions_car_rounded, color: Color(0xFF1E40AF)),
  (key: 'service_laundry_enabled', label: 'Laundry', subtitle: 'Pickup, wash & return delivery', icon: Icons.local_laundry_service_rounded, color: Color(0xFF0F4C81)),
  (key: 'service_car_service_enabled', label: 'Car Services', subtitle: 'Car wash & detailing bookings', icon: Icons.car_repair_rounded, color: Color(0xFF7C3AED)),
];

class WebAdminServicesPage extends ConsumerWidget {
  const WebAdminServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final togglesAsync = ref.watch(_webServiceTogglesProvider);

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
                    Text('Manage Services', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Enable or disable platform services for all customers', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(_webServiceTogglesProvider)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Info banner ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Disabled services show a "Coming Soon" badge on the customer home screen and block navigation into the service.',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          // ── Service cards ────────────────────────────────────────────
          togglesAsync.when(
            loading: () => const AppLoadingIndicator(),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webServiceTogglesProvider)),
            data: (toggles) => SizedBox(
              width: 720,
              child: Column(
                children: _serviceDefs.map((svc) => _ServiceCard(
                  def: svc,
                  enabled: toggles[svc.key] ?? true,
                  onChanged: (val) => _toggle(context, ref, svc.key, svc.label, val),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext ctx, WidgetRef ref, String key, String label, bool enabled) async {
    try {
      await SupabaseConfig.client
          .from('app_config')
          .update({'value': enabled ? 'true' : 'false'})
          .eq('key', key);
      await AppConfigService(SupabaseConfig.client).load();
      ref.read(configVersionProvider.notifier).state++;
      ref.invalidate(_webServiceTogglesProvider);
      if (ctx.mounted) AppSnackbar.success(ctx, '$label is now ${enabled ? 'enabled ✓' : 'disabled — Coming Soon shown'}');
    } catch (e) {
      if (ctx.mounted) AppSnackbar.error(ctx, friendlyError(e));
    }
  }
}

class _ServiceCard extends StatelessWidget {
  final ({String key, String label, String subtitle, IconData icon, Color color}) def;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ServiceCard({required this.def, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: enabled ? def.color.withValues(alpha: 0.3) : const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: enabled ? def.color.withValues(alpha: 0.12) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(def.icon, color: enabled ? def.color : Colors.grey, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: enabled ? const Color(0xFF1E293B) : Colors.grey)),
                Text(def.subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              enabled ? 'Live' : 'Coming Soon',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: enabled ? const Color(0xFF10B981) : Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: def.color,
            activeTrackColor: def.color.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
