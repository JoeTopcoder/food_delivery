import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/menu_model.dart';
import '../../../utils/app_logger.dart';

/// A student this parent is allowed to order for, with the school currently on
/// file. The school shown at checkout is read fresh each time rather than
/// remembered, because a student can move school between orders.
class LinkedStudent {
  const LinkedStudent({
    required this.id,
    required this.name,
    required this.walletId,
    this.schoolId,
    this.schoolName,
    this.schoolAddress,
  });

  final String id;
  final String name;
  final String walletId;
  final String? schoolId;
  final String? schoolName;
  final String? schoolAddress;

  /// A student with no school on file cannot receive a delivery, and the
  /// checkout screen says so rather than failing at the end.
  bool get hasSchool => schoolId != null && (schoolAddress?.isNotEmpty ?? false);

  factory LinkedStudent.fromJson(Map<String, dynamic> j) => LinkedStudent(
    id: (j['student_id'] ?? '').toString(),
    name: (j['student_name'] ?? 'Student').toString(),
    walletId: (j['wallet_id'] ?? '').toString(),
    schoolId: j['school_id']?.toString(),
    schoolName: j['school_name']?.toString(),
    schoolAddress: j['school_address']?.toString(),
  );
}

/// What an order would cost. Always produced by the server, never assembled in
/// the app: the fee depends on who the food is for, and that decision carries
/// an authorisation check the client cannot make.
class LunchQuote {
  const LunchQuote({
    required this.recipientType,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.schoolName,
    this.schoolAddress,
  });

  final String recipientType;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? schoolName;
  final String? schoolAddress;

  static double _d(dynamic v) => v is num ? v.toDouble() : 0.0;

  factory LunchQuote.fromJson(Map<String, dynamic> j) => LunchQuote(
    recipientType: (j['recipient_type'] ?? 'self').toString(),
    subtotal: _d(j['subtotal']),
    deliveryFee: _d(j['delivery_fee']),
    total: _d(j['total']),
    schoolName: j['school_name']?.toString(),
    schoolAddress: j['school_address']?.toString(),
  );
}

/// A past lunch order, as the history screen needs it: who it was for, where it
/// went, and enough of the items to put the same order back in the cart.
class LunchOrder {
  const LunchOrder({
    required this.id,
    required this.recipientType,
    required this.total,
    required this.status,
    required this.orderedAt,
    required this.lines,
    this.schoolName,
    this.studentId,
  });

  final String id;
  final String recipientType;
  final double total;
  final String status;
  final DateTime orderedAt;

  /// menu_item_id -> quantity, plus the name as it was ordered. The name is
  /// kept from the order rather than looked up, so history reads correctly even
  /// after an item is renamed or withdrawn from the menu.
  final List<({String itemId, String name, int quantity})> lines;

  final String? schoolName;

  /// Resolved to a name by the screen against the parent's own linked students,
  /// rather than joined here — orders has two foreign keys into users, and an
  /// ambiguous embed is a worse trade than a lookup the screen already has.
  final String? studentId;

  bool get isForStudent => recipientType == 'student';

  factory LunchOrder.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['order_items'] as List?) ?? const [];
    return LunchOrder(
      id: (j['id'] ?? '').toString(),
      recipientType: (j['recipient_type'] ?? 'self').toString(),
      total: (j['total_amount'] as num?)?.toDouble() ?? 0,
      status: (j['status'] ?? 'pending').toString(),
      orderedAt:
          DateTime.tryParse((j['ordered_at'] ?? j['created_at'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
      schoolName: j['school_name']?.toString(),
      studentId: j['student_id']?.toString(),
      lines: [
        for (final raw in rawItems.whereType<Map>())
          (
            itemId: (raw['menu_item_id'] ?? '').toString(),
            name: (raw['item_name'] ?? 'Item').toString(),
            quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
          ),
      ],
    );
  }
}

class LunchService {
  LunchService(this._client);

  final SupabaseClient _client;

  /// The lunch menu — providers are stores with store_type 'lunch', so this
  /// reuses the same menus table as food and grocery.
  Future<List<MenuItem>> menu() async {
    final rows = await _client
        .from('menus')
        .select('*, restaurants!inner(id, store_type, is_verified)')
        .eq('is_available', true)
        .eq('restaurants.store_type', 'lunch')
        .eq('restaurants.is_verified', true)
        .order('category')
        .order('price');
    return (rows as List)
        .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Past lunch orders. `recipient_type` is only ever set by place_lunch_order,
  /// so it is what separates lunch from the customer's food and grocery orders.
  Future<List<LunchOrder>> myOrders() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('orders')
        .select(
          'id, recipient_type, student_id, school_name, total_amount, status, '
          'ordered_at, created_at, '
          'order_items(menu_item_id, item_name, quantity)',
        )
        .eq('user_id', uid)
        .not('recipient_type', 'is', null)
        .order('ordered_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => LunchOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// The menu items behind a past order, for reorder. Items that have since
  /// been withdrawn simply do not come back — the reorder screen says which,
  /// rather than quietly rebuilding a smaller basket.
  Future<List<MenuItem>> itemsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('menus')
        .select()
        .inFilter('id', ids)
        .eq('is_available', true);
    return (rows as List)
        .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<LinkedStudent>> myStudents() async {
    final rows = await _client.rpc('get_my_students');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((r) => LinkedStudent.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Links a student by the wallet ID shown on their own profile. The parent is
  /// taken from the session server-side, so this cannot link on someone else's
  /// behalf.
  Future<String> linkStudent(String walletId) async {
    final res = await _client.rpc(
      'link_student_by_wallet_id',
      params: {'p_wallet_id': walletId.trim()},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : const {};
    return (map['student_name'] ?? 'Student').toString();
  }

  /// Re-priced whenever the recipient changes. [studentId] null means the
  /// order is for the parent themselves, which is the default state.
  Future<LunchQuote> quote({
    required List<Map<String, dynamic>> items,
    String? studentId,
  }) async {
    final res = await _client.rpc(
      'quote_lunch_order',
      params: {'p_items': items, 'p_student_id': studentId},
    );
    return LunchQuote.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Places the order. Everything that matters — prices, fee, school address,
  /// and whether this parent may order for this student — is recomputed
  /// server-side; these arguments are a request, not a statement of fact.
  Future<Map<String, dynamic>> placeOrder({
    required List<Map<String, dynamic>> items,
    String? studentId,
    String? instructions,
  }) async {
    try {
      final res = await _client.rpc(
        'place_lunch_order',
        params: {
          'p_items': items,
          'p_student_id': studentId,
          'p_instructions': instructions,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      AppLogger.error('Lunch order failed: $e');
      rethrow;
    }
  }
}
