import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Admin management of curated 🔥 HotBite Picks. Admins feature restaurants
/// (and can extend to menu items / grocery) in the customer discovery hub,
/// controlling section, display order, active state and an optional date
/// window. All writes go through the admin-gated `admin_upsert_hotbite_pick`
/// RPC; reads use the admin RLS policy on `hotbite_picks`.
class AdminHotBitePicksScreen extends ConsumerStatefulWidget {
  const AdminHotBitePicksScreen({super.key});

  @override
  ConsumerState<AdminHotBitePicksScreen> createState() =>
      _AdminHotBitePicksScreenState();
}

class _AdminHotBitePicksScreenState
    extends ConsumerState<AdminHotBitePicksScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    // Admin RLS lets admins read every pick (active or not). Resolve names
    // with a client-side join against restaurants/menus.
    final picks = await Supabase.instance.client
        .from('hotbite_picks')
        .select()
        .order('section')
        .order('display_order');
    final rows = (picks as List).cast<Map<String, dynamic>>();
    for (final p in rows) {
      final isRest =
          p['entity_type'] == 'restaurant' || p['entity_type'] == 'grocery_store';
      final table = isRest ? 'restaurants' : 'menus';
      try {
        final e = await Supabase.instance.client
            .from(table)
            .select('name')
            .eq('id', p['entity_id'])
            .maybeSingle();
        p['_name'] = e?['name'] ?? '(missing)';
      } catch (_) {
        p['_name'] = '(missing)';
      }
    }
    return rows;
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _toggleActive(Map<String, dynamic> p) async {
    try {
      await Supabase.instance.client.rpc('admin_upsert_hotbite_pick', params: {
        'p_id': p['id'],
        'p_section': p['section'],
        'p_entity_type': p['entity_type'],
        'p_entity_id': p['entity_id'],
        'p_title': p['title'],
        'p_display_order': p['display_order'],
        'p_starts_at': p['starts_at'],
        'p_ends_at': p['ends_at'],
        'p_is_active': !(p['is_active'] as bool),
      });
      _refresh();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    try {
      await Supabase.instance.client
          .from('hotbite_picks')
          .delete()
          .eq('id', p['id']);
      _refresh();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _featureRestaurant() async {
    final restaurants = await ref
        .read(restaurantServiceProvider)
        .getAllRestaurants(limit: 100);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView.builder(
          controller: controller,
          itemCount: restaurants.length,
          itemBuilder: (ctx, i) => ListTile(
            title: Text(restaurants[i].name),
            subtitle: Text(restaurants[i].cuisineType ?? ''),
            onTap: () => Navigator.pop(ctx, restaurants[i].id),
          ),
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await Supabase.instance.client.rpc('admin_upsert_hotbite_pick', params: {
        'p_id': null,
        'p_section': 'featured',
        'p_entity_type': 'restaurant',
        'p_entity_id': chosen,
        'p_display_order': 0,
        'p_is_active': true,
      });
      if (mounted) AppSnackbar.success(context, 'Added to HotBite Picks');
      _refresh();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HotBite Picks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _featureRestaurant,
        icon: const Icon(Icons.add),
        label: const Text('Feature restaurant'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!)));
          }
          final picks = snap.data ?? const [];
          if (picks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No curated picks yet.\nTap "Feature restaurant" to promote a '
                  'local business in the customer discovery hub.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: picks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = picks[i];
              final active = p['is_active'] as bool? ?? false;
              return ListTile(
                leading: Icon(
                  active ? Icons.star_rounded : Icons.star_border_rounded,
                  color: active ? const Color(0xFFFF5A1F) : null,
                ),
                title: Text(p['_name'] as String? ?? '(unknown)'),
                subtitle: Text(
                  '${p['section']} · ${p['entity_type']} · order ${p['display_order']}'
                  '${active ? '' : ' · inactive'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: active,
                      onChanged: (_) => _toggleActive(p),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(p),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
