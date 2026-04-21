import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A reusable panel showing Google (and Apple on iOS/macOS) sign-in buttons.
class SocialAuthPanel extends StatelessWidget {
  const SocialAuthPanel({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.googleLoading = false,
    this.appleLoading = false,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final bool googleLoading;
  final bool appleLoading;

  bool get _showApple => kIsWeb ? false : (Platform.isIOS || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onGoogle,
          icon: googleLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.g_mobiledata, size: 26),
          label: Text(googleLoading ? 'Signing in...' : 'Continue with Google'),
        ),
        if (_showApple) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onApple,
            icon: appleLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.apple, size: 24),
            label: Text(appleLoading ? 'Signing in...' : 'Continue with Apple'),
          ),
        ],
      ],
    );
  }
}
