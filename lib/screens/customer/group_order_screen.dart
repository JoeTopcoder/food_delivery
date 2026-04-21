import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/group_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';
import 'group_order_detail_screen.dart';

class GroupOrderScreen extends ConsumerStatefulWidget {
  const GroupOrderScreen({super.key});

  @override
  ConsumerState<GroupOrderScreen> createState() => _GroupOrderScreenState();
}

class _GroupOrderScreenState extends ConsumerState<GroupOrderScreen> {
  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }
    final groupOrdersAsync = ref.watch(userGroupOrdersProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.groupOrders,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => _showJoinDialog(userId),
            tooltip: 'Join with code',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showCreateDialog(userId),
        icon: const Icon(Icons.group_add, color: Colors.white),
        label: const Text('New Group', style: TextStyle(color: Colors.white)),
      ),
      body: groupOrdersAsync.when(
        loading: () =>
            const AppLoadingIndicator(message: 'Loading group orders...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(userGroupOrdersProvider(userId)),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return const AppEmptyState(
              icon: Icons.groups_rounded,
              title: 'No group orders yet',
              subtitle: 'Create one or join with an invite code',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupOrderDetailScreen(
                      groupOrderId: groups[i].id,
                    ),
                  ),
                ).then((_) => ref.invalidate(userGroupOrdersProvider(userId)));
              },
              child: _GroupOrderCard(
                group: groups[i],
                currentUserId: userId,
                onRefresh: () => ref.invalidate(userGroupOrdersProvider(userId)),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(String userId) {
    AppSnackbar.info(
      context,
      'Open a restaurant menu first, then tap "Start Group Order"',
    );
  }

  void _showJoinDialog(String userId) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Group Order'),
        content: TextField(
          controller: codeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Invite Code',
            hintText: 'Enter 6-character code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final service = ref.read(groupOrderServiceProvider);
              final result = await service.joinByCode(
                inviteCode: codeCtrl.text.trim(),
                userId: userId,
              );
              if (result != null) {
                ref.invalidate(userGroupOrdersProvider(userId));
                if (mounted) {
                  AppSnackbar.success(context, 'Joined: ${result.name}');
                }
              } else {
                if (mounted) {
                  AppSnackbar.error(context, 'Invalid or expired invite code');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Join', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Group Order Card ────────────────────────────────────────

class _GroupOrderCard extends StatelessWidget {
  final GroupOrder group;
  final String currentUserId;
  final VoidCallback onRefresh;

  const _GroupOrderCard({
    required this.group,
    required this.currentUserId,
    required this.onRefresh,
  });

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
    final isHost = group.hostUserId == currentUserId;
    final fmt = DateFormat('MMM d, h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    group.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                if (isHost) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'HOST',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  fmt.format(group.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              group.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${group.participants.length} participants',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: group.inviteCode));
                    AppSnackbar.success(context, 'Invite code copied!');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.content_copy,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          group.inviteCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (group.totalAmount > 0)
                  Text(
                    '${AppConstants.currencySymbol}${group.totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (group.deadline != null) ...[
              const SizedBox(height: 6),
              Text(
                'Deadline: ${fmt.format(group.deadline!)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
