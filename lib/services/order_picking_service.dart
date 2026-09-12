import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pick_model.dart';
import '../utils/app_logger.dart';

/// Store-side grocery order fulfilment: read the pick list, mark items picked
/// (by scan or by hand), and link barcodes to products on the fly.
///
/// All writes go through SECURITY DEFINER RPCs (pick_scan / pick_set_item /
/// assign_barcode) that self-gate to the store owner or an admin.
class OrderPickingService {
  final SupabaseClient _client;
  OrderPickingService(this._client);

  /// The order's lines with each product's linked barcode + image, joined in
  /// Dart (no reliance on a PostgREST FK embed).
  Future<List<PickLine>> getPickList(String orderId) async {
    try {
      final itemRows = await _client
          .from('order_items')
          .select('id, menu_item_id, item_name, quantity, picked_quantity')
          .eq('order_id', orderId);

      final items = (itemRows as List).cast<Map<String, dynamic>>();
      final ids = items
          .map((r) => r['menu_item_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final products = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final prodRows = await _client
            .from('menus')
            .select('id, barcode, image_url')
            .inFilter('id', ids);
        for (final p in (prodRows as List).cast<Map<String, dynamic>>()) {
          products[p['id'] as String] = p;
        }
      }

      final lines = items.map((r) {
        final pid = r['menu_item_id'] as String?;
        final prod = pid != null ? products[pid] : null;
        return PickLine(
          orderItemId: r['id'] as String,
          menuItemId: pid ?? '',
          name: (r['item_name'] as String?) ?? 'Item',
          quantity: (r['quantity'] as num?)?.toInt() ?? 1,
          pickedQuantity: (r['picked_quantity'] as num?)?.toInt() ?? 0,
          barcode: prod?['barcode'] as String?,
          imageUrl: prod?['image_url'] as String?,
        );
      }).toList();

      // Unpicked first, then by name — keeps the "what's left" at the top.
      lines.sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return lines;
    } catch (e) {
      AppLogger.error('Error loading pick list: $e');
      rethrow;
    }
  }

  /// Lightweight picking progress for an order (no menus join) — for the
  /// order-list card badge.
  Future<PickProgress> getPickProgress(String orderId) async {
    try {
      final rows = await _client
          .from('order_items')
          .select('quantity, picked_quantity')
          .eq('order_id', orderId);
      var pickedLines = 0, totalLines = 0, pickedUnits = 0, totalUnits = 0;
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final qty = (r['quantity'] as num?)?.toInt() ?? 0;
        final picked = (r['picked_quantity'] as num?)?.toInt() ?? 0;
        totalLines += 1;
        totalUnits += qty;
        pickedUnits += picked;
        if (picked >= qty) pickedLines += 1;
      }
      return PickProgress(
        pickedLines: pickedLines,
        totalLines: totalLines,
        pickedUnits: pickedUnits,
        totalUnits: totalUnits,
      );
    } catch (e) {
      AppLogger.error('Error loading pick progress: $e');
      rethrow;
    }
  }

  /// Register one scanned unit of [code] against the order. See the RPC for the
  /// returned `status` values (picked / already_complete / not_in_order /
  /// unknown_code).
  Future<Map<String, dynamic>> scan(String orderId, String code) async {
    try {
      final res = await _client.rpc(
        'pick_scan',
        params: {'p_order_id': orderId, 'p_code': code},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      AppLogger.error('Error scanning pick: $e');
      rethrow;
    }
  }

  /// Manually set a line's picked count (tap +/- or mark done/undone).
  Future<Map<String, dynamic>> setItemPicked(
    String orderItemId,
    int pickedQuantity,
  ) async {
    try {
      final res = await _client.rpc(
        'pick_set_item',
        params: {
          'p_order_item_id': orderItemId,
          'p_picked_quantity': pickedQuantity,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      AppLogger.error('Error setting picked item: $e');
      rethrow;
    }
  }

  /// Link a scanned code to a product so it auto-matches next time.
  Future<void> assignBarcode(String productId, String barcode) async {
    try {
      await _client.rpc(
        'assign_barcode',
        params: {'p_product_id': productId, 'p_barcode': barcode},
      );
    } catch (e) {
      AppLogger.error('Error assigning barcode: $e');
      rethrow;
    }
  }
}
