enum PayoutStatus {
  requested,
  approved,
  processing,
  transferred,
  paid,
  failed,
  canceled,
  rejected;

  static PayoutStatus fromString(String s) => PayoutStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => PayoutStatus.requested,
      );

  String get label {
    switch (this) {
      case PayoutStatus.requested:
        return 'Pending';
      case PayoutStatus.approved:
        return 'Approved';
      case PayoutStatus.processing:
        return 'Processing';
      case PayoutStatus.transferred:
        return 'Transferred';
      case PayoutStatus.paid:
        return 'Paid';
      case PayoutStatus.failed:
        return 'Failed';
      case PayoutStatus.canceled:
        return 'Canceled';
      case PayoutStatus.rejected:
        return 'Rejected';
    }
  }

  bool get isTerminal =>
      this == PayoutStatus.paid ||
      this == PayoutStatus.rejected ||
      this == PayoutStatus.canceled;

  bool get isFailed => this == PayoutStatus.failed;
  bool get isPaid => this == PayoutStatus.paid;
  bool get isProcessing =>
      this == PayoutStatus.processing || this == PayoutStatus.transferred;
  bool get isPending =>
      this == PayoutStatus.requested || this == PayoutStatus.approved;
}

class PayoutRequest {
  final String id;
  final String userId;
  final String role;
  final String stripeAccountId;
  final int amountCents;
  final String currency;
  final PayoutStatus status;
  final String payoutMethod;
  final int instantFeeCents;
  final String? stripeTransferId;
  final String? stripePayoutId;
  final String? failureCode;
  final String? failureMessage;
  final String? adminNote;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PayoutRequest({
    required this.id,
    required this.userId,
    required this.role,
    required this.stripeAccountId,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.payoutMethod = 'standard',
    this.instantFeeCents = 0,
    this.stripeTransferId,
    this.stripePayoutId,
    this.failureCode,
    this.failureMessage,
    this.adminNote,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  double get amountDollars => amountCents / 100.0;
  bool get isInstant => payoutMethod == 'instant';
  int get receivesCents => amountCents - instantFeeCents;

  factory PayoutRequest.fromJson(Map<String, dynamic> j) => PayoutRequest(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        stripeAccountId: j['stripe_account_id'] as String,
        amountCents: j['amount_cents'] as int,
        currency: j['currency'] as String? ?? 'usd',
        status: PayoutStatus.fromString(j['status'] as String? ?? 'requested'),
        payoutMethod: j['payout_method'] as String? ?? 'standard',
        instantFeeCents: j['instant_fee_cents'] as int? ?? 0,
        stripeTransferId: j['stripe_transfer_id'] as String?,
        stripePayoutId: j['stripe_payout_id'] as String?,
        failureCode: j['failure_code'] as String?,
        failureMessage: j['failure_message'] as String?,
        adminNote: j['admin_note'] as String?,
        approvedAt: j['approved_at'] != null
            ? DateTime.parse(j['approved_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'role': role,
        'stripe_account_id': stripeAccountId,
        'amount_cents': amountCents,
        'currency': currency,
        'status': status.name,
        'payout_method': payoutMethod,
        'instant_fee_cents': instantFeeCents,
        'stripe_transfer_id': stripeTransferId,
        'stripe_payout_id': stripePayoutId,
        'failure_code': failureCode,
        'failure_message': failureMessage,
        'admin_note': adminNote,
        'approved_at': approvedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
