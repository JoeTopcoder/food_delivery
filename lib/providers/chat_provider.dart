import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(Supabase.instance.client);
});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  orderId,
) {
  return ref.watch(chatServiceProvider).watchMessages(orderId);
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
