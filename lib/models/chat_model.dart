// ─── Message Types ──────────────────────────────────────────────────────────

enum MessageType { text, image, system, callEvent }

extension MessageTypeExt on MessageType {
  String get value {
    switch (this) {
      case MessageType.text:
        return 'text';
      case MessageType.image:
        return 'image';
      case MessageType.system:
        return 'system';
      case MessageType.callEvent:
        return 'call_event';
    }
  }

  static MessageType fromString(String s) {
    switch (s) {
      case 'image':
        return MessageType.image;
      case 'system':
        return MessageType.system;
      case 'call_event':
        return MessageType.callEvent;
      default:
        return MessageType.text;
    }
  }
}

// ─── Message Status ─────────────────────────────────────────────────────────

enum MessageStatus { sent, delivered, seen }

extension MessageStatusExt on MessageStatus {
  String get value {
    switch (this) {
      case MessageStatus.sent:
        return 'sent';
      case MessageStatus.delivered:
        return 'delivered';
      case MessageStatus.seen:
        return 'seen';
    }
  }

  static MessageStatus fromString(String s) {
    switch (s) {
      case 'delivered':
        return MessageStatus.delivered;
      case 'seen':
        return MessageStatus.seen;
      default:
        return MessageStatus.sent;
    }
  }
}

// ─── ChatMessage ────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String orderId;
  final String? conversationId;
  final String senderId;
  final String senderRole; // 'user' | 'driver' | 'restaurant' | 'admin'
  final String message;
  final MessageType messageType;
  final MessageStatus status;
  final bool isRead;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.orderId,
    this.conversationId,
    required this.senderId,
    required this.senderRole,
    required this.message,
    this.messageType = MessageType.text,
    this.status = MessageStatus.sent,
    required this.isRead,
    this.metadata = const {},
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    conversationId: json['conversation_id'] as String?,
    senderId: json['sender_id'] as String,
    senderRole: json['sender_role'] as String,
    message: json['message'] as String? ?? '',
    messageType: MessageTypeExt.fromString(
      json['message_type'] as String? ?? 'text',
    ),
    status: MessageStatusExt.fromString(json['status'] as String? ?? 'sent'),
    isRead: json['is_read'] as bool? ?? false,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'sender_role': senderRole,
    'message': message,
    'message_type': messageType.value,
    'status': status.value,
    'is_read': isRead,
    'metadata': metadata,
    'created_at': createdAt.toIso8601String(),
  };
}

// ─── Conversation ───────────────────────────────────────────────────────────

class Conversation {
  final String id;
  final String orderId;
  final List<String> participantIds;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.orderId,
    required this.participantIds,
    this.lastMessageText,
    this.lastMessageAt,
    required this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    participantIds:
        (json['participant_ids'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    lastMessageText: json['last_message_text'] as String?,
    lastMessageAt: json['last_message_at'] != null
        ? DateTime.parse(json['last_message_at'] as String)
        : null,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

// ─── Call Status ────────────────────────────────────────────────────────────

enum CallStatus { ringing, accepted, ended, missed, declined, failed }

extension CallStatusExt on CallStatus {
  String get value {
    switch (this) {
      case CallStatus.ringing:
        return 'ringing';
      case CallStatus.accepted:
        return 'accepted';
      case CallStatus.ended:
        return 'ended';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.declined:
        return 'declined';
      case CallStatus.failed:
        return 'failed';
    }
  }

  static CallStatus fromString(String s) {
    switch (s) {
      case 'accepted':
        return CallStatus.accepted;
      case 'ended':
        return CallStatus.ended;
      case 'missed':
        return CallStatus.missed;
      case 'declined':
        return CallStatus.declined;
      case 'failed':
        return CallStatus.failed;
      default:
        return CallStatus.ringing;
    }
  }
}

// ─── Call Model ─────────────────────────────────────────────────────────────

class CallRecord {
  final String id;
  final String? orderId;
  final String? conversationId;
  final String callerId;
  final String receiverId;
  final String channelName;
  final String? agoraToken;
  final CallStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final DateTime createdAt;

  const CallRecord({
    required this.id,
    this.orderId,
    this.conversationId,
    required this.callerId,
    required this.receiverId,
    required this.channelName,
    this.agoraToken,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    required this.createdAt,
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
    id: json['id'] as String,
    orderId: json['order_id'] as String?,
    conversationId: json['conversation_id'] as String?,
    callerId: json['caller_id'] as String,
    receiverId: json['receiver_id'] as String,
    channelName: json['channel_name'] as String,
    agoraToken: json['agora_token'] as String?,
    status: CallStatusExt.fromString(json['status'] as String? ?? 'ringing'),
    startedAt: json['started_at'] != null
        ? DateTime.parse(json['started_at'] as String)
        : null,
    endedAt: json['ended_at'] != null
        ? DateTime.parse(json['ended_at'] as String)
        : null,
    durationSeconds: json['duration_seconds'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  CallRecord copyWith({String? agoraToken}) => CallRecord(
    id: id,
    orderId: orderId,
    conversationId: conversationId,
    callerId: callerId,
    receiverId: receiverId,
    channelName: channelName,
    agoraToken: agoraToken ?? this.agoraToken,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

class OrderIssue {
  final String id;
  final String orderId;
  final String userId;
  final String
  issueType; // 'missing_item' | 'wrong_item' | 'quality' | 'delivery' | 'other'
  final String description;
  final String status; // 'open' | 'in_review' | 'resolved'
  final DateTime createdAt;

  const OrderIssue({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.issueType,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory OrderIssue.fromJson(Map<String, dynamic> json) => OrderIssue(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    userId: json['user_id'] as String,
    issueType: json['issue_type'] as String,
    description: json['description'] as String,
    status: json['status'] as String? ?? 'open',
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
