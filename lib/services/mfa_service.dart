import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth MFA (TOTP) for the admin two-step
/// verification flow. TOTP only — a single authenticator factor per admin.
///
/// Assurance levels: `aal1` = password only, `aal2` = password + a verified
/// TOTP code this session. Enrolling then verifying a factor upgrades the live
/// session to aal2; a fresh login with a verified factor starts at aal1 and
/// must "step up" by entering a code.
class MfaService {
  MfaService(this._client);
  final SupabaseClient _client;

  GoTrueMFAApi get _mfa => _client.auth.mfa;

  /// The user's verified TOTP factor, or null if they haven't finished setup.
  Future<Factor?> verifiedTotpFactor() async {
    final res = await _mfa.listFactors();
    for (final f in res.totp) {
      if (f.status == FactorStatus.verified) return f;
    }
    return null;
  }

  /// True once the user has completed TOTP enrollment.
  Future<bool> hasVerifiedTotp() async => (await verifiedTotpFactor()) != null;

  /// Whether this session still needs to step up to aal2 — i.e. the user has a
  /// verified factor but has so far only authenticated with a password. Reads
  /// the current session synchronously (no network), so it's safe to call from
  /// a widget build / routing decision.
  bool needsStepUp() {
    final aal = _mfa.getAuthenticatorAssuranceLevel();
    return aal.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  /// Whether the current session has already satisfied MFA this session.
  bool get isAal2 =>
      _mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  /// Reliable step-up check for use right after login. The synchronous
  /// [needsStepUp] reads `session.user.factors`, which is NOT populated
  /// immediately after a fresh sign-in — so it wrongly reports "no factor" and
  /// the challenge is skipped. This calls [listFactors] first (a network call
  /// that also refreshes the session's factor list), then reports true when the
  /// user has a verified factor but the session hasn't reached aal2 yet.
  Future<bool> needsStepUpAsync() async {
    final factor = await verifiedTotpFactor(); // refreshes session factors
    if (factor == null) return false;
    final level = _mfa.getAuthenticatorAssuranceLevel().currentLevel;
    return level != AuthenticatorAssuranceLevels.aal2;
  }

  /// Begin enrollment: clear any stale unverified factors first (so they don't
  /// accumulate), then enroll a fresh TOTP factor. Returns the data needed to
  /// render the QR code and manual-entry secret.
  Future<({String factorId, String uri, String secret})>
      startEnrollment() async {
    final existing = await _mfa.listFactors();
    for (final f in existing.all) {
      if (f.status == FactorStatus.unverified) {
        try {
          await _mfa.unenroll(f.id);
        } catch (_) {
          // Best-effort cleanup; a lingering unverified factor is harmless.
        }
      }
    }
    final res = await _mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'HotBite Admin',
    );
    final totp = res.totp;
    if (totp == null) {
      throw const AuthException(
        'Two-step verification is not enabled for this project. '
        'Enable TOTP in the Supabase dashboard (Authentication → MFA).',
      );
    }
    return (factorId: res.id, uri: totp.uri, secret: totp.secret);
  }

  /// Verify a 6-digit code against [factorId] (challenge + verify in one call).
  /// On success the live session is upgraded to aal2. Throws [AuthException]
  /// on a wrong/expired code.
  Future<void> verify({required String factorId, required String code}) async {
    await _mfa.challengeAndVerify(factorId: factorId, code: code.trim());
  }

  /// Step up an already-logged-in session using the user's existing verified
  /// factor. Throws if there is no verified factor to challenge.
  Future<void> stepUp({required String code}) async {
    final factor = await verifiedTotpFactor();
    if (factor == null) {
      throw const AuthException('No verified authenticator to verify against.');
    }
    await verify(factorId: factor.id, code: code);
  }

  /// Ask the server to email a one-time recovery code to the admin's account
  /// email (for when the authenticator app isn't available). Returns a masked
  /// version of the destination email (e.g. "su****@7-dash.com").
  Future<String> requestRecoveryCode() async {
    try {
      final res = await _client.functions
          .invoke('admin-recovery-code', body: {'action': 'request'});
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (data['sent_to'] as String?) ?? 'your email';
      }
      throw AuthException(
        (data is Map ? data['error'] as String? : null) ??
            'Could not send a code.',
      );
    } on FunctionException catch (e) {
      throw AuthException(_fnError(e.details) ?? 'Could not send a code.');
    }
  }

  /// Verify an emailed recovery code. Returns true when it matches an unexpired,
  /// unused code. Does NOT upgrade the session to aal2 — this is an app-level
  /// recovery path into the console.
  Future<bool> verifyRecoveryCode(String code) async {
    try {
      final res = await _client.functions.invoke(
        'admin-recovery-code',
        body: {'action': 'verify', 'code': code.trim()},
      );
      final data = res.data;
      return data is Map && data['ok'] == true;
    } on FunctionException catch (_) {
      return false;
    }
  }

  String? _fnError(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return null;
  }

  /// Turn off two-step verification: unenroll every factor on the account.
  Future<void> disableAll() async {
    final res = await _mfa.listFactors();
    for (final f in res.all) {
      try {
        await _mfa.unenroll(f.id);
      } catch (_) {}
    }
  }
}

final mfaServiceProvider =
    Provider<MfaService>((ref) => MfaService(Supabase.instance.client));
