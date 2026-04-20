import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';

class PayoutRequest {
  final String id;
  final String requesterId;
  final String requesterType;
  final String? driverId;
  final String? restaurantId;
  final double amount;
  final String bankName;
  final String? bankBranch;
  final String bankAccountNumber;
  final String bankAccountHolder;
  final String? bankAccountType;
  final String status;
  final String? adminNotes;
  final String? wipayTransactionId;
  final DateTime? processedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PayoutRequest({
    required this.id,
    required this.requesterId,
    required this.requesterType,
    this.driverId,
    this.restaurantId,
    required this.amount,
    required this.bankName,
    this.bankBranch,
    required this.bankAccountNumber,
    required this.bankAccountHolder,
    this.bankAccountType,
    required this.status,
    this.adminNotes,
    this.wipayTransactionId,
    this.processedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory PayoutRequest.fromJson(Map<String, dynamic> json) {
    return PayoutRequest(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      requesterType: json['requester_type'] as String,
      driverId: json['driver_id'] as String?,
      restaurantId: json['restaurant_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      bankName: json['bank_name'] as String,
      bankBranch: json['bank_branch'] as String?,
      bankAccountNumber: json['bank_account_number'] as String,
      bankAccountHolder: json['bank_account_holder'] as String,
      bankAccountType: json['bank_account_type'] as String?,
      status: json['status'] as String,
      adminNotes: json['admin_notes'] as String?,
      wipayTransactionId: json['wipay_transaction_id'] as String?,
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed' || status == 'rejected';
}

class PayoutService {
  final SupabaseClient _client;

  PayoutService(this._client);

  // ── Bank Info ───────────────────────────────────────────────

  Future<void> saveDriverBankInfo({
    required String driverId,
    required String bankName,
    required String bankBranch,
    required String accountNumber,
    required String accountHolder,
    required String accountType,
  }) async {
    try {
      await _client
          .from(AppConstants.tableDrivers)
          .update({
            'bank_name': bankName,
            'bank_branch': bankBranch,
            'bank_account_number': accountNumber,
            'bank_account_holder': accountHolder,
            'bank_account_type': accountType,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      AppLogger.info('Driver bank info saved');
    } catch (e) {
      AppLogger.error('Error saving driver bank info: $e');
      rethrow;
    }
  }

  Future<void> saveRestaurantBankInfo({
    required String restaurantId,
    required String bankName,
    required String bankBranch,
    required String accountNumber,
    required String accountHolder,
    required String accountType,
  }) async {
    try {
      await _client
          .from(AppConstants.tableRestaurants)
          .update({
            'bank_name': bankName,
            'bank_branch': bankBranch,
            'bank_account_number': accountNumber,
            'bank_account_holder': accountHolder,
            'bank_account_type': accountType,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', restaurantId);
      AppLogger.info('Restaurant bank info saved');
    } catch (e) {
      AppLogger.error('Error saving restaurant bank info: $e');
      rethrow;
    }
  }

  // ── Payout Requests ────────────────────────────────────────

  Future<PayoutRequest> requestDriverPayout({
    required String userId,
    required String driverId,
    required double amount,
    required String bankName,
    required String bankBranch,
    required String accountNumber,
    required String accountHolder,
    required String accountType,
  }) async {
    try {
      final response = await _client
          .from('payout_requests')
          .insert({
            'requester_id': userId,
            'requester_type': 'driver',
            'driver_id': driverId,
            'amount': amount,
            'bank_name': bankName,
            'bank_branch': bankBranch,
            'bank_account_number': accountNumber,
            'bank_account_holder': accountHolder,
            'bank_account_type': accountType,
            'status': 'pending',
          })
          .select()
          .single();
      AppLogger.info('Driver payout request created: ${response['id']}');

      // Immediately update total_paid_out to include all active payouts
      // so Available Balance decreases right away
      await _recalcDriverPaidOut(driverId);

      return PayoutRequest.fromJson(response);
    } catch (e) {
      AppLogger.error('Error requesting driver payout: $e');
      rethrow;
    }
  }

  /// Recalculate total_paid_out for a driver from all active payout requests
  /// (pending, approved, processing, completed — excludes rejected/failed).
  Future<void> _recalcDriverPaidOut(String driverId) async {
    try {
      final rows = await _client
          .from('payout_requests')
          .select('amount, status')
          .eq('driver_id', driverId)
          .not('status', 'in', '(rejected,failed)');
      final total = (rows as List).fold<double>(
        0.0,
        (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0),
      );
      await _client
          .from(AppConstants.tableDrivers)
          .update({
            'total_paid_out': total,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
    } catch (e) {
      AppLogger.error('Error recalculating driver paid out: $e');
    }
  }

  Future<PayoutRequest> requestRestaurantPayout({
    required String userId,
    required String restaurantId,
    required double amount,
    required String bankName,
    required String bankBranch,
    required String accountNumber,
    required String accountHolder,
    required String accountType,
  }) async {
    try {
      final response = await _client
          .from('payout_requests')
          .insert({
            'requester_id': userId,
            'requester_type': 'restaurant',
            'restaurant_id': restaurantId,
            'amount': amount,
            'bank_name': bankName,
            'bank_branch': bankBranch,
            'bank_account_number': accountNumber,
            'bank_account_holder': accountHolder,
            'bank_account_type': accountType,
            'status': 'pending',
          })
          .select()
          .single();
      AppLogger.info('Restaurant payout request created: ${response['id']}');
      return PayoutRequest.fromJson(response);
    } catch (e) {
      AppLogger.error('Error requesting restaurant payout: $e');
      rethrow;
    }
  }

  Future<List<PayoutRequest>> getMyPayouts(String userId) async {
    try {
      final response = await _client
          .from('payout_requests')
          .select()
          .eq('requester_id', userId)
          .order('created_at', ascending: false);
      return (response as List).map((e) => PayoutRequest.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching payouts: $e');
      rethrow;
    }
  }

  // ── Admin ──────────────────────────────────────────────────

  Future<List<PayoutRequest>> getAllPayouts({String? statusFilter}) async {
    try {
      var query = _client.from('payout_requests').select();
      if (statusFilter != null && statusFilter.isNotEmpty) {
        query = query.eq('status', statusFilter);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).map((e) => PayoutRequest.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching all payouts: $e');
      rethrow;
    }
  }

  Future<void> approvePayout(String payoutId) async {
    try {
      await _client
          .from('payout_requests')
          .update({
            'status': 'approved',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);
    } catch (e) {
      AppLogger.error('Error approving payout: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> processPayout(String payoutId) async {
    try {
      // Fetch payout details first
      final payoutData = await _client
          .from('payout_requests')
          .select()
          .eq('id', payoutId)
          .single();

      final amount = (payoutData['amount'] as num).toDouble();
      final recipientName = payoutData['bank_account_holder'] as String;
      final bankAccount = payoutData['bank_account_number'] as String;
      final bankName = payoutData['bank_name'] as String;
      final requesterType = payoutData['requester_type'] as String;

      // Update status to processing
      await _client
          .from('payout_requests')
          .update({
            'status': 'processing',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);

      // Call Stripe payout via the stripe-payment edge function
      final response = await _client.functions.invoke(
        'stripe-payment',
        body: {
          'action': 'create_payout',
          'payoutId': payoutId,
          'amount': amount,
          'currency': 'usd',
          'recipientName': recipientName,
          'bankAccount': bankAccount,
          'bankName': bankName,
          'description':
              '${requesterType == 'driver' ? 'Driver' : 'Restaurant'} payout $payoutId',
        },
      );

      final data = response.data as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      if (status != 'success') {
        final error = data?['error'] ?? 'Stripe payout failed';
        // Revert to approved so admin can retry
        await _client
            .from('payout_requests')
            .update({
              'status': 'approved',
              'admin_notes': 'Stripe payout failed: $error',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', payoutId);
        throw Exception(error);
      }

      final payoutRef = data?['payout_reference'] as String? ?? '';

      // Mark as completed with Stripe reference
      await markPayoutCompleted(payoutId: payoutId, transactionId: payoutRef);

      AppLogger.info('Payout processed via Stripe: $payoutId ref=$payoutRef');

      return {
        'payout_id': payoutId,
        'payout_reference': payoutRef,
        'amount': amount,
        'recipient_name': recipientName,
        'bank_name': bankName,
        'bank_account': bankAccount,
        'requester_type': requesterType,
        'status': 'completed',
      };
    } catch (e) {
      AppLogger.error('Error processing payout: $e');
      rethrow;
    }
  }

  Future<void> rejectPayout(String payoutId, String reason) async {
    try {
      await _client
          .from('payout_requests')
          .update({
            'status': 'rejected',
            'admin_notes': reason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);
    } catch (e) {
      AppLogger.error('Error rejecting payout: $e');
      rethrow;
    }
  }

  Future<void> markPayoutCompleted({
    required String payoutId,
    String? transactionId,
  }) async {
    try {
      final payout = await _client
          .from('payout_requests')
          .select()
          .eq('id', payoutId)
          .single();

      await _client
          .from('payout_requests')
          .update({
            'status': 'completed',
            'wipay_transaction_id': transactionId,
            'processed_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);

      // Update total_paid_out on the driver/restaurant
      final amount = (payout['amount'] as num).toDouble();
      final type = payout['requester_type'] as String;

      if (type == 'driver' && payout['driver_id'] != null) {
        final driver = await _client
            .from(AppConstants.tableDrivers)
            .select('total_paid_out')
            .eq('id', payout['driver_id'])
            .single();
        final currentPaid =
            (driver['total_paid_out'] as num?)?.toDouble() ?? 0.0;
        await _client
            .from(AppConstants.tableDrivers)
            .update({
              'total_paid_out': currentPaid + amount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', payout['driver_id']);
      } else if (type == 'restaurant' && payout['restaurant_id'] != null) {
        final rest = await _client
            .from(AppConstants.tableRestaurants)
            .select('total_paid_out')
            .eq('id', payout['restaurant_id'])
            .single();
        final currentPaid = (rest['total_paid_out'] as num?)?.toDouble() ?? 0.0;
        await _client
            .from(AppConstants.tableRestaurants)
            .update({
              'total_paid_out': currentPaid + amount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', payout['restaurant_id']);
      }

      AppLogger.info('Payout marked completed: $payoutId');
    } catch (e) {
      AppLogger.error('Error marking payout completed: $e');
      rethrow;
    }
  }

  // ── Earnings helpers ───────────────────────────────────────

  Future<double> getRestaurantEarnings(String restaurantId) async {
    try {
      final orders = await _client
          .from(AppConstants.tableOrders)
          .select('total_amount, delivery_fee')
          .eq('restaurant_id', restaurantId)
          .eq('status', AppConstants.orderDelivered);
      double total = 0;
      for (final o in (orders as List)) {
        final orderTotal = (o['total_amount'] as num?)?.toDouble() ?? 0;
        final deliveryFee = (o['delivery_fee'] as num?)?.toDouble() ?? 0;
        total +=
            orderTotal -
            deliveryFee; // Restaurant gets order minus delivery fee
      }
      return total;
    } catch (e) {
      AppLogger.error('Error calculating restaurant earnings: $e');
      return 0;
    }
  }

  Future<double> getTotalPaidOut(String entityId, String type) async {
    try {
      final table = type == 'driver'
          ? AppConstants.tableDrivers
          : AppConstants.tableRestaurants;
      final row = await _client
          .from(table)
          .select('total_paid_out')
          .eq('id', entityId)
          .single();
      return (row['total_paid_out'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }
}

// ── Stripe Connect instant payout support ─────────────────────────────────

/// Represents a row in the payout_history table.
class PayoutRecord {
  final String id;
  final String driverId;
  final String? stripePayoutId;
  final double amount;
  final String currency;
  final String payoutType;
  final String status;
  final String? failureMessage;
  final DateTime createdAt;

  const PayoutRecord({
    required this.id,
    required this.driverId,
    this.stripePayoutId,
    required this.amount,
    required this.currency,
    required this.payoutType,
    required this.status,
    this.failureMessage,
    required this.createdAt,
  });

  factory PayoutRecord.fromJson(Map<String, dynamic> json) {
    return PayoutRecord(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      stripePayoutId: json['stripe_payout_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'usd',
      payoutType: json['payout_type'] as String? ?? 'instant',
      status: json['status'] as String? ?? 'pending',
      failureMessage: json['failure_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// StripePayoutService — handles Stripe Connect onboarding and instant
/// payouts by calling secured Supabase edge functions. Never calls Stripe
/// directly from the client side.
class StripePayoutService {
  StripePayoutService._();
  static final instance = StripePayoutService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Returns an onboarding URL to complete Stripe Connect KYC.
  Future<String> getStripeOnboardingUrl() async {
    final res = await _client.functions.invoke(
      'stripe-connect',
      body: {'action': 'onboard'},
    );
    _checkError(res);
    final url = (res.data as Map<String, dynamic>)['url'] as String?;
    if (url == null) throw Exception('No onboarding URL returned from server.');
    return url;
  }

  /// Fetches current Stripe Connect account status for the authenticated driver.
  Future<Map<String, dynamic>> getStripeStatus() async {
    final res = await _client.functions.invoke(
      'stripe-connect',
      body: {'action': 'status'},
    );
    _checkError(res);
    return res.data as Map<String, dynamic>;
  }

  /// Requests an instant (or standard) payout of [amountCents] (USD cents).
  /// Returns the full server response map on success.
  /// May throw [StripePayoutException] with [fallbackAvailable] == true when
  /// instant fails so the caller can offer a standard payout fallback.
  Future<Map<String, dynamic>> requestPayout({
    required int amountCents,
    String payoutType = 'instant',
  }) async {
    final res = await _client.functions.invoke(
      'payout-driver',
      body: {'amount_cents': amountCents, 'payout_type': payoutType},
    );

    final data = res.data as Map<String, dynamic>?;
    final status = res.status ?? 200;

    if (status >= 400) {
      final errMsg = data?['error'] as String? ?? 'Payout failed';
      final fallback = data?['fallback_available'] as bool? ?? false;
      final hint = data?['message'] as String?;
      throw StripePayoutException(
        errMsg,
        fallbackAvailable: fallback,
        hint: hint,
      );
    }

    if (data == null) throw Exception('Empty response from payout function');
    return data;
  }

  /// Returns the driver's payout history (most recent first, limit 50).
  Future<List<PayoutRecord>> getPayoutHistory(String driverId) async {
    final rows = await _client
        .from('payout_history')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(50);

    return (rows as List)
        .map((r) => PayoutRecord.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  void _checkError(FunctionResponse res) {
    final status = res.status ?? 200;
    if (status >= 400) {
      final data = res.data as Map<String, dynamic>?;
      final msg = data?['error'] as String? ?? 'Server error ($status)';
      throw Exception(msg);
    }
  }
}

/// Structured exception for Stripe payout errors, carrying a fallback flag.
class StripePayoutException implements Exception {
  final String message;
  final bool fallbackAvailable;
  final String? hint;

  const StripePayoutException(
    this.message, {
    this.fallbackAvailable = false,
    this.hint,
  });

  @override
  String toString() => message;
}
