import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/chat_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? orderId;
  final String? rideId;
  final String otherPartyName;
  final String? receiverId;
  const ChatScreen({
    super.key,
    this.orderId,
    this.rideId,
    required this.otherPartyName,
    this.receiverId,
  }) : assert(orderId != null || rideId != null);

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _typingTimer;
  String? _conversationId;
  bool _markedRead = false;

  bool get _isRide => widget.rideId != null;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    final svc = ref.read(chatServiceProvider);
    final conv = _isRide
        ? await svc.getConversationForRide(widget.rideId!)
        : await svc.getConversationForOrder(widget.orderId!);
    if (conv != null && mounted) {
      setState(() => _conversationId = conv.id);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _typingTimer?.cancel();
    if (_conversationId != null) {
      ref.read(chatServiceProvider).setTyping(_conversationId!, false);
    }
    super.dispose();
  }

  void _markReadOnce() {
    if (_markedRead) return;
    _markedRead = true;
    final userId = ref.read(currentUserIdProvider) ?? '';
    if (userId.isEmpty) return;
    final svc = ref.read(chatServiceProvider);
    if (_isRide) {
      svc.markRideRead(widget.rideId!, userId);
    } else {
      svc.markRead(widget.orderId!, userId);
    }
  }

  void _onTextChanged(String _) {
    if (_conversationId == null) return;
    final svc = ref.read(chatServiceProvider);
    svc.setTyping(_conversationId!, true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      svc.setTyping(_conversationId!, false);
    });
  }

  Future<void> _send(String userId, String role) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    final service = ref.read(chatServiceProvider);
    if (_conversationId != null) {
      service.setTyping(_conversationId!, false);
    }
    _typingTimer?.cancel();
    if (_isRide) {
      await service.sendRideMessage(
        rideId: widget.rideId!,
        senderId: userId,
        senderRole: role,
        message: text,
      );
    } else {
      await service.sendMessage(
        orderId: widget.orderId!,
        senderId: userId,
        senderRole: role,
        message: text,
      );
    }
    _scrollDown();
    if (_conversationId == null) _loadConversation();
  }

  Future<void> _startCall() async {
    if (widget.receiverId == null || widget.receiverId!.isEmpty) {
      AppSnackbar.warning(context, 'Cannot call — no participant found');
      return;
    }
    try {
      final call = await ref
          .read(chatServiceProvider)
          .initiateCall(
            orderId: widget.rideId ?? widget.orderId!,
            receiverId: widget.receiverId!,
          );
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/call',
          arguments: {
            'call': call,
            'isCaller': true,
            'otherPartyName': widget.otherPartyName,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0, // With reverse: true, 0 is the bottom (newest messages)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final role = ref.watch(currentUserProvider)?.role ?? 'user';
    final msgsAsync = _isRide
        ? ref.watch(rideMessagesProvider(widget.rideId!))
        : ref.watch(chatMessagesProvider(widget.orderId!));

    // Auto-scroll to bottom when new messages arrive
    if (_isRide) {
      ref.listen(rideMessagesProvider(widget.rideId!), (prev, next) {
        final oldLen = prev?.valueOrNull?.length ?? 0;
        final newLen = next.valueOrNull?.length ?? 0;
        if (newLen > oldLen) _scrollDown();
      });
    } else {
      ref.listen(chatMessagesProvider(widget.orderId!), (prev, next) {
        final oldLen = prev?.valueOrNull?.length ?? 0;
        final newLen = next.valueOrNull?.length ?? 0;
        if (newLen > oldLen) _scrollDown();
      });
    }

    _markReadOnce();

    final channelId = widget.rideId ?? widget.orderId ?? '';
    final subtitle = _isRide
        ? 'Ride #${channelId.length >= 8 ? channelId.substring(0, 8).toUpperCase() : channelId.toUpperCase()}'
        : 'Order #${channelId.length >= 8 ? channelId.substring(0, 8).toUpperCase() : channelId.toUpperCase()}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherPartyName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E2030),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.receiverId != null && widget.receiverId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call_rounded, color: Color(0xFF22C55E)),
              onPressed: _startCall,
              tooltip: 'Voice Call',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              loading: () =>
                  const AppLoadingIndicator(message: 'Loading messages...'),
              error: (e, _) => AppErrorState(
                message: 'Connection lost',
                icon: Icons.wifi_off_rounded,
                onRetry: () => _isRide
                    ? ref.invalidate(rideMessagesProvider(widget.rideId!))
                    : ref.invalidate(chatMessagesProvider(widget.orderId!)),
              ),
              data: (msgs) {
                if (msgs.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'No messages yet',
                    subtitle: 'Start the conversation!',
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[i];
                    if (msg.messageType == MessageType.system ||
                        msg.messageType == MessageType.callEvent) {
                      return _SystemBubble(msg: msg);
                    }
                    return _Bubble(msg: msg, isMine: msg.senderId == userId);
                  },
                );
              },
            ),
          ),
          // Typing indicator
          if (_conversationId != null)
            _TypingBar(conversationId: _conversationId!, currentUserId: userId),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E2030),
              border: Border(top: BorderSide(color: Color(0xFF2A2D3E))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: _onTextChanged,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0F1117),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A2D3E),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A2D3E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppTheme.primaryColor),
                        ),
                      ),
                      onSubmitted: (_) => _send(userId, role),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _send(userId, role),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Typing Indicator ──────────────────────────────────────────────────────

class _TypingBar extends ConsumerWidget {
  final String conversationId;
  final String currentUserId;
  const _TypingBar({required this.conversationId, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typingAsync = ref.watch(typingIndicatorsProvider(conversationId));
    return typingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (typingUsers) {
        final others = typingUsers
            .where((t) => t['user_id'] != currentUserId)
            .toList();
        if (others.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              _DotAnimation(),
              const SizedBox(width: 8),
              Text(
                'typing...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DotAnimation extends StatefulWidget {
  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final val = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (val + i * 0.2) % 1.0;
            final opacity = (1.0 - (offset - 0.5).abs() * 2).clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── System Bubble ─────────────────────────────────────────────────────────

class _SystemBubble extends StatelessWidget {
  final ChatMessage msg;
  const _SystemBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isCall = msg.messageType == MessageType.callEvent;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCall ? Icons.call_rounded : Icons.info_outline_rounded,
              size: 14,
              color: isCall ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              msg.message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat Bubble ───────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMine;
  const _Bubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(msg.createdAt);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? AppTheme.primaryColor : const Color(0xFF1E2030),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine ? null : Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  msg.senderRole.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Text(
              msg.message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _StatusIcon(status: msg.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Delivery Status Icon ──────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 13, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white54);
      case MessageStatus.seen:
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF60A5FA));
    }
  }
}
