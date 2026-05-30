class Wallet {
  final String userId;
  final double balance;
  final double cashbackBalance;
  final double reservedBalance;
  final double debtBalance;
  final DateTime updatedAt;

  Wallet({
    required this.userId,
    this.balance = 0,
    this.cashbackBalance = 0,
    this.reservedBalance = 0,
    this.debtBalance = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  double get totalAvailable => balance + cashbackBalance;

  /// Spendable balance — deducts both active holds and any outstanding admin debt
  double get availableBalance =>
      (balance - reservedBalance - debtBalance).clamp(0.0, double.infinity);

  bool get hasDebt => debtBalance > 0;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      userId:          json['user_id'] as String,
      balance:         (json['balance']          as num?)?.toDouble() ?? 0,
      cashbackBalance: (json['cashback_balance'] as num?)?.toDouble() ?? 0,
      reservedBalance: (json['reserved_balance'] as num?)?.toDouble() ?? 0,
      debtBalance:     (json['debt_balance']     as num?)?.toDouble() ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  factory Wallet.empty(String userId) => Wallet(userId: userId);
}

class WalletTransaction {
  final String id;
  final String userId;
  final double amount;
  final String
  type; // deposit, payment, cashback, refund, penalty, tip_received
  final String? paymentMethod;
  final String status;
  final String? orderId;
  final String? description;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    this.paymentMethod,
    this.status = 'completed',
    this.orderId,
    this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      paymentMethod: json['payment_method'] as String?,
      status: json['status'] as String? ?? 'completed',
      orderId: json['order_id'] as String?,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;
}
