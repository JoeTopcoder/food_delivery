import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/menu_model.dart';
import 'lunch_service.dart';

final lunchServiceProvider = Provider<LunchService>(
  (ref) => LunchService(Supabase.instance.client),
);

final lunchMenuProvider = FutureProvider.autoDispose<List<MenuItem>>(
  (ref) => ref.read(lunchServiceProvider).menu(),
);

final myStudentsProvider = FutureProvider.autoDispose<List<LinkedStudent>>(
  (ref) => ref.read(lunchServiceProvider).myStudents(),
);

final lunchOrdersProvider = FutureProvider.autoDispose<List<LunchOrder>>(
  (ref) => ref.read(lunchServiceProvider).myOrders(),
);

/// One line of the lunch cart.
class LunchCartLine {
  const LunchCartLine({required this.item, required this.quantity});

  final MenuItem item;
  final int quantity;

  double get lineTotal => item.price * quantity;

  LunchCartLine copyWith({int? quantity}) =>
      LunchCartLine(item: item, quantity: quantity ?? this.quantity);

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'quantity': quantity,
  };

  factory LunchCartLine.fromJson(Map<String, dynamic> j) => LunchCartLine(
    item: MenuItem.fromJson(Map<String, dynamic>.from(j['item'] as Map)),
    quantity: (j['quantity'] as num?)?.toInt() ?? 1,
  );
}

/// The lunch cart holds ITEMS AND NOTHING ELSE.
///
/// No recipient, no student, no school, no delivery fee. Who the lunch is for
/// is chosen at checkout, which is what lets the same basket be sent to a child
/// or kept for yourself without rebuilding it — and it keeps the fee, which
/// depends on that choice, out of a place that cannot authorise it.
class LunchCartNotifier extends StateNotifier<List<LunchCartLine>> {
  LunchCartNotifier() : super([]) {
    _load();
  }

  static const _key = 'lunch_cart_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      state = decoded
          .whereType<Map>()
          .map((e) => LunchCartLine.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // A cart that will not deserialise is discarded rather than crashing the
      // screen; the customer can add items again.
      state = [];
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(state.map((l) => l.toJson()).toList()),
      );
    } catch (_) {
      // Persistence is a convenience; losing it must not break the order.
    }
  }

  void add(MenuItem item) {
    final i = state.indexWhere((l) => l.item.id == item.id);
    state = i >= 0
        ? [
            for (var k = 0; k < state.length; k++)
              k == i ? state[k].copyWith(quantity: state[k].quantity + 1) : state[k],
          ]
        : [...state, LunchCartLine(item: item, quantity: 1)];
    _persist();
  }

  /// Replaces the cart with a set of items and quantities — what reorder does.
  /// It replaces rather than appends so a reorder produces the order the
  /// customer asked to repeat, not that order plus whatever was already there.
  void replaceWith(List<LunchCartLine> lines) {
    state = lines;
    _persist();
  }

  void setQuantity(String itemId, int quantity) {
    state = quantity <= 0
        ? state.where((l) => l.item.id != itemId).toList()
        : [
            for (final l in state)
              l.item.id == itemId ? l.copyWith(quantity: quantity) : l,
          ];
    _persist();
  }

  void remove(String itemId) => setQuantity(itemId, 0);

  void clear() {
    state = [];
    _persist();
  }

  /// The shape place_lunch_order expects: ids and quantities only. Prices are
  /// deliberately not sent — the server reads them from the menu.
  List<Map<String, dynamic>> toOrderItems() => [
    for (final l in state) {'item_id': l.item.id, 'qty': l.quantity},
  ];
}

final lunchCartProvider =
    StateNotifierProvider<LunchCartNotifier, List<LunchCartLine>>(
      (ref) => LunchCartNotifier(),
    );

final lunchSubtotalProvider = Provider<double>((ref) {
  return ref
      .watch(lunchCartProvider)
      .fold<double>(0, (sum, l) => sum + l.lineTotal);
});

final lunchItemCountProvider = Provider<int>((ref) {
  return ref.watch(lunchCartProvider).fold<int>(0, (sum, l) => sum + l.quantity);
});
