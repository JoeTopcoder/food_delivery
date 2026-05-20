// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ai_voice_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/ai/ai_voice_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../shared/chat_screen.dart';
import '../../models/order_model.dart';

/// Full-screen AI Voice Assistant.
/// Works for all 3 roles: customer, driver, admin.
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => AiVoiceScreen(role: 'customer', orderId: order.id),
/// ));
/// ```
class AiVoiceScreen extends ConsumerStatefulWidget {
  const AiVoiceScreen({
    super.key,
    required this.role,
    this.orderId,
    this.restaurantId,
    this.activeOrders,
  });

  final String role;
  final String? orderId;
  final String? restaurantId;

  /// All non-terminal orders. When >1 and [orderId] is null, the user is
  /// prompted to pick one before the session starts.
  final List<Order>? activeOrders;

  @override
  ConsumerState<AiVoiceScreen> createState() => _AiVoiceScreenState();
}

class _AiVoiceScreenState extends ConsumerState<AiVoiceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveController;
  late final TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();
  bool _showTextInput = false;
  String? _resolvedOrderId; // set when user picks from multi-order list
  bool _orderPicked = false; // true once session has been started

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _textController = TextEditingController();

    // If there's only one (or zero) active orders, start immediately.
    // If there are multiple, wait for the user to pick one.
    final multiOrder =
        (widget.activeOrders?.length ?? 0) > 1 && widget.orderId == null;
    if (!multiOrder) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _startSession(widget.orderId),
      );
    }
  }

  void _startSession(String? orderId) {
    if (_orderPicked) return;
    _orderPicked = true;
    ref
        .read(aiVoiceProvider.notifier)
        .startSession(
          role: widget.role,
          orderId: orderId,
          restaurantId: widget.restaurantId,
        );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiVoiceProvider);

    // Show cancel order picker when AI returns multiple orders
    ref.listen<AiVoiceState>(aiVoiceProvider, (prev, next) {
      if (next.pendingCancelOrders != null &&
          next.pendingCancelOrders != prev?.pendingCancelOrders) {
        _showCancelOrderPicker(context, next.pendingCancelOrders!);
      }

      // Auto-credit wallet for customer when AI issues a credit
      if (widget.role == 'customer' &&
          next.pendingAction != null &&
          next.pendingAction != prev?.pendingAction &&
          next.pendingAction!.type == 'credit_issued' &&
          next.pendingAction!.creditAmount != null &&
          next.pendingAction!.creditAmount! > 0) {
        final amount = next.pendingAction!.creditAmount!;
        final reason = next.pendingAction!.creditReason ?? 'AI credit';
        // Call wallet deposit
        ref
            .read(walletNotifierProvider.notifier)
            .deposit(amount, method: reason);
        // Dismiss the action so it doesn't repeat
        Future.microtask(
          () => ref.read(aiVoiceProvider.notifier).dismissAction(),
        );
      }
    });

    // Auto-scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Show order picker overlay when there are multiple active orders and
    // the user hasn't selected one yet.
    final multiOrders =
        widget.activeOrders != null &&
        widget.activeOrders!.length > 1 &&
        widget.orderId == null &&
        !_orderPicked;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: _buildAppBar(context),
      body: multiOrders
          ? _OrderPickerOverlay(
              orders: widget.activeOrders!,
              onPick: (orderId) {
                setState(() {
                  _resolvedOrderId = orderId;
                });
                _startSession(orderId);
              },
            )
          : SingleChildScrollView(
              child: SizedBox(
                height: MediaQuery.of(context).size.height -
                    AppBar().preferredSize.height -
                    MediaQuery.of(context).padding.top,
                child: Column(
                  children: [
                    // ── Status banner ─────────────────────────────────────────────────
                    _StatusBanner(status: state.status, role: widget.role),

                    // ── Phase 3: Action banner (credit issued, etc.) ──────────────────
                    if (state.pendingAction != null)
                      _ActionBanner(
                        action: state.pendingAction!,
                        onDismiss: () =>
                            ref.read(aiVoiceProvider.notifier).dismissAction(),
                      ),

                    // ── Chat history ──────────────────────────────────────────────────
                    Expanded(
                      child: state.history.isEmpty
                          ? _EmptyStateHint(role: widget.role)
                          : _ChatHistory(
                              messages: state.history,
                              scrollController: _scrollController,
                              onCallDriver: (userId, name) =>
                                  _callDriver(context, userId, name),
                            ),
                    ),

                    // ── Quick reply suggestions (after last AI response) ─────────────
                    if (state.history.isNotEmpty &&
                        !state.history.last.isUser &&
                        state.status == AiVoiceStatus.idle)
                      _QuickReplySuggestions(
                        role: widget.role,
                        lastAiMessage: state.history.last.text,
                        lastUserMessage: state.history
                            .lastWhere(
                              (m) => m.isUser,
                              orElse: () => state.history.last,
                            )
                            .text,
                        onSend: (text) =>
                            ref.read(aiVoiceProvider.notifier).sendText(text),
                      ),

                    // ── Live transcription ────────────────────────────────────────────
                    if (state.status == AiVoiceStatus.listening &&
                        state.transcribedText.isNotEmpty)
                      _TranscriptionBubble(text: state.transcribedText),

                    // ── Processing indicator ──────────────────────────────────────────
                    if (state.status == AiVoiceStatus.processing)
                      const _ThinkingIndicator(),

                    // ── Escalate to support ───────────────────────────────────────────
                    if (state.canEscalate &&
                        (widget.orderId ?? _resolvedOrderId) != null)
                      _EscalateBar(onEscalate: () => _escalateToSupport(context)),

                    // ── Text input (fallback) ─────────────────────────────────────────
                    if (_showTextInput)
                      _TextInputBar(
                        controller: _textController,
                        onSend: () {
                          final text = _textController.text.trim();
                          if (text.isNotEmpty) {
                            ref
                                .read(aiVoiceProvider.notifier)
                                .sendText(text);
                            _textController.clear();
                          }
                        },
                      ),

                    // ── Mic button row ────────────────────────────────────────────────
                    _MicButtonRow(
                      state: state,
                      pulseController: _pulseController,
                      waveController: _waveController,
                      onMicTap: () =>
                          ref.read(aiVoiceProvider.notifier).toggleListening(),
                      onStopSpeaking: () =>
                          ref.read(aiVoiceProvider.notifier).stopSpeaking(),
                      onToggleKeyboard: () =>
                          setState(() => _showTextInput = !_showTextInput),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ), // end SingleChildScrollView (non-picker branch)
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D1A),
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white70),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, Color(0xFF9C27B0)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MealHub AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _roleBadge(widget.role),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38),
          tooltip: 'Clear conversation',
          onPressed: () {
            ref.read(aiVoiceProvider.notifier).clearHistory();
            AppSnackbar.success(context, 'Conversation cleared');
          },
        ),
      ],
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _escalateToSupport(BuildContext context) {
    if (widget.orderId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(orderId: widget.orderId!, otherPartyName: 'Support'),
      ),
    );
  }

  Future<void> _callDriver(
    BuildContext context,
    String driverUserId,
    String driverName,
  ) async {
    final effectiveOrderId = _resolvedOrderId ?? widget.orderId;
    if (effectiveOrderId == null) return;
    try {
      final call = await ref
          .read(chatServiceProvider)
          .initiateCall(orderId: effectiveOrderId, receiverId: driverUserId);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/call',
        arguments: {
          'call': call,
          'isCaller': true,
          'otherPartyName': driverName,
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showCancelOrderPicker(
    BuildContext context,
    List<AiCancelOrder> orders,
  ) {
    ref.read(aiVoiceProvider.notifier).dismissCancelOrders();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E2030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Which order to cancel?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...orders.map(
                  (o) => ListTile(
                    title: Text(
                      'Order #${o.shortId} — ${o.restaurant}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${o.status}  •  \$${o.total.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white54),
                    ),
                    trailing: const Icon(
                      Icons.cancel_outlined,
                      color: Colors.redAccent,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmCancel(context, o);
                    },
                  ),
                ),
                ListTile(
                  title: const Text(
                    'Never mind, keep all orders',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context, AiCancelOrder order) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel Order #${order.shortId}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${order.restaurant}\n\$${order.total.toStringAsFixed(2)}\n\nCancellation within 5 minutes is free. A fee may apply after that.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // Use the full cancelOrder flow (handles card auto-refund,
                // wallet penalty, status update, notifications).
                await ref.read(orderServiceProvider).cancelOrder(order.id);

                // Also run the penalty RPC so wallet-paid orders get
                // a refund back to the wallet when applicable.
                try {
                  await ref
                      .read(walletNotifierProvider.notifier)
                      .cancelOrder(order.id);
                } catch (_) {
                  // Non-fatal – order is already cancelled above
                }

                // Refresh order list so UI reflects the cancellation.
                final userId = ref.read(currentUserIdProvider);
                if (userId != null) {
                  ref.invalidate(userOrdersProvider(userId));
                }

                if (context.mounted) {
                  AppSnackbar.success(
                    context,
                    'Order #${order.shortId} has been cancelled.',
                  );
                  ref
                      .read(aiVoiceProvider.notifier)
                      .sendText(
                        'Order #${order.shortId} has been cancelled successfully.',
                      );
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _roleBadge(String role) {
    switch (role) {
      case 'driver':
        return 'Driver Assistant';
      case 'admin':
        return 'Admin Assistant';
      default:
        return 'Customer Assistant';
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.role});
  final AiVoiceStatus status;
  final String role;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case AiVoiceStatus.listening:
        color = const Color(0xFF10B981);
        label = 'Listening...';
        icon = Icons.mic;
        break;
      case AiVoiceStatus.processing:
        color = AppTheme.primaryColor;
        label = 'Thinking...';
        icon = Icons.psychology_outlined;
        break;
      case AiVoiceStatus.speaking:
        color = const Color(0xFF3B82F6);
        label = 'Speaking...  (tap mic to interrupt)';
        icon = Icons.volume_up_outlined;
        break;
      case AiVoiceStatus.error:
        color = AppTheme.errorColor;
        label = 'Something went wrong. Try again.';
        icon = Icons.warning_amber_outlined;
        break;
      case AiVoiceStatus.requestingPermission:
        color = AppTheme.warningColor;
        label = 'Requesting microphone access...';
        icon = Icons.mic_off_outlined;
        break;
      default:
        color = Colors.white24;
        label = 'Tap the mic to speak';
        icon = Icons.mic_none_outlined;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: color.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHistory extends StatelessWidget {
  const _ChatHistory({
    required this.messages,
    required this.scrollController,
    required this.onCallDriver,
  });
  final List<AiVoiceMessage> messages;
  final ScrollController scrollController;
  final void Function(String userId, String name) onCallDriver;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (_, i) =>
          _MessageBubble(msg: messages[i], onCallDriver: onCallDriver),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.onCallDriver});
  final AiVoiceMessage msg;
  final void Function(String userId, String name) onCallDriver;

  @override
  Widget build(BuildContext context) {
    // ── Driver call card ──────────────────────────────────────────────────
    if (msg.isDriverCallCard) {
      final rawName = msg.driverName ?? 'your driver';
      // Abbreviate: "John Smith" → "John S."
      final parts = rawName.trim().split(RegExp(r'\s+'));
      final displayName = parts.length >= 2
          ? '${parts.first} ${parts.last[0].toUpperCase()}.'
          : parts.first;
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2030),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                color: AppTheme.primaryColor,
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                'Call $displayName',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => onCallDriver(msg.driverUserId!, rawName),
                icon: const Icon(
                  Icons.call_rounded,
                  color: Color(0xFF22C55E),
                  size: 26,
                ),
                tooltip: 'Call driver',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      );
    }

    // ── Regular text bubble ───────────────────────────────────────────────
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isUser
              ? LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF9C27B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser ? null : const Color(0xFF1E2030),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      color: AppTheme.primaryColor,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'MealHub AI',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptionBubble extends StatelessWidget {
  const _TranscriptionBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'AI is thinking...',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MicButtonRow extends StatelessWidget {
  const _MicButtonRow({
    required this.state,
    required this.pulseController,
    required this.waveController,
    required this.onMicTap,
    required this.onStopSpeaking,
    required this.onToggleKeyboard,
  });

  final AiVoiceState state;
  final AnimationController pulseController;
  final AnimationController waveController;
  final VoidCallback onMicTap;
  final VoidCallback onStopSpeaking;
  final VoidCallback onToggleKeyboard;

  @override
  Widget build(BuildContext context) {
    final isListening = state.status == AiVoiceStatus.listening;
    final isSpeaking = state.status == AiVoiceStatus.speaking;
    final isProcessing = state.status == AiVoiceStatus.processing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Keyboard toggle
          _CircleIconBtn(
            icon: Icons.keyboard_outlined,
            color: Colors.white38,
            onTap: onToggleKeyboard,
            size: 44,
          ),
          const SizedBox(width: 24),

          // Main mic / stop button
          GestureDetector(
            onTap: isSpeaking
                ? onStopSpeaking
                : (isProcessing ? null : onMicTap),
            child: AnimatedBuilder(
              animation: pulseController,
              builder: (_, child) {
                final scale = isListening
                    ? 1.0 + 0.08 * pulseController.value
                    : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring when listening
                  if (isListening)
                    AnimatedBuilder(
                      animation: waveController,
                      builder: (_, __) =>
                          _WaveRing(progress: waveController.value),
                    ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isListening
                            ? [const Color(0xFF10B981), const Color(0xFF059669)]
                            : isSpeaking
                            ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                            : [AppTheme.primaryColor, Color(0xFF9C27B0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isListening
                                      ? const Color(0xFF10B981)
                                      : AppTheme.primaryColor)
                                  .withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      isListening
                          ? Icons.mic
                          : isSpeaking
                          ? Icons.stop
                          : isProcessing
                          ? Icons.hourglass_top_rounded
                          : Icons.mic_none,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 24),

          // Volume mute
          _CircleIconBtn(
            icon: isSpeaking
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
            color: isSpeaking ? AppTheme.errorColor : Colors.white38,
            onTap: isSpeaking ? onStopSpeaking : null,
            size: 44,
          ),
        ],
      ),
    );
  }
}

class _WaveRing extends StatelessWidget {
  const _WaveRing({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(110, 110),
      painter: _WaveRingPainter(progress),
    );
  }
}

class _WaveRingPainter extends CustomPainter {
  _WaveRingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = 36.0 + phase * 20;
      final opacity = (1.0 - phase) * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF10B981).withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveRingPainter old) => old.progress != progress;
}

class _CircleIconBtn extends StatelessWidget {
  const _CircleIconBtn({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: size * 0.45),
      ),
    );
  }
}

class _TextInputBar extends StatelessWidget {
  const _TextInputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
            ),
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: AppTheme.primaryColor),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

class _EscalateBar extends StatelessWidget {
  const _EscalateBar({required this.onEscalate});
  final VoidCallback onEscalate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.support_agent,
          color: AppTheme.warningColor,
          size: 20,
        ),
        title: const Text(
          'AI is having trouble. Talk to a real person?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        trailing: TextButton(
          onPressed: onEscalate,
          child: Text(
            'Connect',
            style: TextStyle(
              color: AppTheme.warningColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Phase 3: Action banner (credit issued, etc.) ─────────────────────────────

class _ActionBanner extends StatefulWidget {
  const _ActionBanner({required this.action, required this.onDismiss});

  final AiAction action;
  final VoidCallback onDismiss;

  @override
  State<_ActionBanner> createState() => _ActionBannerState();
}

class _ActionBannerState extends State<_ActionBanner> {
  @override
  void initState() {
    super.initState();
    // Auto-dismiss after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCreditIssued = widget.action.type == 'credit_issued';
    final bgColor = isCreditIssued
        ? const Color(0xFF1B4D2B)
        : const Color(0xFF1A2E4A);
    final iconColor = isCreditIssued
        ? const Color(0xFF4CAF50)
        : const Color(0xFF64B5F6);
    final icon = isCreditIssued ? Icons.wallet_giftcard : Icons.info_outline;

    String message;
    if (isCreditIssued) {
      final amount = widget.action.creditAmount?.toStringAsFixed(2) ?? '0.00';
      message = '\$$amount wallet credit added as an apology for the delay.';
    } else {
      message = widget.action.creditReason ?? 'Action completed.';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: widget.onDismiss,
            child: Icon(Icons.close, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }
}

// ── Order picker shown when the user has multiple active orders ───────────────

class _OrderPickerOverlay extends StatelessWidget {
  const _OrderPickerOverlay({required this.orders, required this.onPick});

  final List<Order> orders;
  final void Function(String orderId) onPick;

  static const _statusLabel = <String, String>{
    'pending': 'Waiting for confirmation',
    'confirmed': 'Confirmed',
    'preparing': 'Being prepared',
    'ready': 'Ready for pickup',
    'picked_up': 'Picked up',
    'on_the_way': 'On the way',
  };

  String _label(String status) => _statusLabel[status] ?? status;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.shopping_bag_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You have multiple active orders.\nWhich one do you need help with?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final order = orders[i];
                  final statusText = _label(order.status);
                  final itemCount = order.items.length;
                  final firstItem = order.items.isNotEmpty
                      ? order.items.first.itemName
                      : 'Order';
                  final preview = itemCount > 1
                      ? '$firstItem + ${itemCount - 1} more'
                      : firstItem;

                  return GestureDetector(
                    onTap: () => onPick(order.id),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2030),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.15,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.receipt_long_outlined,
                              color: AppTheme.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preview,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '\$${order.totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white38,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateHint extends StatelessWidget {
  const _EmptyStateHint({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestionsFor(role);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF9C27B0)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How can I help you?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the mic and speak, or use the keyboard.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map((s) => _SuggestionChip(text: s))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _suggestionsFor(String role) {
    switch (role) {
      case 'driver':
        return [
          'Where is my next delivery?',
          'Mark order as delivered',
          'Navigation help',
        ];
      case 'admin':
        return [
          'Show pending orders',
          'Recent support tickets',
          'System status',
        ];
      default:
        return [
          'Where is my order?',
          'When will it arrive?',
          'I want to cancel',
        ];
    }
  }
}

class _SuggestionChip extends ConsumerWidget {
  const _SuggestionChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(aiVoiceProvider.notifier).sendText(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}

// ── Quick reply row shown after each AI response ─────────────────────────────

class _QuickReplySuggestions extends StatelessWidget {
  const _QuickReplySuggestions({
    required this.role,
    required this.onSend,
    this.lastAiMessage,
    this.lastUserMessage,
  });
  final String role;
  final void Function(String) onSend;
  final String? lastAiMessage;
  final String? lastUserMessage;

  @override
  Widget build(BuildContext context) {
    final chips = _contextualChips(role, lastAiMessage, lastUserMessage);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => onSend(chips[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2030),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                chips[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns chips relevant to the last exchange (user question + AI reply),
  /// falling back to role-based defaults when no keyword matches.
  List<String> _contextualChips(String role, String? aiMsg, String? userMsg) {
    final text = '${(userMsg ?? '')} ${(aiMsg ?? '')}'.toLowerCase();

    if (role == 'driver') {
      if (_any(text, ['deliver', 'drop', 'arrived', 'complete'])) {
        return [
          'Mark as delivered',
          'Customer not answering',
          'I had trouble finding the address',
          'Show next order',
        ];
      }
      if (_any(text, ['earn', 'pay', 'wage', 'income', 'bonus'])) {
        return [
          'Show this week\'s earnings',
          'When do I get paid?',
          'How do bonuses work?',
          'Show my delivery history',
        ];
      }
      if (_any(text, ['navig', 'direction', 'route', 'map', 'address'])) {
        return [
          'Open navigation',
          'The address looks wrong',
          'I arrived at the restaurant',
          'Customer changed address',
        ];
      }
      if (_any(text, ['order', 'pickup', 'restaurant', 'ready'])) {
        return [
          'I\'m at the restaurant',
          'Order is not ready yet',
          'Show order details',
          'Contact customer',
        ];
      }
      // Default driver
      return [
        'What\'s my next delivery?',
        'Show earnings today',
        'I need navigation help',
        'Report a problem',
        'Mark order as delivered',
        'How do I earn more?',
      ];
    }

    if (role == 'admin') {
      if (_any(text, ['order', 'pending', 'active', 'queue'])) {
        return [
          'Show all pending orders',
          'How many orders this hour?',
          'Any delayed orders?',
          'Show completed orders today',
        ];
      }
      if (_any(text, ['driver', 'deliver', 'assign'])) {
        return [
          'How many active drivers?',
          'Show unassigned orders',
          'Driver performance today',
          'Any driver complaints?',
        ];
      }
      if (_any(text, ['revenue', 'earn', 'sales', 'money', 'profit'])) {
        return [
          'Revenue this week',
          'Compare to last week',
          'Top earning restaurants',
          'Show refunds today',
        ];
      }
      if (_any(text, ['support', 'complaint', 'ticket', 'issue', 'problem'])) {
        return [
          'Show open tickets',
          'Any urgent complaints?',
          'Show refund requests',
          'Most common issues today',
        ];
      }
      // Default admin
      return [
        'Show pending orders',
        'Revenue today',
        'Active drivers now',
        'Open support tickets',
        'Top restaurants today',
        'Any system issues?',
      ];
    }

    // ── Customer (default) ────────────────────────────────────────────
    if (_any(text, ['cancel', 'cancelled', 'refund'])) {
      return [
        'Yes, cancel my order',
        'No, keep my order',
        'Will I get a refund?',
        'How long does refund take?',
      ];
    }
    if (_any(text, [
      'deliver',
      'arrive',
      'eta',
      'time',
      'late',
      'delay',
      'soon',
      'minutes',
    ])) {
      return [
        'Can you give me an exact time?',
        'My driver is very late',
        'Contact my driver',
        'Where is my driver now?',
      ];
    }
    if (_any(text, ['driver', 'location', 'track', 'map'])) {
      return [
        'How far is my driver?',
        'My driver is not moving',
        'Driver went the wrong way',
        'Call my driver',
      ];
    }
    if (_any(text, [
      'wrong',
      'missing',
      'item',
      'issue',
      'problem',
      'cold',
      'damage',
    ])) {
      return [
        'I want a refund',
        'Replace the missing item',
        'Report to support',
        'How do I get compensated?',
      ];
    }
    if (_any(text, ['promo', 'discount', 'code', 'coupon', 'offer', 'deal'])) {
      return [
        'Apply a promo code',
        'Show available offers',
        'Why isn\'t my code working?',
        'Earn loyalty points',
      ];
    }
    if (_any(text, ['address', 'location', 'change', 'update'])) {
      return [
        'Change delivery address',
        'Add a new address',
        'Use my current location',
        'Deliver to my office',
      ];
    }
    if (_any(text, ['pay', 'payment', 'card', 'wallet', 'charge', 'bill'])) {
      return [
        'I was charged twice',
        'Change payment method',
        'Top up my wallet',
        'Show my receipt',
      ];
    }
    if (_any(text, ['order', 'placed', 'confirm', 'status', 'process'])) {
      return [
        'Where is my order?',
        'When will it arrive?',
        'Add special instructions',
        'Cancel this order',
      ];
    }
    // Default customer
    return [
      'Where is my order?',
      'I have a problem with my order',
      'I want to cancel',
      'Talk to support',
      'Show me deals',
      'Track my driver',
    ];
  }

  bool _any(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
