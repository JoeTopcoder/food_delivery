import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';

class AdminChatsScreen extends ConsumerWidget {
  const AdminChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminId = ref.watch(currentUserIdProvider) ?? '';
    final chatsAsync = ref.watch(allChatSummariesProvider);
    final issuesAsync = ref.watch(allIssuesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: const Text(
          'Support Chats',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E2030),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: chatsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
        error: (e, _) => Center(
          child: Text(
            friendlyError(e),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 56,
                    color: Color(0xFF4B5563),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No chats yet',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Customer support chats will appear here',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          final openIssueOrderIds = <String>{};
          issuesAsync.whenData((issues) {
            for (final issue in issues) {
              if (issue.status == 'open') {
                openIssueOrderIds.add(issue.orderId);
              }
            }
          });

          return RefreshIndicator(
            color: AppTheme.primaryColor,
            backgroundColor: const Color(0xFF1E2030),
            onRefresh: () async {
              ref.invalidate(allChatSummariesProvider);
              ref.invalidate(allIssuesProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                // Support both conversations table format and legacy format
                final orderId = (chat['order_id'] as String?) ?? '';
                final lastMsg =
                    (chat['last_message_text'] as String?) ??
                    (chat['message'] as String?) ??
                    '';
                final role = (chat['sender_role'] as String?) ?? '';
                final createdAt =
                    DateTime.tryParse(
                      (chat['last_message_at'] as String?) ??
                          (chat['created_at'] as String?) ??
                          '',
                    ) ??
                    DateTime.now();
                final hasOpenIssue = openIssueOrderIds.contains(orderId);

                // Determine the customer's user ID from participant_ids
                final participantIds =
                    (chat['participant_ids'] as List<dynamic>? ?? [])
                        .map((e) => e as String)
                        .toList();
                final customerId = participantIds.firstWhere(
                  (id) => id != adminId,
                  orElse: () => '',
                );

                return _ChatTile(
                  orderId: orderId,
                  lastMessage: lastMsg,
                  senderRole: role,
                  time: createdAt,
                  hasOpenIssue: hasOpenIssue,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/chat',
                    arguments: {
                      'orderId': orderId,
                      'otherPartyName':
                          'Order #${orderId.length >= 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()}',
                      'receiverId': customerId.isEmpty ? null : customerId,
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String orderId;
  final String lastMessage;
  final String senderRole;
  final DateTime time;
  final bool hasOpenIssue;
  final VoidCallback onTap;

  const _ChatTile({
    required this.orderId,
    required this.lastMessage,
    required this.senderRole,
    required this.time,
    required this.hasOpenIssue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · h:mm a');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasOpenIssue
                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                : const Color(0xFF2A2D3E),
            width: hasOpenIssue ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasOpenIssue
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : AppTheme.primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasOpenIssue
                    ? Icons.warning_amber_rounded
                    : Icons.chat_bubble_rounded,
                color: hasOpenIssue
                    ? const Color(0xFFEF4444)
                    : AppTheme.primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Order #${orderId.length >= 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      if (hasOpenIssue) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ISSUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    senderRole.isNotEmpty
                        ? '${senderRole[0].toUpperCase()}${senderRole.substring(1)}: $lastMessage'
                        : lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fmt.format(time),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF4B5563)),
          ],
        ),
      ),
    );
  }
}
