import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/peak_time_model.dart';
import '../utils/app_logger.dart';

/// Backend-authoritative Dynamic Peak Time state, shared across the whole app
/// (customer, driver, admin, checkout). It is fetched from the
/// `get_peak_time_state` RPC — never computed on the client — and refreshed,
/// with debouncing, whenever orders change (active-count moves) or an admin
/// changes the Peak Time configuration.
///
/// Realtime here is a lightweight *invalidation* signal: an event just triggers
/// one debounced authoritative RPC refresh rather than downloading any orders.
class PeakTimeNotifier extends StateNotifier<AsyncValue<PeakTimeState>> {
  PeakTimeNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _configChannel;
  Timer? _debounce;
  Timer? _pollFallback;
  bool _disposed = false;

  Future<void> _init() async {
    await refresh();
    _subscribe();
    // Low-frequency safety net that also recovers from missed realtime events
    // (e.g. after a background/foreground transition or a dropped socket).
    _pollFallback = Timer.periodic(
      const Duration(minutes: 2),
      (_) => refresh(),
    );
  }

  /// Fetches the authoritative state. Keeps the last good value on error so the
  /// UI never flashes to a wrong state, and falls back to a safe non-peak value
  /// only when nothing has ever loaded.
  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final res = await SupabaseConfig.client.rpc('get_peak_time_state');
      if (_disposed) return;
      final map = res is Map<String, dynamic>
          ? res
          : Map<String, dynamic>.from(res as Map);
      state = AsyncValue.data(PeakTimeState.fromJson(map));
    } catch (e, st) {
      AppLogger.error('Peak time refresh failed: $e');
      if (_disposed) return;
      // Preserve the last known value; only surface a safe default if we have
      // never loaded successfully.
      if (!state.hasValue) {
        state = const AsyncValue.data(PeakTimeState.off);
      }
      // Keep the error available for diagnostics without dropping the value.
      if (state.hasValue) {
        state = AsyncValue.data(state.value!);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void _subscribe() {
    final client = SupabaseConfig.client;
    // Orders: any insert/update/delete may move the active-order count across
    // the threshold. We never read the changed row — just schedule a refresh.
    _ordersChannel = client
        .channel('peak_time_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();

    // Config: an admin changing the threshold / enabled / fee should update the
    // state promptly.
    _configChannel = client
        .channel('peak_time_config')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_config',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  /// Coalesces bursts of order changes into a single authoritative refresh so a
  /// storm of order updates can't cause an RPC storm.
  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _pollFallback?.cancel();
    final client = SupabaseConfig.client;
    if (_ordersChannel != null) client.removeChannel(_ordersChannel!);
    if (_configChannel != null) client.removeChannel(_configChannel!);
    super.dispose();
  }
}

/// App-wide singleton (kept alive) so every screen shares one authoritative
/// state and one set of subscriptions.
final peakTimeProvider =
    StateNotifierProvider<PeakTimeNotifier, AsyncValue<PeakTimeState>>((ref) {
  return PeakTimeNotifier();
});

/// Convenience: the current state or a safe non-peak default while loading.
final peakTimeStateProvider = Provider<PeakTimeState>((ref) {
  return ref.watch(peakTimeProvider).valueOrNull ?? PeakTimeState.off;
});
