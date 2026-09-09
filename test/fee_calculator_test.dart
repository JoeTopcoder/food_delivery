import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/config/app_constants.dart';

/// Service-fee arithmetic.
///
/// These assertions are derived from the fee constants rather than written as
/// literals. The previous version hardcoded US$0.30 / US$1.00 and the old
/// additive formula, so it broke twice over: once when the platform was
/// redenominated to JMD, and again when the fee started being solved rather
/// than approximated. Deriving means a future rate change — or the move from
/// Stripe to NCB — updates the expectations with the constants.
void main() {
  // f = ((base * rate) + fixed + flat) / (1 - rate)
  //
  // The fee is charged on the total captured, and the fee is itself part of
  // that total, so it is solved rather than added on top.
  double expectedFee(double base) {
    final raw =
        ((base * AppConstants.stripeFeeRate) +
            AppConstants.stripeFixedFee +
            AppConstants.platformFlatFee) /
        (1 - AppConstants.stripeFeeRate);
    return double.parse(raw.toStringAsFixed(2));
  }

  // Realistic Jamaican baskets: a patty and a box lunch through to a large
  // family order.
  const subtotals = <double>[0, 450, 1200, 1860, 5400, 15000];

  group('AppConstants.calculateServiceFee', () {
    for (final subtotal in subtotals) {
      test('J\$${subtotal.toStringAsFixed(0)} order', () {
        expect(
          AppConstants.calculateServiceFee(subtotal),
          closeTo(expectedFee(subtotal), 0.001),
        );
      });
    }

    test('a zero subtotal still recovers the fixed costs', () {
      // Nothing ordered still costs the processor its per-transaction charge,
      // so the fee floor is the fixed components, grossed up.
      final fee = AppConstants.calculateServiceFee(0);
      expect(fee, greaterThan(AppConstants.platformFlatFee));
      expect(fee, closeTo(expectedFee(0), 0.001));
    });

    test('rises with basket size', () {
      var previous = -1.0;
      for (final subtotal in subtotals) {
        final fee = AppConstants.calculateServiceFee(subtotal);
        expect(fee, greaterThan(previous));
        previous = fee;
      }
    });

    test('is rounded to at most 2 decimal places', () {
      for (final subtotal in [777.0, 1234.56, 99.99]) {
        final asString = AppConstants.calculateServiceFee(subtotal).toString();
        final decimals = asString.contains('.')
            ? asString.split('.')[1].length
            : 0;
        expect(decimals, lessThanOrEqualTo(2), reason: 'subtotal $subtotal');
      }
    });

    test('otherCharges are part of the base', () {
      // Delivery is captured on the same transaction, so the processor takes
      // its cut of that too and the fee has to recover it.
      final withDelivery = AppConstants.calculateServiceFee(
        1200,
        otherCharges: 775,
      );
      expect(withDelivery, closeTo(expectedFee(1200 + 775), 0.001));
      expect(withDelivery, greaterThan(AppConstants.calculateServiceFee(1200)));
    });
  });

  group('AppConstants.calculateStripeFee', () {
    for (final subtotal in [1200.0, 5400.0]) {
      test('J\$${subtotal.toStringAsFixed(0)} processor portion', () {
        final expected =
            (subtotal * AppConstants.stripeFeeRate) +
            AppConstants.stripeFixedFee;
        expect(
          AppConstants.calculateStripeFee(subtotal),
          closeTo(double.parse(expected.toStringAsFixed(2)), 0.001),
        );
      });
    }

    test(
      'the fee leaves exactly the flat margin after the processor is paid',
      () {
        // The point of solving the fee instead of adding it on: whatever the
        // basket, the platform keeps platformFlatFee once the processor has
        // taken its percentage of the WHOLE captured amount, fee included.
        //
        // The old test asserted serviceFee == stripeFee + flat, which was only
        // true under the additive formula and quietly stopped holding.
        for (final subtotal in subtotals) {
          final fee = AppConstants.calculateServiceFee(subtotal);
          final captured = subtotal + fee;
          final processorTakes =
              (captured * AppConstants.stripeFeeRate) +
              AppConstants.stripeFixedFee;
          expect(
            fee - processorTakes,
            closeTo(AppConstants.platformFlatFee, 0.02),
            reason: 'subtotal J\$$subtotal',
          );
        }
      },
    );
  });

  group('Fee constants', () {
    test('processor rate is 2.9%', () {
      expect(AppConstants.stripeFeeRate, closeTo(0.029, 0.0001));
    });

    test('the fixed components are on the JMD scale, not the old USD one', () {
      // Guards the redenomination: US$0.30 and US$1.00 became J$46.50 and
      // J$155.00. If either ever reads as a sub-dollar figure again, the
      // platform is silently charging about 1/155th of its intended fee.
      expect(AppConstants.stripeFixedFee, greaterThan(1.0));
      expect(AppConstants.platformFlatFee, greaterThan(1.0));
      expect(AppConstants.stripeFixedFee, closeTo(46.50, 0.001));
      expect(AppConstants.platformFlatFee, closeTo(155.00, 0.001));
    });

    test('currency is JMD', () {
      expect(AppConstants.currencyCode, 'JMD');
      expect(AppConstants.currencySymbol, r'J$');
    });
  });
}
