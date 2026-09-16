import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../utils/friendly_error.dart';

/// A vertical timeline of an order's lifecycle — placed, accepted by the store,
/// assigned to a rider, picked up, out for delivery, delivered / cancelled —
/// with the time of each step and who performed it.
///
/// Reads from the shared `order_status_events` log (status, occurred_at,
/// actor_type), keyed by the `orders` table id, so it works from both the
/// admin order view and the store order view. Optional [extraTimestamps] can
/// supply canonical stage times (e.g. from the order row's own *_at columns)
/// that may not have an event, merged in by stage.
class OrderStatusTimeline extends StatefulWidget {
  final String orderId;

  /// Optional stage -> timestamp map to merge with the event log, using the
  /// canonical status keys below (e.g. {'confirmed': DateTime, 'ready': ...}).
  final Map<String, DateTime>? extraTimestamps;

  const OrderStatusTimeline({
    super.key,
    required this.orderId,
    this.extraTimestamps,
  });

  @override
  State<OrderStatusTimeline> createState() => _OrderStatusTimelineState();
}

class _OrderStatusTimelineState extends State<OrderStatusTimeline> {
  late Future<List<_Step>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // Canonical ordering of stages so a timeline reads top-to-bottom in the order
  // an order actually progresses, regardless of event arrival order.
  static const _order = <String, int>{
    'pending': 0,
    'placed': 0,
    'confirmed': 1,
    'accepted': 1,
    'preparing': 2,
    'ready': 3,
    'assigned': 4,
    'rider_assigned': 4,
    'picked_up': 5,
    'out_for_delivery': 6,
    'on_the_way': 6,
    'delivered': 7,
    'completed': 8,
    'cancelled': 9,
    'partially_cancelled': 9,
  };

  static String _label(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return 'Order placed';
      case 'confirmed':
      case 'accepted':
        return 'Accepted by store';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for pickup';
      case 'assigned':
      case 'rider_assigned':
        return 'Assigned to rider';
      case 'picked_up':
        return 'Picked up by rider';
      case 'out_for_delivery':
      case 'on_the_way':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'partially_cancelled':
        return 'Partially cancelled';
      default:
        return status
            .replaceAll('_', ' ')
            .replaceRange(0, 1, status.isEmpty ? '' : status[0].toUpperCase());
    }
  }

  static IconData _icon(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return Icons.receipt_long_rounded;
      case 'confirmed':
      case 'accepted':
        return Icons.storefront_rounded;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'ready':
        return Icons.check_circle_outline_rounded;
      case 'assigned':
      case 'rider_assigned':
        return Icons.person_pin_circle_rounded;
      case 'picked_up':
        return Icons.shopping_bag_rounded;
      case 'out_for_delivery':
      case 'on_the_way':
        return Icons.delivery_dining_rounded;
      case 'delivered':
      case 'completed':
        return Icons.task_alt_rounded;
      case 'cancelled':
      case 'partially_cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.circle;
    }
  }

  static String _actorLabel(String? actor) {
    switch (actor) {
      case 'customer':
        return 'customer';
      case 'store':
      case 'restaurant':
      case 'merchant':
        return 'store';
      case 'rider':
      case 'driver':
        return 'rider';
      case 'admin':
        return 'admin';
      case 'system':
      case null:
        return 'system';
      default:
        return actor;
    }
  }

  Future<List<_Step>> _load() async {
    final rows = await SupabaseConfig.client
        .from('order_status_events')
        .select('status, occurred_at, actor_type')
        .eq('order_id', widget.orderId)
        .order('occurred_at', ascending: true);

    // Best time + actor per stage (earliest event for that stage).
    final byStage = <String, _Step>{};
    for (final r in (rows as List)) {
      final status = (r['status'] ?? '').toString();
      if (status.isEmpty) continue;
      final t = DateTime.tryParse((r['occurred_at'] ?? '').toString());
      if (t == null) continue;
      final existing = byStage[status];
      if (existing == null || t.isBefore(existing.time)) {
        byStage[status] = _Step(
          status: status,
          time: t,
          actor: _actorLabel(r['actor_type']?.toString()),
        );
      }
    }

    // Merge in canonical timestamps that have no event.
    widget.extraTimestamps?.forEach((status, time) {
      if (!byStage.containsKey(status)) {
        byStage[status] = _Step(status: status, time: time, actor: null);
      }
    });

    final steps = byStage.values.toList()
      ..sort((a, b) {
        final oa = _order[a.status] ?? 50;
        final ob = _order[b.status] ?? 50;
        if (oa != ob) return oa.compareTo(ob);
        return a.time.compareTo(b.time);
      });
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<_Step>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text(friendlyError(snap.error!),
              style: TextStyle(color: scheme.error, fontSize: 13));
        }
        final steps = snap.data ?? [];
        if (steps.isEmpty) {
          return Text('No status history recorded yet.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++)
              _StepTile(
                step: steps[i],
                isFirst: i == 0,
                isLast: i == steps.length - 1,
                label: _label(steps[i].status),
                icon: _icon(steps[i].status),
                cancelled: steps[i].status.contains('cancel'),
              ),
          ],
        );
      },
    );
  }
}

class _Step {
  final String status;
  final DateTime time;
  final String? actor;
  const _Step({required this.status, required this.time, this.actor});
}

class _StepTile extends StatelessWidget {
  final _Step step;
  final bool isFirst;
  final bool isLast;
  final String label;
  final IconData icon;
  final bool cancelled;

  const _StepTile({
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.label,
    required this.icon,
    required this.cancelled,
  });

  static String _fmt(DateTime dt) {
    final l = dt.toLocal();
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ap = l.hour < 12 ? 'AM' : 'PM';
    final mm = l.minute.toString().padLeft(2, '0');
    return '${m[l.month - 1]} ${l.day}, $h:$mm $ap';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = cancelled ? scheme.error : const Color(0xFF10B981);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: connector line + node
          Column(
            children: [
              Container(
                width: 2,
                height: 6,
                color: isFirst ? Colors.transparent : scheme.outlineVariant,
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : scheme.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(step.time)}${step.actor != null ? '  ·  by ${step.actor}' : ''}',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
