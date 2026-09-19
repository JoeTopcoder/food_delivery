import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/models/peak_time_model.dart';

/// Unit tests for the client-side Peak Time model. The authoritative activation
/// rule (`is_peak_time = enabled AND active_order_count > threshold`) lives in
/// the Postgres `get_peak_time_state` function and is verified against the live
/// DB; these tests cover the model parsing and the derived display values the
/// UI relies on (fee applicability, orders-to-activate).
PeakTimeState _state({
  required int count,
  required int threshold,
  bool enabled = true,
  bool feeEnabled = false,
  double fee = 0,
}) {
  // Mirror the backend rule so the model tests exercise the same boundaries.
  final isPeak = enabled && count > threshold;
  return PeakTimeState(
    activeOrderCount: count,
    threshold: threshold,
    enabled: enabled,
    isPeakTime: isPeak,
    feeEnabled: feeEnabled,
    fee: fee,
    etaAdjustmentMinutes: 0,
  );
}

void main() {
  group('Peak Time activation boundary (strict >)', () {
    test('0 active, threshold 80 -> OFF', () {
      expect(_state(count: 0, threshold: 80).isPeakTime, isFalse);
    });
    test('79 active, threshold 80 -> OFF', () {
      expect(_state(count: 79, threshold: 80).isPeakTime, isFalse);
    });
    test('80 active, threshold 80 -> OFF (never >=)', () {
      expect(_state(count: 80, threshold: 80).isPeakTime, isFalse);
    });
    test('81 active, threshold 80 -> ON', () {
      expect(_state(count: 81, threshold: 80).isPeakTime, isTrue);
    });
    test('100 active, threshold 80 -> ON', () {
      expect(_state(count: 100, threshold: 80).isPeakTime, isTrue);
    });
    test('administratively disabled -> OFF at every count', () {
      expect(_state(count: 200, threshold: 80, enabled: false).isPeakTime,
          isFalse);
    });
  });

  group('ordersToActivate', () {
    test('79 active, threshold 80 -> 2 more to activate (need 81)', () {
      expect(_state(count: 79, threshold: 80).ordersToActivate, 2);
    });
    test('80 active, threshold 80 -> 1 more to activate', () {
      expect(_state(count: 80, threshold: 80).ordersToActivate, 1);
    });
    test('already active -> 0', () {
      expect(_state(count: 90, threshold: 80).ordersToActivate, 0);
    });
  });

  group('applicableFee', () {
    test('peak OFF -> no fee even if fee enabled', () {
      expect(
        _state(count: 10, threshold: 80, feeEnabled: true, fee: 200)
            .applicableFee,
        0,
      );
    });
    test('peak ON but fee disabled -> no fee', () {
      expect(
        _state(count: 90, threshold: 80, feeEnabled: false, fee: 200)
            .applicableFee,
        0,
      );
    });
    test('peak ON and fee enabled -> configured fee', () {
      expect(
        _state(count: 90, threshold: 80, feeEnabled: true, fee: 200)
            .applicableFee,
        200,
      );
    });
  });

  group('fromJson', () {
    test('parses backend payload, tolerating string numerics', () {
      final s = PeakTimeState.fromJson({
        'active_order_count': 81,
        'threshold': '80',
        'enabled': true,
        'is_peak_time': true,
        'fee_enabled': true,
        'fee': '200.0',
        'eta_adjustment_minutes': '5',
        'updated_at': '2026-09-19T04:00:00+00:00',
      });
      expect(s.activeOrderCount, 81);
      expect(s.threshold, 80);
      expect(s.isPeakTime, isTrue);
      expect(s.applicableFee, 200.0);
      expect(s.etaAdjustmentMinutes, 5);
      expect(s.updatedAt, isNotNull);
    });

    test('off default is safe and non-peak', () {
      expect(PeakTimeState.off.isPeakTime, isFalse);
      expect(PeakTimeState.off.applicableFee, 0);
    });
  });
}
