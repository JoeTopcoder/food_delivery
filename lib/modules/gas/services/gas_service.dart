// Cooking Gas module service — thin wrapper over Supabase tables + the gas_*
// SECURITY DEFINER RPCs. All pricing/stock/state logic lives in the DB; this
// only reads rows and invokes the audited RPCs.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gas_models.dart';

class GasService {
  final SupabaseClient _db;
  GasService(this._db);

  // ── Customer reads ────────────────────────────────────────────────────────

  /// Live suppliers only (RLS also restricts to approved+active; we add the
  /// open/operational filter for the customer landing page).
  Future<List<GasSupplier>> getLiveSuppliers() async {
    final rows = await _db
        .from('gas_suppliers')
        .select()
        .eq('verification_status', 'approved')
        .eq('is_active', true)
        .eq('delivery_operational', true)
        .order('business_name');
    return (rows as List).map((r) => GasSupplier.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<List<GasProduct>> getProducts(String supplierId) async {
    final rows = await _db
        .from('gas_products')
        .select()
        .eq('supplier_id', supplierId)
        .eq('is_active', true)
        .order('size_lb');
    return (rows as List).map((r) => GasProduct.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Price quote (delivery + service + total) BEFORE placing — no side effects.
  Future<Map<String, dynamic>> quote({
    required String supplierId,
    required List<GasCartLine> lines,
    required double lat,
    required double lng,
  }) async {
    final res = await _db.rpc('gas_quote', params: {
      'p_supplier': supplierId,
      'p_items': lines.map((l) => l.toItemJson()).toList(),
      'p_lat': lat,
      'p_lng': lng,
    });
    return (res as Map).cast<String, dynamic>();
  }

  // ── Placement + payment ───────────────────────────────────────────────────

  /// Places a gas order via the server-authoritative RPC. Returns the new order id.
  Future<String> placeOrder({
    required String supplierId,
    required List<GasCartLine> lines,
    required String address,
    required double lat,
    required double lng,
    String paymentMethod = 'wallet',
    String? notes,
  }) async {
    final res = await _db.rpc('place_gas_order', params: {
      'p_supplier': supplierId,
      'p_items': lines.map((l) => l.toItemJson()).toList(),
      'p_address': address,
      'p_lat': lat,
      'p_lng': lng,
      'p_payment_method': paymentMethod,
      'p_notes': notes,
    });
    return res.toString();
  }

  /// Pay an order from the HotBite wallet (audited ledger).
  Future<void> payFromWallet(String orderId) async {
    await _db.rpc('gas_pay_wallet', params: {'p_order': orderId});
  }

  /// Mark an order Cash on Delivery (collected when delivered).
  Future<void> setCashOnDelivery(String orderId) async {
    await _db.rpc('gas_set_cash', params: {'p_order': orderId});
  }

  /// Pay by saved card via the gas-pay-order edge function (Stripe).
  Future<void> payByCard(String orderId, String paymentMethodId) async {
    final res = await _db.functions.invoke('gas-pay-order', body: {
      'orderId': orderId,
      'method': 'stripe',
      'paymentMethodId': paymentMethodId,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
  }

  /// Fetch a single gas order by id (owner/customer/admin per RLS).
  Future<GasOrder?> getOrder(String orderId) async {
    final row = await _db.from('gas_orders').select().eq('id', orderId).maybeSingle();
    return row == null ? null : GasOrder.fromMap(row);
  }

  // ── Orders (customer + supplier share the same table via RLS) ─────────────

  Future<List<GasOrder>> getMyOrders(String customerId) async {
    final rows = await _db
        .from('gas_orders')
        .select()
        .eq('customer_id', customerId)
        .order('placed_at', ascending: false);
    return (rows as List).map((r) => GasOrder.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<List<GasOrder>> getSupplierOrders(String supplierId) async {
    final rows = await _db
        .from('gas_orders')
        .select()
        .eq('supplier_id', supplierId)
        .order('placed_at', ascending: false);
    return (rows as List).map((r) => GasOrder.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// The supplier record owned by [ownerId], if any (owner wears the supplier hat).
  Future<GasSupplier?> getSupplierForOwner(String ownerId) async {
    final row = await _db
        .from('gas_suppliers')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    return row == null ? null : GasSupplier.fromMap(row);
  }

  // ── Lifecycle (role-gated inside the RPC) ─────────────────────────────────

  Future<void> transition(String orderId, String newStatus, {String? reason}) async {
    await _db.rpc('gas_order_transition',
        params: {'p_order': orderId, 'p_new': newStatus, 'p_reason': reason});
  }

  Future<void> decideExchange(String exchangeId, String decision, {String? reason}) async {
    await _db.rpc('gas_exchange_decide',
        params: {'p_exchange': exchangeId, 'p_decision': decision, 'p_reason': reason});
  }

  Future<List<Map<String, dynamic>>> getOperators(String supplierId) async {
    final rows = await _db
        .from('gas_delivery_operators')
        .select()
        .eq('supplier_id', supplierId)
        .eq('is_active', true)
        .order('name');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> assignOperator(String orderId, String operatorId, {int payoutCents = 0}) async {
    await _db.rpc('gas_assign_operator',
        params: {'p_order': orderId, 'p_operator': operatorId, 'p_payout_cents': payoutCents});
  }

  // ── Admin ─────────────────────────────────────────────────────────────────

  Future<List<GasSupplier>> getAllSuppliers() async {
    final rows = await _db.from('gas_suppliers').select().order('created_at', ascending: false);
    return (rows as List).map((r) => GasSupplier.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> setSupplierStatus(String supplierId, String status) async {
    await _db.from('gas_suppliers').update({'verification_status': status}).eq('id', supplierId);
  }

  Future<void> setSupplierOperational(String supplierId, bool operational) async {
    await _db.from('gas_suppliers').update({'delivery_operational': operational}).eq('id', supplierId);
  }

  /// Admin: all gas orders across every supplier (RLS admin policy permits).
  Future<List<GasOrder>> getAllOrders() async {
    final rows = await _db
        .from('gas_orders')
        .select()
        .order('placed_at', ascending: false)
        .limit(200);
    return (rows as List).map((r) => GasOrder.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getFinancials() async {
    final res = await _db.rpc('get_gas_financials_admin');
    return (res as Map).cast<String, dynamic>();
  }
}
