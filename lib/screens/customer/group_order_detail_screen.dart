import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/group_order_model.dart';
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

      // Load all participants' items combined into the cart
      final cartNotifier = ref.read(cartProvider.notifier);
      cartNotifier.clearCart();
      for (final participant in group.participants) {
        for (final itemJson in participant.items) {
          try {
            final cartItem = CartItem.fromJson(
              itemJson as Map<String, dynamic>,
            );
            for (int i = 0; i < cartItem.quantity; i++) {
              cartNotifier.addItem(
                cartItem.menuItem,
                sides: cartItem.selectedSides,
                options: cartItem.selectedOptions,
              );
            }
          } catch (_) {
            // Skip malformed items
          }
        }
      }

      if (!mounted) return;

      // Set group metadata so cart + checkout apply 60% delivery discount
      // and checkout knows to mark this group order as 'ordered' on success.
      ref.read(groupOrderParticipantCountProvider.notifier).state =
          group.participants.length;
      ref.read(groupOrderIdForCheckoutProvider.notifier).state =
          widget.groupOrderId;

      // Navigate to cart → checkout (full payment flow).
      // markAsOrdered is triggered inside CheckoutScreen on payment success.
      await Navigator.pushNamed(context, '/cart');

      // Clear the group discount / id flags when user returns (either after
      // placing the order or cancelling before checkout).
      ref.read(groupOrderParticipantCountProvider.notifier).state = 0;
      ref.read(groupOrderIdForCheckoutProvider.notifier).state = null;

      if (!mounted) return;
      await _refresh();
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

  String _inviteLink(GroupOrder group) =>
      'https://mealhub.app/join-group/${group.inviteCode}';

  void _shareInvite(GroupOrder group) {
    final link = _inviteLink(group);
    Share.share(
      '🍽️ Join my group order "${group.name}" on MealHub!\n\n'
      'Tap the link to join instantly:\n$link\n\n'
      'Or open MealHub → Group Orders → Join → enter code: ${group.inviteCode}',
      subject: 'Join my MealHub group order!',
    );
  }

  void _showQrDialog(GroupOrder group) {
    final link = _inviteLink(group);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan to Join',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                group.name,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF1A1A2E),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  group.inviteCode,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Code expires when order is locked',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        Navigator.pop(ctx);
                        AppSnackbar.success(context, 'Link copied!');
                      },
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy Link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _shareInvite(group);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
        error: (e, _) =>
            AppErrorState(message: friendlyError(e), onRetry: _refresh),
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
                    onQr: () => _showQrDialog(group),
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
                  Builder(
                    builder: (context) {
                      // Find this user's participant record
                      final myParticipant = group.participants
                          .where((p) => p.userId == currentUserId)
                          .firstOrNull;

                      if (myParticipant == null) {
                        // User hasn't joined yet — shouldn't normally happen
                        // but show a friendly message just in case
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Join this group order to add items.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.orange),
                          ),
                        );
                      }

                      return _AddItemsButton(
                        groupOrderId: widget.groupOrderId,
                        restaurantId: group.restaurantId,
                        participantId: myParticipant.id,
                      );
                    },
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
                  onPressed: _cancelling ? null : () => _cancelGroup(group),
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
                    onPressed: _locking ? null : () => _lockGroup(group),
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
        return const Color(0xFF6B7280); // grey — closed
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
  final VoidCallback onQr;

  const _InviteCodeCard({
    required this.group,
    required this.onCopy,
    required this.onShare,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withValues(alpha: 0.75),
          ],
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
          const SizedBox(height: 10),
          // QR code button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onQr,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.qr_code_rounded, size: 16),
              label: const Text('Show QR Code'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddItemsButton extends ConsumerWidget {
  final String groupOrderId;
  final String restaurantId;
  final String participantId;

  const _AddItemsButton({
    required this.groupOrderId,
    required this.restaurantId,
    required this.participantId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        try {
          final data = await ref.read(
            restaurantByIdProvider(restaurantId).future,
          );
          if (data != null && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RestaurantDetailScreen(
                  restaurant: data,
                  groupOrderId: groupOrderId,
                  groupParticipantId: participantId,
                ),
              ),
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

class _ParticipantTile extends StatefulWidget {
  final GroupOrderParticipant participant;
  final bool isCurrentUser;

  const _ParticipantTile({
    required this.participant,
    required this.isCurrentUser,
  });

  @override
  State<_ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<_ParticipantTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final name =
        widget.participant.userName ?? (widget.isCurrentUser ? 'You' : 'Guest');
    final hasItems = widget.participant.items.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.isCurrentUser
            ? AppTheme.primaryColor.withValues(alpha: 0.04)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isCurrentUser
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: hasItems
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryColor.withValues(
                      alpha: 0.12,
                    ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.isCurrentUser) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
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
                        Text(
                          hasItems
                              ? '${widget.participant.items.length} item${widget.participant.items.length != 1 ? 's' : ''}'
                              : 'No items added yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontStyle: hasItems
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.participant.subtotal > 0)
                    Text(
                      '${AppConstants.currencySymbol}${widget.participant.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  if (hasItems) ...[
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── Expanded item list ────────────────────────────────────
          if (_expanded && hasItems) ...[
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: widget.participant.items.map((itemJson) {
                  // Try to parse the item name / price from stored JSON
                  try {
                    final json = itemJson as Map<String, dynamic>;
                    final menuItem =
                        json['menuItem'] as Map<String, dynamic>? ?? json;
                    final itemName = menuItem['name'] as String? ?? 'Item';
                    final qty = json['quantity'] as int? ?? 1;
                    final price =
                        (menuItem['price'] as num?)?.toDouble() ?? 0.0;
                    final sides =
                        (json['selectedSides'] as List?)
                            ?.map(
                              (s) =>
                                  (s as Map<String, dynamic>)['name']
                                      as String? ??
                                  '',
                            )
                            .where((s) => s.isNotEmpty)
                            .toList() ??
                        [];
                    final options =
                        (json['selectedOptions'] as Map<String, dynamic>?)
                            ?.values
                            .expand(
                              (choices) => (choices as List).map(
                                (c) =>
                                    (c as Map<String, dynamic>)['name']
                                        as String? ??
                                    '',
                              ),
                            )
                            .where((s) => s.isNotEmpty)
                            .toList() ??
                        [];
                    final extras = [...sides, ...options];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '$qty',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (extras.isNotEmpty)
                                  Text(
                                    extras.join(', '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (price > 0)
                            Text(
                              '${AppConstants.currencySymbol}${(price * qty).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                }).toList(),
              ),
            ),
          ],
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
