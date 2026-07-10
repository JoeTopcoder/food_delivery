class EarningsSummary {
  final int availableBalanceCents;
  final int pendingBalanceCents;
  final int lockedBalanceCents;
  final int withdrawnBalanceCents;
  final int lifetimeEarnedCents;

  const EarningsSummary({
    required this.availableBalanceCents,
    required this.pendingBalanceCents,
    required this.lockedBalanceCents,
    required this.withdrawnBalanceCents,
    required this.lifetimeEarnedCents,
  });

  /// Available balance in dollars (2 decimal places).
  double get availableBalanceDollars => availableBalanceCents / 100.0;

  /// Pending balance in dollars.
  double get pendingBalanceDollars => pendingBalanceCents / 100.0;

  /// Lifetime earnings in dollars.
  double get lifetimeEarnedDollars => lifetimeEarnedCents / 100.0;

  factory EarningsSummary.fromJson(Map<String, dynamic> j) => EarningsSummary(
        availableBalanceCents:
            (j['available_balance_cents'] as num?)?.toInt() ?? 0,
        pendingBalanceCents:
            (j['pending_balance_cents'] as num?)?.toInt() ?? 0,
        lockedBalanceCents:
            (j['locked_balance_cents'] as num?)?.toInt() ?? 0,
        withdrawnBalanceCents:
            (j['withdrawn_balance_cents'] as num?)?.toInt() ?? 0,
        lifetimeEarnedCents:
            (j['lifetime_earned_cents'] as num?)?.toInt() ?? 0,
      );

  static EarningsSummary zero() => const EarningsSummary(
        availableBalanceCents: 0,
        pendingBalanceCents: 0,
        lockedBalanceCents: 0,
        withdrawnBalanceCents: 0,
        lifetimeEarnedCents: 0,
      );
}

class PayoutSettings {
  final int minPayoutCents;
  final int maxPayoutCents;
  final int driverHoldDays;
  final int restaurantHoldDays;
  final bool requireAdminApproval;
  final bool instantPayoutsEnabled;
  final String platformCurrency;

  const PayoutSettings({
    required this.minPayoutCents,
    required this.maxPayoutCents,
    required this.driverHoldDays,
    required this.restaurantHoldDays,
    required this.requireAdminApproval,
    required this.instantPayoutsEnabled,
    required this.platformCurrency,
  });

  double get minPayoutDollars => minPayoutCents / 100.0;
  double get maxPayoutDollars => maxPayoutCents / 100.0;

  factory PayoutSettings.fromJson(Map<String, dynamic> j) => PayoutSettings(
        minPayoutCents: j['min_payout_cents'] as int? ?? 1000,
        maxPayoutCents: j['max_payout_cents'] as int? ?? 500000,
        driverHoldDays: j['driver_hold_days'] as int? ?? 2,
        restaurantHoldDays: j['restaurant_hold_days'] as int? ?? 2,
        requireAdminApproval: j['require_admin_approval'] as bool? ?? true,
        instantPayoutsEnabled: j['instant_payouts_enabled'] as bool? ?? false,
        platformCurrency: j['platform_currency'] as String? ?? 'usd',
      );
}
