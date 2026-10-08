import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/auth_user/auth_provider.dart';
import '../../../services/mfa_service.dart';
import '../../../utils/app_theme.dart';
import '../core/admin_mfa_setup_screen.dart';
import '../core/admin_overview_screen.dart';

/// Post-login step-up for an admin with two-step verification enabled.
///
/// Two ways past: enter the current TOTP code from the authenticator app, or —
/// if that's unavailable — request a one-time code by email and enter that.
/// The only other option is signing out.
class AdminMfaChallengeScreen extends ConsumerStatefulWidget {
  const AdminMfaChallengeScreen({super.key, this.onVerified});

  /// Called when verification succeeds. When provided (e.g. by [AdminGate]),
  /// the gate swaps in the console in place; otherwise we navigate to the
  /// mobile AdminOverviewScreen ourselves.
  final VoidCallback? onVerified;

  @override
  ConsumerState<AdminMfaChallengeScreen> createState() =>
      _AdminMfaChallengeScreenState();
}

class _AdminMfaChallengeScreenState
    extends ConsumerState<AdminMfaChallengeScreen> {
  static const _shield = Color(0xFF2563EB);

  final _codeCtrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  // Recovery (email code) mode.
  bool _recovery = false;
  bool _recoverySent = false;
  String? _maskedEmail;

  Timer? _timer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final s = 30 - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
    if (mounted) setState(() => _secondsLeft = s);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  MfaService get _svc => ref.read(mfaServiceProvider);

  void _toConsole() {
    if (!mounted) return;
    if (widget.onVerified != null) {
      widget.onVerified!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminOverviewScreen()),
    );
  }

  Future<void> _verifyTotp() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _svc.stepUp(code: code);
      _toConsole();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException
            ? 'That code didn\'t match. Try the current one.'
            : 'Verification failed. Please try again.';
        _codeCtrl.clear();
      });
      _focus.requestFocus();
    }
  }

  Future<void> _requestRecovery() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final masked = await _svc.requestRecoveryCode();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recoverySent = true;
        _maskedEmail = masked;
        _codeCtrl.clear();
      });
      _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException ? e.message : 'Could not send a code.';
      });
    }
  }

  Future<void> _verifyRecovery() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await _svc.verifyRecoveryCode(code);
      if (!mounted) return;
      if (ok) {
        // Recovery leaves the session at aal1, which the database now blocks
        // for admin data. Route into re-enrolling a fresh authenticator, which
        // reaches aal2; on completion, continue into the console.
        setState(() => _busy = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminMfaSetupScreen(
              forceEnroll: true,
              onCompleted: () {
                Navigator.of(context).pop();
                _toConsole();
              },
            ),
          ),
        );
      } else {
        setState(() {
          _busy = false;
          _error = 'That code is wrong or expired.';
          _codeCtrl.clear();
        });
        _focus.requestFocus();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Verification failed. Please try again.';
      });
    }
  }

  void _onCodeChanged(String v) {
    setState(() => _error = null);
    if (v.length == 6) {
      _recovery ? _verifyRecovery() : _verifyTotp();
    }
  }

  void _signOut() => ref.read(authNotifierProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _appBar(theme),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: _recovery ? _recoveryBody(theme) : _totpBody(theme),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _busy ? null : _signOut,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Hot',
                style: TextStyle(
                    color: onSurface, fontWeight: FontWeight.w900, fontSize: 20),
              ),
              TextSpan(
                text: 'Bite',
                style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 20),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
              width: 1, height: 22, color: onSurface.withValues(alpha: 0.15)),
          const SizedBox(width: 12),
          Text(
            'Admin security',
            style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Authenticator (TOTP) mode ──────────────────────────────────────────────
  Widget _totpBody(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final code = _codeCtrl.text;
    final complete = code.length == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        _shieldIcon(Icons.shield_rounded, _shield),
        const SizedBox(height: 24),
        _title(theme, 'Verify your identity'),
        const SizedBox(height: 10),
        _subtitle(theme,
            'Enter the 6-digit code from your authenticator app to continue to Admin Console.'),
        const SizedBox(height: 32),
        _otpBoxes(theme, code),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_rounded,
                size: 16, color: onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text('Code refreshes in ${_secondsLeft}s',
                style: TextStyle(
                    fontSize: 13, color: onSurface.withValues(alpha: 0.5))),
          ],
        ),
        _errorText(),
        const SizedBox(height: 28),
        _primaryButton(
          label: 'Verify code',
          enabled: complete,
          onPressed: _verifyTotp,
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _recovery = true;
                      _recoverySent = false;
                      _error = null;
                      _codeCtrl.clear();
                    }),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 14),
                children: [
                  const TextSpan(text: 'Having trouble? '),
                  TextSpan(
                    text: 'Use a backup code',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _signOutLink(),
      ],
    );
  }

  // ── Recovery (email code) mode ─────────────────────────────────────────────
  Widget _recoveryBody(ThemeData theme) {
    final code = _codeCtrl.text;
    final complete = code.length == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        _shieldIcon(Icons.mark_email_read_rounded, AppTheme.primaryColor),
        const SizedBox(height: 24),
        _title(theme, _recoverySent ? 'Check your email' : 'Email a sign-in code'),
        const SizedBox(height: 10),
        _subtitle(
          theme,
          _recoverySent
              ? 'We sent a 6-digit code to $_maskedEmail. Enter it below — it expires in 10 minutes.'
              : 'Can\'t use your authenticator? We\'ll email a one-time code to your admin email address.',
        ),
        const SizedBox(height: 32),
        if (_recoverySent) ...[
          _otpBoxes(theme, code),
          _errorText(),
          const SizedBox(height: 28),
          _primaryButton(
            label: 'Verify code',
            enabled: complete,
            onPressed: _verifyRecovery,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _requestRecovery,
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
              child: const Text('Resend code'),
            ),
          ),
        ] else ...[
          _errorText(),
          _primaryButton(
            label: 'Email me a code',
            enabled: true,
            onPressed: _requestRecovery,
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _recovery = false;
                      _recoverySent = false;
                      _error = null;
                      _codeCtrl.clear();
                    }),
            child: const Text('Back to authenticator'),
          ),
        ),
        const SizedBox(height: 4),
        _signOutLink(),
      ],
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────────
  Widget _shieldIcon(IconData icon, Color color) => Center(
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 46),
        ),
      );

  Widget _title(ThemeData theme, String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface),
      );

  Widget _subtitle(ThemeData theme, String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
      );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFDC2626))),
        );

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) =>
      FilledButton(
        onPressed: (enabled && !_busy) ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _signOutLink() => Center(
        child: TextButton(
          onPressed: _busy ? null : _signOut,
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
          child: const Text('Sign out',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  /// Six segmented digit boxes with a transparent full-width field on top that
  /// captures the actual keyboard input.
  Widget _otpBoxes(ThemeData theme, String code) {
    final onSurface = theme.colorScheme.onSurface;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            final filled = i < code.length;
            final active = i == code.length && !_busy;
            return Container(
              width: 48,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _error != null
                      ? const Color(0xFFDC2626)
                      : active
                          ? AppTheme.primaryColor
                          : filled
                              ? AppTheme.primaryColor.withValues(alpha: 0.5)
                              : onSurface.withValues(alpha: 0.15),
                  width: active ? 2 : 1.2,
                ),
              ),
              child: Text(
                filled ? code[i] : '',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: onSurface),
              ),
            );
          }),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _codeCtrl,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  counterText: '', border: InputBorder.none),
              onChanged: _onCodeChanged,
            ),
          ),
        ),
      ],
    );
  }
}
