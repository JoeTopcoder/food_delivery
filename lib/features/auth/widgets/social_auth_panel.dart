import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

  // Apple is only available on Apple devices.
  bool get _showApple {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS;
    }
    return Platform.isIOS || Platform.isMacOS;
  }

  // Google is only shown on Android/web. On iOS the native Google Sign-In
  // SDK requires GoogleService-Info.plist + a registered URL scheme; Apple
  // also requires Sign in with Apple to be the primary social auth option.
  bool get _showGoogle {
    if (kIsWeb) return true;
    return !Platform.isIOS && !Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showGoogle) ...[
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
        ],
        if (_showApple) ...[
          if (_showGoogle) const SizedBox(height: 10),
          SignInWithAppleButton(
            onPressed: appleLoading ? null : onApple,
            style: SignInWithAppleButtonStyle.black,
          ),
        ],
      ],
    );
  }
}
