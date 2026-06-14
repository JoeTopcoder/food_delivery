import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/admin_provider.dart';
import '../../../models/restaurant_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebAdminRestaurantsPage extends ConsumerStatefulWidget {
  const WebAdminRestaurantsPage({super.key});

  @override
  ConsumerState<WebAdminRestaurantsPage> createState() => _WebAdminRestaurantsPageState();
}

class _WebAdminRestaurantsPageState extends ConsumerState<WebAdminRestaurantsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['All', 'Pending', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allRestaurantsAdminProvider((0, 100)));
    final pendingAsync = ref.watch(pendingRestaurantsProvider);
    final rejectedAsync = ref.watch(rejectedRestaurantsProvider);

    final current = _tab.index == 0 ? allAsync : _tab.index == 1 ? pendingAsync : rejectedAsync;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Restaurants', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Manage restaurant partners', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 20),

          // ── Tabs ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
            ),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.all(6),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Table ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: current.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () {
                  ref.invalidate(allRestaurantsAdminProvider);
                  ref.invalidate(pendingRestaurantsProvider);
                }),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No restaurants found', style: TextStyle(color: Color(0xFF94A3B8))))
                    : _RestaurantsTable(
                        restaurants: items,
                        showActions: _tab.index == 1,
                        onApprove: (r) => _verify(r, true),
                        onReject: (r) => _verify(r, false),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verify(Restaurant r, bool approve) async {
    try {
      await ref.read(adminServiceProvider).verifyRestaurant(r.id, approve);
      ref.invalidate(allRestaurantsAdminProvider);
      ref.invalidate(pendingRestaurantsProvider);
      ref.invalidate(rejectedRestaurantsProvider);
      if (mounted) AppSnackbar.show(context, message: approve ? 'Restaurant approved' : 'Restaurant rejected', type: approve ? AppSnackbarType.success : AppSnackbarType.error);
    } catch (e) {
      if (mounted) AppSnackbar.show(context, message: friendlyError(e), type: AppSnackbarType.error);
    }
  }
}

class _RestaurantsTable extends StatelessWidget {
  final List<Restaurant> restaurants;
  final bool showActions;
  final ValueChanged<Restaurant> onApprove;
  final ValueChanged<Restaurant> onReject;

  const _RestaurantsTable({required this.restaurants, required this.showActions, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Expanded(flex: 2, child: _Th('Name')),
              const Expanded(child: _Th('Cuisine')),
              const Expanded(child: _Th('Status')),
              const Expanded(child: _Th('Rating')),
              const Expanded(child: _Th('Address')),
              if (showActions) const SizedBox(width: 120),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: ListView.separated(
            itemCount: restaurants.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final r = restaurants[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                    Expanded(child: Text(r.cuisineType ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                    Expanded(child: _StatusBadge(isVerified: r.isVerified, isOpen: r.isOpen)),
                    Expanded(child: Row(children: [
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(r.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ])),
                    Expanded(child: Text(r.address ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
                    if (showActions) SizedBox(
                      width: 120,
                      child: Row(
                        children: [
                          _ActionBtn(label: '✓', color: const Color(0xFF10B981), onTap: () => onApprove(r)),
                          const SizedBox(width: 6),
                          _ActionBtn(label: '✕', color: const Color(0xFFEF4444), onTap: () => onReject(r)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isVerified;
  final bool isOpen;
  const _StatusBadge({required this.isVerified, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final label = !isVerified ? 'Pending' : isOpen ? 'Open' : 'Closed';
    final color = !isVerified ? const Color(0xFFF59E0B) : isOpen ? const Color(0xFF10B981) : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}
