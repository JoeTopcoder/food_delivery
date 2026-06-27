import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// Shows a bottom-sheet prompting the guest to sign in.
///
/// Returns `true` if the user navigated to sign-in, `false` if they dismissed.
///
/// Usage:
/// ```dart
/// if (!ref.read(authNotifierProvider).isAuthenticated) {
///   showGuestSignInPrompt(context);
///   return;
/// }
/// // proceed with auth-required action
/// ```
Future<bool> showGuestSignInPrompt(
  BuildContext context, {
  String? message,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _GuestSignInSheet(
      message: message ?? 'Sign in to continue.',
    ),
  );
  return result ?? false;
}

class _GuestSignInSheet extends StatelessWidget {
  final String message;
  const _GuestSignInSheet({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: Color(0xFFFF7A1A),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sign in to continue',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
                Navigator.pushNamed(context, '/role-selection');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A1A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Sign In / Create Account',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue browsing'),
          ),
        ],
      ),
    );
  }
}

/// Convenience widget that wraps an [onTap] with a guest auth check.
///
/// If the user is not authenticated, shows the sign-in prompt instead of
/// calling [onTap]. Saves adding boilerplate to every tappable widget.
class GuestAuthGuard extends ConsumerWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? promptMessage;

  const GuestAuthGuard({
    super.key,
    required this.child,
    required this.onTap,
    this.promptMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(authNotifierProvider).isAuthenticated;
    return GestureDetector(
      onTap: () {
        if (!isAuthenticated) {
          showGuestSignInPrompt(context, message: promptMessage);
          return;
        }
        onTap();
      },
      child: child,
    );
  }
}
