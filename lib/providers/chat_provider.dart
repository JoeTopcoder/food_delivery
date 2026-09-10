import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../services/social/chat_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(Supabase.instance.client);
});

/// Key for chatMessagesProvider — supply either orderId or rideId.
typedef ChatKey = ({String? orderId, String? rideId});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, ChatKey>((
  ref,
  key,
) {
  return ref
      .watch(chatServiceProvider)
      .watchMessages(orderId: key.orderId, rideId: key.rideId);
});

// Conversation for a specific order
final conversationForOrderProvider =
    FutureProvider.family<Conversation?, String>((ref, orderId) {
      return ref.watch(chatServiceProvider).getConversationForOrder(orderId);
    });

// All conversations stream (for admin / inbox)
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatServiceProvider).watchConversations();
});

// Typing indicators for a conversation
final typingIndicatorsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      conversationId,
    ) {
      return ref.watch(chatServiceProvider).watchTyping(conversationId);
    });

// Active calls for the current user
final activeCallsProvider = StreamProvider.family<List<CallRecord>, String>((
  ref,
  userId,
) {
  return ref.watch(chatServiceProvider).watchActiveCalls(userId);
});

final orderIssuesProvider = FutureProvider.family<List<OrderIssue>, String>((
  ref,
  orderId,
) {
  return ref.watch(chatServiceProvider).getIssues(orderId: orderId);
});

/// All issues (admin)
final allIssuesProvider = FutureProvider.autoDispose<List<OrderIssue>>((ref) {
  return ref.watch(chatServiceProvider).getAllIssues();
});

/// All chat summaries for admin (order_id + latest message)
final allChatSummariesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(chatServiceProvider).getAllChatSummaries();
    });

/// Which chats the admin list is showing. Open by default: a support queue is
/// a list of things still needing attention, and closed chats would bury them.
enum ChatFilter {
  open('Open'),
  closed('Closed'),
  all('All');

  const ChatFilter(this.label);
  final String label;
}

final adminChatFilterProvider = StateProvider<ChatFilter>(
  (ref) => ChatFilter.open,
);

/// Chat summaries narrowed by the filter.
///
/// A conversation is closed when it has a closed_at, so there is no status
/// string that could disagree with the timestamp.
final filteredChatSummariesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final all = await ref.watch(allChatSummariesProvider.future);
      final filter = ref.watch(adminChatFilterProvider);
      bool isClosed(Map<String, dynamic> c) => c['closed_at'] != null;
      return switch (filter) {
        ChatFilter.open => all.where((c) => !isClosed(c)).toList(),
        ChatFilter.closed => all.where(isClosed).toList(),
        ChatFilter.all => all,
      };
    });

/// How many chats are still open — shown on the filter chip so the size of the
/// queue is visible without switching tabs.
final openChatCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final all = await ref.watch(allChatSummariesProvider.future);
  return all.where((c) => c['closed_at'] == null).length;
});
