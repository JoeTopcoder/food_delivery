import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/chat_provider.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminChatsPage extends ConsumerWidget {
  const WebAdminChatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(allChatSummariesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support Chats', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Customer and driver support conversations', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(allChatSummariesProvider),
              ),
            ],
          ),
          const SizedBox(height: 28),

          chatsAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allChatSummariesProvider)),
            data: (chats) {
              if (chats.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No support chats yet'),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: const Row(children: [
                        Expanded(flex: 2, child: Text('Order ID', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 3, child: Text('Last Message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Sender Role', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        SizedBox(width: 60, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...chats.asMap().entries.map((e) {
                      final i = e.key;
                      final chat = e.value;
                      final orderId = (chat['order_id'] as String?) ?? (chat['conversation_id'] as String?) ?? '-';
                      final lastMsg = (chat['last_message_text'] as String?) ?? (chat['message'] as String?) ?? '';
                      final role = (chat['sender_role'] as String?) ?? '';
                      final createdAt = DateTime.tryParse(
                        (chat['last_message_at'] as String?) ?? (chat['created_at'] as String?) ?? '',
                      );
                      final isLast = i == chats.length - 1;
                      final hasIssue = chat['has_open_issue'] == true;

                      return Container(
                        decoration: BoxDecoration(
                          color: hasIssue ? const Color(0xFFFFF7ED) : null,
                          border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(children: [
                            Expanded(flex: 2, child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.chat_bubble_rounded, size: 14, color: Color(0xFFEF4444)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  orderId.length > 8 ? '…${orderId.substring(orderId.length - 8)}' : orderId,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF475569)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ])),
                            Expanded(flex: 3, child: Text(
                              lastMsg,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                            )),
                            Expanded(flex: 2, child: _RoleBadge(role: role)),
                            Expanded(flex: 2, child: Text(
                              createdAt != null ? DateFormat('MMM d, h:mm a').format(createdAt.toLocal()) : '-',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            )),
                            SizedBox(width: 60, child: hasIssue
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFFCD34D)),
                                  ),
                                  child: const Text('Issue', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                                )
                              : const SizedBox()),
                          ]),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (role) {
      'customer' => (const Color(0xFF6366F1), const Color(0xFFEEF2FF)),
      'driver'   => (const Color(0xFF10B981), const Color(0xFFECFDF5)),
      'admin'    => (const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
      _          => (const Color(0xFF94A3B8), const Color(0xFFF1F5F9)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        role.isEmpty ? 'Unknown' : role[0].toUpperCase() + role.substring(1),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
