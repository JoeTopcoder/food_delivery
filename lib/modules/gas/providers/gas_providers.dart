import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/supabase_config.dart';
import '../../../providers/auth_user/auth_provider.dart';
import '../models/gas_models.dart';
import '../services/gas_service.dart';

final gasServiceProvider = Provider<GasService>((ref) => GasService(SupabaseConfig.client));

/// Live gas suppliers for the customer landing page.
final gasLiveSuppliersProvider = FutureProvider.autoDispose<List<GasSupplier>>((ref) {
  ref.keepAlive();
  return ref.watch(gasServiceProvider).getLiveSuppliers();
});

/// Active products for a supplier.
final gasProductsProvider =
    FutureProvider.autoDispose.family<List<GasProduct>, String>((ref, supplierId) {
  return ref.watch(gasServiceProvider).getProducts(supplierId);
});

/// The current customer's gas orders.
final myGasOrdersProvider = FutureProvider.autoDispose<List<GasOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Future.value(const <GasOrder>[]);
  return ref.watch(gasServiceProvider).getMyOrders(uid);
});

/// The supplier record owned by the current user (owner = supplier hat), if any.
final myGasSupplierProvider = FutureProvider.autoDispose<GasSupplier?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Future.value(null);
  return ref.watch(gasServiceProvider).getSupplierForOwner(uid);
});

/// Orders for a supplier dashboard.
final supplierGasOrdersProvider =
    FutureProvider.autoDispose.family<List<GasOrder>, String>((ref, supplierId) {
  return ref.watch(gasServiceProvider).getSupplierOrders(supplierId);
});

/// Admin: all suppliers (any status).
final allGasSuppliersProvider = FutureProvider.autoDispose<List<GasSupplier>>((ref) {
  return ref.watch(gasServiceProvider).getAllSuppliers();
});

/// Admin: financial rollup.
final gasFinancialsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(gasServiceProvider).getFinancials();
});
