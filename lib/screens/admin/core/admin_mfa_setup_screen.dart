import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/mfa_service.dart';
import '../../../utils/app_theme.dart';

/// Admin two-step verification (TOTP) setup & management.
///
/// Opt-in: an admin comes here from the account menu to turn on 2FA. Scan the
/// QR with Google Authenticator / Authy, enter the 6-digit code to confirm,
/// and the factor becomes verified (the live session is upgraded to aal2).
/// If already enabled, shows status and a Disable option.
class AdminMfaSetupScreen extends ConsumerStatefulWidget {
  const AdminMfaSetupScreen({
    super.key,
    this.forceEnroll = false,
    this.onCompleted,
  });

  /// Skip the "already enabled" screen and go straight to enrolling a new
  /// authenticator — used by the email-recovery flow, where the old device is
  /// lost and the admin must set up a fresh one to regain aal2 (data) access.
  final bool forceEnroll;

  /// Called after enrollment succeeds. When set (recovery flow), the "done"
  /// screen offers "Continue to Admin Console" and stale factors are removed.
  final VoidCallback? onCompleted;

  @override
  ConsumerState<AdminMfaSetupScreen> createState() =>
      _AdminMfaSetupScreenState();
}

enum _View { loading, enabled, enroll, done, error }

class _AdminMfaSetupScreenState extends ConsumerState<AdminMfaSetupScreen> {
  _View _view = _View.loading;
  String? _error;

  // Enrollment data
  String? _factorId;
  String? _uri;
  String? _secret;

  final _codeCtrl = TextEditingController();
  bool _busy = false;

  MfaService get _svc => ref.read(mfaServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _view = _View.loading;
      _error = null;
    });
    try {
      // Recovery flow: always enroll a fresh factor, even if a (lost) one exists.
      if (widget.forceEnroll) {
        await _beginEnroll();
        return;
      }
      final hasIt = await _svc.hasVerifiedTotp();
      if (!mounted) return;
      setState(() => _view = hasIt ? _View.enabled : _View.loading);
      if (!hasIt) await _beginEnroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.error;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _beginEnroll() async {
    setState(() {
      _view = _View.loading;
      _error = null;
    });
    try {
      final res = await _svc.startEnrollment();
      if (!mounted) return;
      setState(() {
        _factorId = res.factorId;
        _uri = res.uri;
        _secret = res.secret;
        _view = _View.enroll;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.error;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6 || _factorId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _svc.verify(factorId: _factorId!, code: code);
      // Recovery re-enroll: now aal2, so drop the old lost authenticator(s).
      if (widget.forceEnroll) {
        try {
          await _svc.removeOtherFactors(_factorId!);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _view = _View.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off two-step verification?'),
        content: const Text(
          'Your account will be protected by password only. You can turn it '
          'back on any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.disableAll();
      if (!mounted) return;
      setState(() => _busy = false);
      await _beginEnroll(); // back to the enroll view
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    final s = e.toString();
    if (s.contains('invalid') || s.contains('Invalid')) {
      return 'That code didn\'t match. Check your authenticator and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-step verification'),
      ),
      body: SafeArea(
        child: switch (_view) {
          _View.loading => const Center(child: CircularProgressIndicator()),
          _View.enabled => _enabledView(),
          _View.enroll => _enrollView(),
          _View.done => _doneView(),
          _View.error => _errorView(),
        },
      ),
    );
  }

  Widget _enabledView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        _shield(const Color(0xFF16A34A), Icons.verified_user_rounded),
        const SizedBox(height: 16),
        const Text(
          'Two-step verification is ON',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Your admin account asks for a code from your authenticator app each '
          'time you sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, height: 1.4),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: _busy ? null : _disable,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFDC2626)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.no_encryption_gmailerrorred_rounded),
          label: const Text('Turn off two-step verification'),
        ),
      ],
    );
  }

  Widget _enrollView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Protect your admin account',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '1. Open an authenticator app (Google Authenticator, Authy, 1Password).\n'
          '2. Scan this QR code, or enter the key manually.\n'
          '3. Type the 6-digit code it shows to confirm.',
          style: TextStyle(color: Colors.grey.shade600, height: 1.5),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _uri == null
                ? const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : QrImageView(
                    data: _uri!,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        if (_secret != null) _manualKey(_secret!),
        const SizedBox(height: 24),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            if (v.length == 6 && !_busy) _verify();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFDC2626)),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verify,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm & turn on'),
        ),
      ],
    );
  }

  Widget _manualKey(String secret) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: secret));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key copied')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.key_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                secret,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            const Icon(Icons.copy_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _doneView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        _shield(const Color(0xFF16A34A), Icons.check_circle_rounded),
        const SizedBox(height: 16),
        const Text(
          'You\'re protected',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Two-step verification is now on. You\'ll be asked for a code from '
          'your authenticator each time you sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, height: 1.4),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () {
            if (widget.onCompleted != null) {
              widget.onCompleted!();
            } else {
              Navigator.of(context).pop();
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(widget.onCompleted != null
              ? 'Continue to Admin Console'
              : 'Done'),
        ),
      ],
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _shield(Color color, IconData icon) => Center(
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 44),
        ),
      );
}
