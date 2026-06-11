import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/config/app_constants.dart';

void main() {
  group('AppConstants.calculateServiceFee', () {
    // Helper: expected fee = (subtotal * 0.029) + 0.30 + 1.00, rounded to 2dp
    double expected(double subtotal) =>
        double.parse(((subtotal * 0.029) + 0.30 + 1.00).toStringAsFixed(2));

    test('\$5.00 order', () {
      // (5.00 * 0.029) + 0.30 + 1.00 = 0.145 + 0.30 + 1.00 = 1.445 → 1.45
      expect(AppConstants.calculateServiceFee(5.00), closeTo(1.45, 0.001));
      expect(AppConstants.calculateServiceFee(5.00), expected(5.00));
    });

    test('\$20.00 order', () {
      // (20.00 * 0.029) + 0.30 + 1.00 = 0.58 + 0.30 + 1.00 = 1.88
      expect(AppConstants.calculateServiceFee(20.00), closeTo(1.88, 0.001));
      expect(AppConstants.calculateServiceFee(20.00), expected(20.00));
    });

    test('\$100.00 order', () {
      // (100.00 * 0.029) + 0.30 + 1.00 = 2.90 + 0.30 + 1.00 = 4.20
      expect(AppConstants.calculateServiceFee(100.00), closeTo(4.20, 0.001));
      expect(AppConstants.calculateServiceFee(100.00), expected(100.00));
    });

    test('\$500.00 order', () {
      // (500.00 * 0.029) + 0.30 + 1.00 = 14.50 + 0.30 + 1.00 = 15.80
      expect(AppConstants.calculateServiceFee(500.00), closeTo(15.80, 0.001));
      expect(AppConstants.calculateServiceFee(500.00), expected(500.00));
    });

    test('result is rounded to 2 decimal places', () {
      // subtotal = 7.77 → (7.77 * 0.029) = 0.22533 → + 0.30 + 1.00 = 1.52533 → 1.53
      final fee = AppConstants.calculateServiceFee(7.77);
      final asString = fee.toString();
      final decimalPart = asString.contains('.') ? asString.split('.')[1] : '';
      expect(decimalPart.length, lessThanOrEqualTo(2));
      expect(fee, closeTo(1.53, 0.001));
    });

    test('zero subtotal', () {
      // 0 + 0.30 + 1.00 = 1.30
      expect(AppConstants.calculateServiceFee(0.00), closeTo(1.30, 0.001));
    });
  });

  group('AppConstants.calculateStripeFee', () {
    test('\$20.00 order stripe portion', () {
      // (20.00 * 0.029) + 0.30 = 0.58 + 0.30 = 0.88
      expect(AppConstants.calculateStripeFee(20.00), closeTo(0.88, 0.001));
    });

    test('\$100.00 order stripe portion', () {
      // (100.00 * 0.029) + 0.30 = 2.90 + 0.30 = 3.20
      expect(AppConstants.calculateStripeFee(100.00), closeTo(3.20, 0.001));
    });

    test('stripe fee + platform flat fee = service fee', () {
      for (final subtotal in [5.0, 20.0, 100.0, 500.0]) {
        final stripeFee = AppConstants.calculateStripeFee(subtotal);
        final serviceFee = AppConstants.calculateServiceFee(subtotal);
        expect(
          serviceFee,
          closeTo(stripeFee + AppConstants.platformFlatFee, 0.001),
          reason: 'Failed for subtotal \$$subtotal',
        );
      }
    });
  });

  group('Multi-restaurant order fee', () {
    test('two restaurants summed subtotal', () {
      // Restaurant A: $15.00, Restaurant B: $25.00 → subtotal = $40.00
      const subtotal = 40.00;
      // (40.00 * 0.029) + 0.30 + 1.00 = 1.16 + 0.30 + 1.00 = 2.46
      expect(AppConstants.calculateServiceFee(subtotal), closeTo(2.46, 0.001));
    });

    test('three restaurants summed subtotal', () {
      // $10 + $20 + $30 = $60
      const subtotal = 60.00;
      // (60.00 * 0.029) + 0.30 + 1.00 = 1.74 + 0.30 + 1.00 = 3.04
      expect(AppConstants.calculateServiceFee(subtotal), closeTo(3.04, 0.001));
    });
  });

  group('Ride order fee', () {
    test('minimum fare ride (\$8.00)', () {
      // (8.00 * 0.029) + 0.30 + 1.00 = 0.232 + 0.30 + 1.00 = 1.532 → 1.53
      expect(AppConstants.calculateServiceFee(8.00), closeTo(1.53, 0.001));
    });

    test('longer ride (\$35.00)', () {
      // (35.00 * 0.029) + 0.30 + 1.00 = 1.015 + 0.30 + 1.00 = 2.315 → 2.32
      expect(AppConstants.calculateServiceFee(35.00), closeTo(2.32, 0.001));
    });

    test('airport ride with surcharge (\$50.00 fare)', () {
      // (50.00 * 0.029) + 0.30 + 1.00 = 1.45 + 0.30 + 1.00 = 2.75
      expect(AppConstants.calculateServiceFee(50.00), closeTo(2.75, 0.001));
    });
  });

  group('Fee constants', () {
    test('stripe fee rate is 2.9%', () {
      expect(AppConstants.stripeFeeRate, closeTo(0.029, 0.0001));
    });

    test('stripe fixed fee is \$0.30', () {
      expect(AppConstants.stripeFixedFee, closeTo(0.30, 0.001));
    });

    test('platform flat fee is \$1.00', () {
      expect(AppConstants.platformFlatFee, closeTo(1.00, 0.001));
    });
  });
}
