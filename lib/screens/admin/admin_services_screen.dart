import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../providers/feature_providers.dart';
import '../../services/app_config_service.dart';
import '../../config/supabase_config.dart';

// ── Provider: live state of the 5 service toggles from DB ───────────────────
final _serviceTogglesProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
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
  // Defaults if a key is missing
  map.putIfAbsent('service_food_enabled', () => true);
  map.putIfAbsent('service_grocery_enabled', () => true);
  map.putIfAbsent('service_rides_enabled', () => true);
  map.putIfAbsent('service_laundry_enabled', () => true);
  map.putIfAbsent('service_car_service_enabled', () => true);
  return map;
});

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminServicesScreen extends ConsumerWidget {
  const AdminServicesScreen({super.key});

  static const _services = [
    _ServiceDef(
      key: 'service_food_enabled',
      label: 'Food Delivery',
      subtitle: 'Restaurants, menus & order placement',
      icon: Icons.fastfood_rounded,
      color: Color(0xFFFF6B35),
    ),
    _ServiceDef(
      key: 'service_grocery_enabled',
      label: 'Grocery',
      subtitle: 'Grocery store browsing & orders',
      icon: Icons.local_grocery_store_rounded,
      color: Color(0xFF059669),
    ),
    _ServiceDef(
      key: 'service_rides_enabled',
      label: 'Ride Sharing',
      subtitle: 'Taxi & ride booking',
      icon: Icons.directions_car_rounded,
      color: Color(0xFF1E40AF),
    ),
    _ServiceDef(
      key: 'service_laundry_enabled',
      label: 'Laundry',
      subtitle: 'Pickup, wash & return delivery',
      icon: Icons.local_laundry_service_rounded,
      color: Color(0xFF0F4C81),
    ),
    _ServiceDef(
      key: 'service_car_service_enabled',
      label: 'Car Services',
      subtitle: 'Car wash & detailing bookings',
      icon: Icons.car_repair_rounded,
      color: Color(0xFF7C3AED),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final togglesAsync = ref.watch(_serviceTogglesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Services',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: togglesAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading services…'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(_serviceTogglesProvider),
        ),
        data: (toggles) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Disabled services show a "Coming Soon" badge on the '
                      'customer home screen and block navigation into the service.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Service toggle tiles
            ...(_services.map(
              (svc) => _ServiceToggleTile(
                def: svc,
                enabled: toggles[svc.key] ?? true,
                onChanged: (val) =>
                    _toggle(context, ref, svc.key, val),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    String key,
    bool enabled,
  ) async {
    try {
      await SupabaseConfig.client
          .from('app_config')
          .update({'value': enabled ? 'true' : 'false'})
          .eq('key', key);

      // Reload AppConstants so the change is reflected instantly in this session
      await AppConfigService(SupabaseConfig.client).load();

      // Bump configVersionProvider so serviceEnabledProvider recalculates
      ref.read(configVersionProvider.notifier).state++;

      // Refresh this screen
      ref.invalidate(_serviceTogglesProvider);

      if (context.mounted) {
        final label = _services
            .firstWhere((s) => s.key == key)
            .label;
        AppSnackbar.success(
          context,
          '$label is now ${enabled ? 'enabled ✓' : 'disabled — Coming Soon shown'}',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

// ── Service definition ───────────────────────────────────────────────────────

class _ServiceDef {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _ServiceDef({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ── Toggle tile ───────────────────────────────────────────────────────────────

class _ServiceToggleTile extends StatelessWidget {
  final _ServiceDef def;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ServiceToggleTile({
    required this.def,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? def.color.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: enabled
                ? def.color.withValues(alpha: 0.12)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            def.icon,
            color: enabled ? def.color : Colors.grey,
            size: 22,
          ),
        ),
        title: Text(
          def.label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Colors.grey,
          ),
        ),
        subtitle: Text(
          def.subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                enabled ? 'Live' : 'Coming Soon',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? const Color(0xFF10B981)
                      : Colors.orange.shade700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: def.color,
              activeTrackColor: def.color.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
