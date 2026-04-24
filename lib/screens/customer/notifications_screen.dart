import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/context_extensions.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late final RealtimeChannel _channel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingNotifications();
    _subscribeToOrderUpdates();
    _hookForegroundCallback();
  }

  /// Catches foreground FCM order notifications and adds them to the in-memory
  /// list immediately — so the user sees them without leaving the screen.
  /// Uses the DB-assigned ID from `data['notification_id']` so that
  /// mark-as-read and clear-all correctly target the right row.
  void _hookForegroundCallback() {
    NotificationService.onOrderNotificationReceived =
        (type, title, body, data) {
          if (!mounted) return;
          // Prefer the real DB notification ID if the edge function includes it
          final dbId = data['notification_id'] as String?
              ?? data['id'] as String?
              ?? '${type}_${DateTime.now().millisecondsSinceEpoch}';
          ref
              .read(notificationNotifierProvider.notifier)
              .addNotification(
                AppNotification(
                  id: dbId,
                  type: type,
                  title: title,
                  body: body,
                  data: data,
                  timestamp: DateTime.now(),
                  isRead: false,
                ),
              );
        };
  }

  Future<void> _loadExistingNotifications() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(60);

      final notifier = ref.read(notificationNotifierProvider.notifier);
      final loaded = (rows as List).map((row) => AppNotification(
        id: row['id'] as String,
        type: row['type'] as String? ?? 'info',
        title: row['title'] as String? ?? '',
        body: row['body'] as String? ?? '',
        data: (row['data'] as Map<String, dynamic>?) ?? {},
        timestamp:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now(),
        isRead: row['is_read'] as bool? ?? false,
      )).toList();
      notifier.setAll(loaded);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _subscribeToOrderUpdates() {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    _channel = Supabase.instance.client
        .channel('user_notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            ref
                .read(notificationNotifierProvider.notifier)
                .addNotification(
                  AppNotification(
                    id: row['id'] as String? ?? DateTime.now().toString(),
                    type: row['type'] as String? ?? 'info',
                    title: row['title'] as String? ?? '',
                    body: row['body'] as String? ?? '',
                    data: (row['data'] as Map<String, dynamic>?) ?? {},
                    timestamp: DateTime.now(),
                  ),
                );
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_channel);
    // Remove the foreground callback so it doesn't fire after this screen is gone
    NotificationService.onOrderNotificationReceived = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationNotifierProvider);
    final notifier = ref.read(notificationNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.notifications,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          if (notifications.isNotEmpty)
            TextButton(
              onPressed: () async {
                final user = Supabase.instance.client.auth.currentUser;
                if (user != null) {
                  await Supabase.instance.client
                      .from('notifications')
                      .update({'is_read': true})
                      .eq('user_id', user.id)
                      .eq('is_read', false);
                }
                notifier.clearAll();
                if (context.mounted) {
                  AppSnackbar.success(context, 'All notifications cleared');
                }
              },
              child: const Text(
                'Clear All',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
          ? const _EmptyNotifications()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                return _NotifCard(
                  notification: n,
                  onTap: () {
                    notifier.markAsRead(n.id);
                    // Persist read state to DB
                    Supabase.instance.client
                        .from('notifications')
                        .update({'is_read': true})
                        .eq('id', n.id)
                        .then((_) {});
                  },
                  onDismiss: () {
                    notifier.removeNotification(n.id);
                    // Mark as read in DB so it doesn't reappear on next load
                    Supabase.instance.client
                        .from('notifications')
                        .update({'is_read': true})
                        .eq('id', n.id)
                        .then((_) {});
                  },
                );
              },
            ),
    );
  }
}

// ─── Notification Card ────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotifCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  IconData get _icon {
    switch (notification.type) {
      case 'order_placed':
        return Icons.receipt_long_rounded;
      case 'order_confirmed':
        return Icons.check_circle_rounded;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'out_for_delivery':
        return Icons.directions_bike_rounded;
      case 'delivered':
        return Icons.home_rounded;
      case 'payment':
        return Icons.payment_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color get _color {
    switch (notification.type) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'out_for_delivery':
        return const Color(0xFF6366F1);
      case 'preparing':
        return const Color(0xFFF59E0B);
      case 'payment':
        return const Color(0xFF10B981);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a · MMM d').format(notification.timestamp);
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notification.isRead
                ? Theme.of(context).cardColor
                : _color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: notification.isRead
                ? null
                : Border.all(color: _color.withValues(alpha: 0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No notifications yet.\nYour order updates will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
