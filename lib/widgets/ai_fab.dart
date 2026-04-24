import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_theme.dart';
import '../screens/shared/ai_voice_screen.dart';
import '../models/order_model.dart';

/// Floating AI button. Drop into any Scaffold's [floatingActionButton].
///
/// [role]    'customer' | 'driver' | 'admin'
/// [orderId] Optional — passes live order context to the AI.
/// [restaurantId] Optional — passes menu & restaurant context to the AI.
/// [activeOrders] Optional — all non-terminal orders; enables multi-order picker.
class AiFab extends ConsumerWidget {
  const AiFab({
    super.key,
    required this.role,
    this.orderId,
    this.restaurantId,
    this.activeOrders,
  });

  final String role;
  final String? orderId;
  final String? restaurantId;
  final List<Order>? activeOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      heroTag: 'ai_fab_${role}_${orderId ?? 'none'}',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiVoiceScreen(
            role: role,
            orderId: orderId,
            restaurantId: restaurantId,
            activeOrders: activeOrders,
          ),
        ),
      ),
      backgroundColor: AppTheme.primaryColor,
      tooltip: 'AI Assistant',
      child: const Icon(Icons.smart_toy_outlined, color: Colors.white),
    );
  }
}

/// AppBar action icon version — use inside AppBar.actions.
class AiAppBarAction extends ConsumerWidget {
  const AiAppBarAction({
    super.key,
    required this.role,
    this.orderId,
    this.restaurantId,
    this.activeOrders,
  });

  final String role;
  final String? orderId;
  final String? restaurantId;
  final List<Order>? activeOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.smart_toy_outlined),
      tooltip: 'AI Assistant',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiVoiceScreen(
            role: role,
            orderId: orderId,
            restaurantId: restaurantId,
            activeOrders: activeOrders,
          ),
        ),
      ),
    );
  }
}
