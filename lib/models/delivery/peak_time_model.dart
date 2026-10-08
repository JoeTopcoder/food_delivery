/// Authoritative Dynamic Peak Time state, as returned by the backend
/// `get_peak_time_state` RPC. The client never computes any of these values
/// itself — it only reads them for display and passes the fee through checkout,
/// where the backend re-validates it.
class PeakTimeState {
  final int activeOrderCount;
  final int threshold;
  final bool enabled;
  final bool isPeakTime;
  final bool feeEnabled;
  final double fee;
  final int etaAdjustmentMinutes;
  final DateTime? updatedAt;

  const PeakTimeState({
    required this.activeOrderCount,
    required this.threshold,
    required this.enabled,
    required this.isPeakTime,
    required this.feeEnabled,
    required this.fee,
    required this.etaAdjustmentMinutes,
    this.updatedAt,
  });

  /// A safe, non-peak default used when the state cannot be loaded. Never treat
  /// this as authoritative for charging — checkout always re-validates on the
  /// backend.
  static const PeakTimeState off = PeakTimeState(
    activeOrderCount: 0,
    threshold: 80,
    enabled: true,
    isPeakTime: false,
    feeEnabled: false,
    fee: 0,
    etaAdjustmentMinutes: 0,
  );

  /// Orders still needed to activate Peak Time (0 once already active). Because
  /// activation is strictly `count > threshold`, this is `threshold + 1 - count`.
  int get ordersToActivate {
    if (isPeakTime) return 0;
    final needed = threshold + 1 - activeOrderCount;
    return needed < 0 ? 0 : needed;
  }

  /// The surcharge that actually applies right now (0 unless peak + fee enabled).
  double get applicableFee => (isPeakTime && feeEnabled) ? fee : 0;

  factory PeakTimeState.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    int toI(dynamic v) =>
        v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return PeakTimeState(
      activeOrderCount: toI(json['active_order_count']),
      threshold: toI(json['threshold']),
      enabled: json['enabled'] == true,
      isPeakTime: json['is_peak_time'] == true,
      feeEnabled: json['fee_enabled'] == true,
      fee: toD(json['fee']),
      etaAdjustmentMinutes: toI(json['eta_adjustment_minutes']),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse('${json['updated_at']}')
          : null,
    );
  }
}
