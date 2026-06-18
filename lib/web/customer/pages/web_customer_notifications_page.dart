import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/notification_provider.dart';

class WebCustomerNotificationsPage extends ConsumerWidget {
  const WebCustomerNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Stay updated on your orders and promotions', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            if (notifications.isNotEmpty)
              TextButton(
                onPressed: () => ref.read(notificationNotifierProvider.notifier).clearAll(),
                child: const Text('Mark all read', style: TextStyle(color: Color(0xFFFF6B35))),
              ),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: notifications.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.notifications_none_rounded, size: 64, color: Color(0xFFE2E8F0)),
                        SizedBox(height: 12),
                        Text('No notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        SizedBox(height: 4),
                        Text('You\'re all caught up!', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                      ]),
                    )
                  : ListView.separated(
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final n = notifications[i];
                        return InkWell(
                          onTap: () => ref.read(notificationNotifierProvider.notifier).markAsRead(n.id),
                          child: Container(
                            color: n.isRead ? Colors.transparent : const Color(0xFFFFF8F5),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(
                                  color: _typeColor(n.type).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_typeIcon(n.type), color: _typeColor(n.type), size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(n.title, style: TextStyle(fontSize: 14, fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700, color: const Color(0xFF1E293B)))),
                                  if (!n.isRead)
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF6B35), shape: BoxShape.circle)),
                                ]),
                                const SizedBox(height: 3),
                                Text(n.body, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                                const SizedBox(height: 4),
                                Text(_formatDate(n.timestamp), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              ])),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
    'order'       => const Color(0xFF6366F1),
    'promo'       => const Color(0xFFFF6B35),
    'delivery'    => const Color(0xFF10B981),
    'payment'     => const Color(0xFFF59E0B),
    _             => const Color(0xFF64748B),
  };

  IconData _typeIcon(String type) => switch (type) {
    'order'       => Icons.receipt_long_rounded,
    'promo'       => Icons.local_offer_rounded,
    'delivery'    => Icons.delivery_dining_rounded,
    'payment'     => Icons.payments_rounded,
    _             => Icons.notifications_rounded,
  };

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
