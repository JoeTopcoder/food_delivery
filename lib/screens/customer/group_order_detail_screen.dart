import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/group_order_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';
import 'restaurant_detail_screen.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final groupOrderDetailProvider = FutureProvider.autoDispose
    .family<GroupOrder?, String>((ref, groupOrderId) async {
  final service = ref.watch(groupOrderServiceProvider);
  return service.getGroupOrder(groupOrderId);
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class GroupOrderDetailScreen extends ConsumerStatefulWidget {
  final String groupOrderId;

  const GroupOrderDetailScreen({super.key, required this.groupOrderId});

  @override
  ConsumerState<GroupOrderDetailScreen> createState() =>
      _GroupOrderDetailScreenState();
}

class _GroupOrderDetailScreenState
    extends ConsumerState<GroupOrderDetailScreen> {
  bool _locking = false;
  bool _cancelling = false;

  Future<void> _refresh() async {
    ref.invalidate(groupOrderDetailProvider(widget.groupOrderId));
  }

  Future<void> _lockGroup(GroupOrder group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock Group Order?'),
        content: const Text(
          'No more items can be added after locking. '
          'You will proceed to checkout with everyone\'s items combined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text(
              'Lock & Checkout',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _locking = true);
    try {
      final service = ref.read(groupOrderServiceProvider);
      await service.lockGroupOrder(widget.groupOrderId);
      await _refresh();
      if (mounted) {
        AppSnackbar.success(
          context,
          'Group order locked — proceed to checkout!',
        );
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _locking = false);
    }
  }

  Future<void> _cancelGroup(GroupOrder group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Group Order?'),
        content: const Text('This will cancel the group order for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel Group Order',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final service = ref.read(groupOrderServiceProvider);
      await service.cancelGroupOrder(widget.groupOrderId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _shareInvite(GroupOrder group) {
    Share.share(
      'Join my group order "${group.name}" on MealHub! '
      'Use invite code: ${group.inviteCode}\n\n'
      'Open the app → Group Orders → Join with code.',
    );
  }

  void _copyCode(GroupOrder group) {
    Clipboard.setData(ClipboardData(text: group.inviteCode));
    AppSnackbar.success(context, 'Invite code copied!');
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupOrderDetailProvider(widget.groupOrderId));
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Group Order',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: groupAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: _refresh,
        ),
        data: (group) {
          if (group == null) {
            return const AppEmptyState(
              icon: Icons.groups_rounded,
              title: 'Group order not found',
              subtitle: 'It may have been cancelled or expired.',
            );
          }
          final isHost = group.hostUserId == currentUserId;
          final isCollecting = group.status == 'collecting';
          final fmt = DateFormat('MMM d, h:mm a');

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                // ── Status + Name ──────────────────────────────────
                _StatusHeader(group: group, isHost: isHost),
                const SizedBox(height: 16),

                // ── Invite Code Card ───────────────────────────────
                if (isCollecting) ...[
                  _InviteCodeCard(
                    group: group,
                    onCopy: () => _copyCode(group),
                    onShare: () => _shareInvite(group),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Deadline ───────────────────────────────────────
                if (group.deadline != null) ...[
                  _InfoTile(
                    icon: Icons.timer_outlined,
                    label: 'Deadline',
                    value: fmt.format(group.deadline!),
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Add Items Button (during collecting) ───────────
                if (isCollecting) ...[
                  _AddItemsButton(
                    groupOrderId: widget.groupOrderId,
                    restaurantId: group.restaurantId,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Participants ───────────────────────────────────
                Text(
                  'Participants (${group.participants.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ...group.participants.map(
                  (p) => _ParticipantTile(
                    participant: p,
                    isCurrentUser: p.userId == currentUserId,
                  ),
                ),

                // ── Total ──────────────────────────────────────────
                if (group.totalAmount > 0) ...[
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Group Total',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${AppConstants.currencySymbol}${group.totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
      // Bottom action bar for host
      bottomNavigationBar: groupAsync.whenData((group) {
        if (group == null) return null;
        final isHost = group.hostUserId == currentUserId;
        final isCollecting = group.status == 'collecting';

        if (!isHost || !isCollecting) return null;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                // Cancel
                OutlinedButton(
                  onPressed: _cancelling ? null : () => _cancelGroup(group!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _cancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                // Lock & Checkout
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _locking ? null : () => _lockGroup(group!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: _locking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_outline, size: 18),
                    label: const Text(
                      'Lock & Checkout',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).valueOrNull,
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final GroupOrder group;
  final bool isHost;

  const _StatusHeader({required this.group, required this.isHost});

  Color get _statusColor {
    switch (group.status) {
      case 'collecting':
        return const Color(0xFF10B981);
      case 'locked':
        return const Color(0xFF6366F1);
      case 'ordered':
        return AppTheme.primaryColor;
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  group.status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'You\'re the host',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            group.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (group.deliveryAddress != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    group.deliveryAddress!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  final GroupOrder group;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _InviteCodeCard({
    required this.group,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.group_add_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Invite Friends',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  group.inviteCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopy,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onShare,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text(
                    'Share',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddItemsButton extends ConsumerWidget {
  final String groupOrderId;
  final String restaurantId;

  const _AddItemsButton({
    required this.groupOrderId,
    required this.restaurantId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        // Fetch the restaurant and navigate to its detail screen
        try {
          final data = await ref
              .read(restaurantByIdProvider(restaurantId).future);
          if (data != null && context.mounted) {
            Navigator.pushNamed(
              context,
              '/restaurant-detail',
              arguments: data,
            );
          }
        } catch (_) {
          if (context.mounted) {
            AppSnackbar.error(context, 'Could not open restaurant menu');
          }
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: BorderSide(color: AppTheme.primaryColor),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(double.infinity, 0),
      ),
      icon: const Icon(Icons.add_shopping_cart_rounded),
      label: const Text(
        'Add My Items',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final GroupOrderParticipant participant;
  final bool isCurrentUser;

  const _ParticipantTile({
    required this.participant,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final name = participant.userName ??
        (isCurrentUser ? 'You' : 'Guest');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppTheme.primaryColor.withValues(alpha: 0.04)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (participant.items.isNotEmpty)
                  Text(
                    '${participant.items.length} item${participant.items.length != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    'No items added yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (participant.subtotal > 0)
            Text(
              '${AppConstants.currencySymbol}${participant.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
