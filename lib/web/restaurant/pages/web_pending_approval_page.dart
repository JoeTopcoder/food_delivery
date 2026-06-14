import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebPendingApprovalPage extends ConsumerStatefulWidget {
  final String restaurantId;
  const WebPendingApprovalPage({super.key, required this.restaurantId});

  @override
  ConsumerState<WebPendingApprovalPage> createState() => _WebPendingApprovalPageState();
}

class _WebPendingApprovalPageState extends ConsumerState<WebPendingApprovalPage> {
  RealtimeChannel? _channel;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _subscribeToApproval();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToApproval() {
    _channel = Supabase.instance.client
        .channel('restaurant-approval-${widget.restaurantId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'restaurants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.restaurantId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            final isVerified = newRow['is_verified'] == true;
            if (isVerified && mounted) {
              _onApproved();
            }
          },
        )
        .subscribe();
  }

  void _onApproved() {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId != null) {
      ref.invalidate(restaurantByOwnerProvider(currentUserId));
    }
  }

  Future<void> _checkManually() async {
    setState(() => _checking = true);
    try {
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null) {
        ref.invalidate(restaurantByOwnerProvider(currentUserId));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated icon
                _PulsingIcon(),
                const SizedBox(height: 32),

                // Heading
                const Text(
                  'Application Submitted!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),

                // Sub-heading
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Hang tight — admin will review shortly',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Info card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.schedule_rounded,
                        color: const Color(0xFFF59E0B),
                        title: 'Review Time',
                        subtitle: 'Applications are typically reviewed within 24–48 hours.',
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.notifications_active_rounded,
                        color: const Color(0xFF6366F1),
                        title: 'Instant Notification',
                        subtitle: "You'll be redirected to your dashboard automatically once approved.",
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.verified_rounded,
                        color: const Color(0xFF10B981),
                        title: 'What Happens Next',
                        subtitle: 'Our team verifies your restaurant details, then activates your account.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Check status button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _checkManually,
                    icon: _checking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                    label: Text(
                      _checking ? 'Checking…' : 'Check Approval Status',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Sign out
                TextButton(
                  onPressed: _signOut,
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pulsing icon animation ────────────────────────────────────────────────────

class _PulsingIcon extends StatefulWidget {
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColor.withValues(alpha: 0.15), AppTheme.primaryColor.withValues(alpha: 0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 2),
        ),
        child: Icon(Icons.hourglass_top_rounded, color: AppTheme.primaryColor, size: 44),
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _InfoRow({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}
