import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/mfa_service.dart';
import '../../../web/admin/admin_web_app.dart';
import '../core/admin_mfa_challenge_screen.dart';
import '../core/admin_overview_screen.dart';

/// Decides, after an admin logs in, whether they must complete a TOTP step-up
/// before the console loads. Used on both the mobile and web admin entry
/// points — it renders the right console (AdminWebApp on web, else
/// AdminOverviewScreen) once MFA is satisfied.
///
/// The synchronous AAL check is unreliable right after sign-in because
/// `session.user.factors` isn't populated yet, so this does an async
/// [MfaService.needsStepUpAsync] (which refreshes the factor list) before
/// routing. Shows a brief spinner while that resolves. When the step-up is
/// satisfied (in-session), it swaps to the console without a new login.
class AdminGate extends ConsumerStatefulWidget {
  const AdminGate({super.key});

  @override
  ConsumerState<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends ConsumerState<AdminGate> {
  late final Future<bool> _needsStepUp;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _needsStepUp = _check();
  }

  Future<bool> _check() async {
    try {
      return await ref.read(mfaServiceProvider).needsStepUpAsync();
    } catch (_) {
      // If the factor lookup fails (e.g. offline), don't lock the admin out of
      // the console over a transient error — fall through to the dashboard.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _needsStepUp,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == true && !_verified) {
          return AdminMfaChallengeScreen(
            onVerified: () => setState(() => _verified = true),
          );
        }
        return kIsWeb ? const AdminWebApp() : const AdminOverviewScreen();
      },
    );
  }
}
