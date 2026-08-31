import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/screens/customer/home_screen.dart';

void main() {
  group('isBirthdayToday', () {
    test('matches when month and day are the same, regardless of year', () {
      expect(
        isBirthdayToday(DateTime(1995, 8, 31), DateTime(2026, 8, 31)),
        isTrue,
      );
      expect(
        isBirthdayToday(DateTime(1970, 3, 15), DateTime(2026, 3, 15)),
        isTrue,
      );
    });

    test('does not match a different day', () {
      expect(
        isBirthdayToday(DateTime(1995, 8, 31), DateTime(2026, 8, 30)),
        isFalse,
      );
    });

    test('does not match a different month, same day-of-month', () {
      expect(
        isBirthdayToday(DateTime(1995, 8, 31), DateTime(2026, 9, 31 - 30)),
        isFalse,
      );
    });

    test('a Feb 29 birthday only matches on an actual Feb 29', () {
      // Leap year — matches.
      expect(
        isBirthdayToday(DateTime(2000, 2, 29), DateTime(2028, 2, 29)),
        isTrue,
      );
      // Non-leap year has no Feb 29 at all — DateTime(2026, 2, 29) normalizes
      // to Mar 1, which correctly does NOT match a Feb 29 birthday.
      expect(
        isBirthdayToday(DateTime(2000, 2, 29), DateTime(2026, 2, 29)),
        isFalse,
      );
    });

    test('defaults to DateTime.now() when no reference date is passed', () {
      final now = DateTime.now();
      expect(isBirthdayToday(DateTime(1990, now.month, now.day)), isTrue);
    });
  });
}
