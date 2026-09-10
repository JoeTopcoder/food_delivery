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
    final chatsAsync = ref.watch(filteredChatSummariesProvider);
    final issuesAsync = ref.watch(allIssuesProvider);
    final filter = ref.watch(adminChatFilterProvider);
    final openCount = ref.watch(openChatCountProvider).valueOrNull;

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
      body: Column(
        children: [
          _FilterBar(
            selected: filter,
            openCount: openCount,
            onSelected: (f) =>
                ref.read(adminChatFilterProvider.notifier).state = f,
          ),
          Expanded(
            child: chatsAsync.when(
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
                        Text(
                          switch (filter) {
                            ChatFilter.open => 'No open chats',
                            ChatFilter.closed => 'No closed chats',
                            ChatFilter.all => 'No chats yet',
                          },
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          switch (filter) {
                            ChatFilter.open =>
                              'Everything has been dealt with.',
                            ChatFilter.closed =>
                              'Chats you close will appear here.',
                            ChatFilter.all =>
                              'Customer support chats will appear here',
                          },
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                      final conversationId = (chat['id'] as String?) ?? '';
                      final closedAt = chat['closed_at'] as String?;
                      final closeReason = chat['close_reason'] as String?;

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
                        isClosed: closedAt != null,
                        closeReason: closeReason,
                        // A conversation with no id predates the conversations table
                        // and can only be reached through chat_messages, so there is
                        // nothing for the RPC to close.
                        onClose: conversationId.isEmpty
                            ? null
                            : () => _close(context, ref, conversationId),
                        onReopen: conversationId.isEmpty
                            ? null
                            : () => _reopen(context, ref, conversationId),
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/chat',
                          arguments: {
                            'orderId': orderId,
                            'otherPartyName':
                                'Order #${orderId.length >= 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()}',
                            'receiverId': customerId.isEmpty
                                ? null
                                : customerId,
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Closes a chat, then offers an immediate undo. Support staff work fast and
  /// a mis-tap on the wrong row should cost a tap to fix, not a hunt through
  /// the closed list.
  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    String conversationId,
  ) async {
    // Captured before the await: reaching for the messenger after the dialog
    // closes is a BuildContext used across an async gap.
    final messenger = ScaffoldMessenger.of(context);

    final reason = await showDialog<String?>(
      context: context,
      builder: (_) => const _CloseReasonDialog(),
    );
    // null means the dialog was dismissed; an empty string means "close, no
    // reason given". They are different answers and must not be conflated.
    if (reason == null) return;
    try {
      await ref
          .read(chatServiceProvider)
          .closeConversation(conversationId, reason: reason);
      ref.invalidate(allChatSummariesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Chat closed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await ref
                  .read(chatServiceProvider)
                  .reopenConversation(conversationId);
              ref.invalidate(allChatSummariesProvider);
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _reopen(
    BuildContext context,
    WidgetRef ref,
    String conversationId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatServiceProvider).reopenConversation(conversationId);
      ref.invalidate(allChatSummariesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Chat reopened')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Open / Closed / All, with the open count on the chip so the size of the
/// queue is visible without switching.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.openCount,
    required this.onSelected,
  });

  final ChatFilter selected;
  final int? openCount;
  final ValueChanged<ChatFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (final f in ChatFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  f == ChatFilter.open && openCount != null
                      ? '${f.label} ($openCount)'
                      : f.label,
                ),
                selected: f == selected,
                onSelected: (_) => onSelected(f),
                backgroundColor: const Color(0xFF1E2030),
                selectedColor: AppTheme.primaryColor,
                labelStyle: TextStyle(
                  color: f == selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
                side: const BorderSide(color: Color(0xFF2A2D3E)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks for an optional reason. Returns null if dismissed, or the reason
/// (possibly empty) if the admin confirmed.
class _CloseReasonDialog extends StatefulWidget {
  const _CloseReasonDialog();

  @override
  State<_CloseReasonDialog> createState() => _CloseReasonDialogState();
}

class _CloseReasonDialogState extends State<_CloseReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2030),
      title: const Text(
        'Close this chat?',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'If the customer writes again it reopens automatically.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            // The app's global input theme fills fields with white, which on
            // this dark dialog rendered as a blank white block with the label
            // invisible inside it. fillColor has to be set explicitly here.
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF161824),
              hintText: 'Reason (optional)',
              hintStyle: TextStyle(color: Colors.white38),
              counterStyle: TextStyle(color: Colors.white38),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2D3E)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF155EEF)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Close chat'),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String orderId;
  final String lastMessage;
  final String senderRole;
  final DateTime time;
  final bool hasOpenIssue;
  final bool isClosed;
  final String? closeReason;
  final VoidCallback? onClose;
  final VoidCallback? onReopen;
  final VoidCallback onTap;

  const _ChatTile({
    required this.orderId,
    required this.lastMessage,
    required this.senderRole,
    required this.time,
    required this.hasOpenIssue,
    required this.isClosed,
    required this.closeReason,
    required this.onClose,
    required this.onReopen,
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
          // A closed chat is dimmed rather than hidden, so in the All listing
          // the ones still needing attention are the ones that stand out.
          color: isClosed
              ? const Color(0xFF1E2030).withValues(alpha: 0.55)
              : const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isClosed
                ? const Color(0xFF2A2D3E)
                : hasOpenIssue
                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                : const Color(0xFF2A2D3E),
            width: hasOpenIssue && !isClosed ? 1.5 : 1,
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
                      if (isClosed) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4B5563),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CLOSED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (hasOpenIssue && !isClosed) ...[
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
                  if (isClosed &&
                      closeReason != null &&
                      closeReason!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Closed: $closeReason',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
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
            if (onClose == null && onReopen == null)
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF4B5563))
            else
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF9CA3AF),
                ),
                color: const Color(0xFF1E2030),
                onSelected: (v) {
                  if (v == 'close') onClose?.call();
                  if (v == 'reopen') onReopen?.call();
                },
                itemBuilder: (_) => [
                  if (!isClosed)
                    const PopupMenuItem(
                      value: 'close',
                      child: Text(
                        'Close chat',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  else
                    const PopupMenuItem(
                      value: 'reopen',
                      child: Text(
                        'Reopen chat',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
