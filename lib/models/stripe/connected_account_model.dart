class ConnectedAccount {
  final String id;
  final String userId;
  final String role;
  final String stripeAccountId;
  final String country;
  final String currency;
  final String onboardingStatus;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final bool detailsSubmitted;
  final String? transfersCapabilityStatus;
  final List<String> requirementsCurrentlyDue;
  final String? disabledReason;
  final DateTime? lastSyncedAt;
  final DateTime createdAt;

  const ConnectedAccount({
    required this.id,
    required this.userId,
    required this.role,
    required this.stripeAccountId,
    required this.country,
    required this.currency,
    required this.onboardingStatus,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.detailsSubmitted,
    this.transfersCapabilityStatus,
    required this.requirementsCurrentlyDue,
    this.disabledReason,
    this.lastSyncedAt,
    required this.createdAt,
  });

  /// True when Stripe onboarding is fully complete and payouts are enabled.
  bool get isComplete => onboardingStatus == 'complete';

  /// True when account has restrictions requiring action.
  bool get isRestricted => onboardingStatus == 'restricted';

  /// True when account is in a not_started or pending state.
  bool get isPending =>
      onboardingStatus == 'pending' || onboardingStatus == 'not_started';

  /// True when the transfers capability is active.
  bool get canReceiveTransfers => transfersCapabilityStatus == 'active';

  /// True when Stripe requires additional information.
  bool get needsMoreInfo => requirementsCurrentlyDue.isNotEmpty;

  factory ConnectedAccount.fromJson(Map<String, dynamic> j) => ConnectedAccount(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        stripeAccountId: j['stripe_account_id'] as String,
        country: j['country'] as String? ?? 'US',
        currency: j['currency'] as String? ?? 'usd',
        onboardingStatus: j['onboarding_status'] as String? ?? 'not_started',
        chargesEnabled: j['charges_enabled'] as bool? ?? false,
        payoutsEnabled: j['payouts_enabled'] as bool? ?? false,
        detailsSubmitted: j['details_submitted'] as bool? ?? false,
        transfersCapabilityStatus:
            j['transfers_capability_status'] as String?,
        requirementsCurrentlyDue: List<String>.from(
            (j['requirements_currently_due'] as List<dynamic>?) ?? []),
        disabledReason: j['disabled_reason'] as String?,
        lastSyncedAt: j['last_synced_at'] != null
            ? DateTime.parse(j['last_synced_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'role': role,
        'stripe_account_id': stripeAccountId,
        'country': country,
        'currency': currency,
        'onboarding_status': onboardingStatus,
        'charges_enabled': chargesEnabled,
        'payouts_enabled': payoutsEnabled,
        'details_submitted': detailsSubmitted,
        'transfers_capability_status': transfersCapabilityStatus,
        'requirements_currently_due': requirementsCurrentlyDue,
        'disabled_reason': disabledReason,
        'last_synced_at': lastSyncedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
