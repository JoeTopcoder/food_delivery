import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/features/voice_ordering/domain/models/parsed_voice_order.dart';

void main() {
  group('ParsedVoiceOrder.fromJson', () {
    test('parses a well-formed add_to_cart response', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'add_to_cart',
        'restaurant_query': 'Island Grill',
        'items': [
          {
            'name_query': 'jerk chicken meal',
            'quantity': 2,
            'modifiers': ['large', 'extra gravy'],
            'notes': null,
          },
        ],
        'confidence': 0.95,
      });

      expect(parsed.intent, VoiceOrderIntent.addToCart);
      expect(parsed.restaurantQuery, 'Island Grill');
      expect(parsed.items, hasLength(1));
      expect(parsed.items.first.nameQuery, 'jerk chicken meal');
      expect(parsed.items.first.quantity, 2);
      expect(parsed.items.first.modifiers, ['large', 'extra gravy']);
      expect(parsed.confidence, 0.95);
    });

    test('unrecognised intent string maps to unknown, never guessed', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'do_something_weird',
        'items': [],
        'confidence': 0.9,
      });
      expect(parsed.intent, VoiceOrderIntent.unknown);
    });

    test('parses remove_from_cart with an item_reference', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'remove_from_cart',
        'item_reference': 'the Ting',
        'items': [],
        'confidence': 0.9,
      });
      expect(parsed.intent, VoiceOrderIntent.removeFromCart);
      expect(parsed.itemReference, 'the Ting');
      expect(parsed.items, isEmpty);
    });

    test('parses update_quantity with item_reference and new_quantity', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'update_quantity',
        'item_reference': 'burger',
        'new_quantity': 3,
        'items': [],
        'confidence': 0.9,
      });
      expect(parsed.intent, VoiceOrderIntent.updateQuantity);
      expect(parsed.itemReference, 'burger');
      expect(parsed.newQuantity, 3);
    });

    test('parses clear_cart / view_cart / checkout with no item payload', () {
      for (final s in ['clear_cart', 'view_cart', 'checkout']) {
        final parsed = ParsedVoiceOrder.fromJson({
          'intent': s,
          'items': [],
          'confidence': 0.9,
        });
        expect(parsed.items, isEmpty);
        expect(parsed.itemReference, isNull);
      }
      expect(
        ParsedVoiceOrder.fromJson({'intent': 'clear_cart', 'confidence': 0.9}).intent,
        VoiceOrderIntent.clearCart,
      );
      expect(
        ParsedVoiceOrder.fromJson({'intent': 'view_cart', 'confidence': 0.9}).intent,
        VoiceOrderIntent.viewCart,
      );
      expect(
        ParsedVoiceOrder.fromJson({'intent': 'checkout', 'confidence': 0.9}).intent,
        VoiceOrderIntent.checkout,
      );
    });

    test('null/missing restaurant_query becomes null, not a literal string', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'add_to_cart',
        'items': [
          {'name_query': 'soup', 'quantity': 1, 'modifiers': []},
        ],
        'confidence': 0.8,
      });
      expect(parsed.restaurantQuery, isNull);
    });

    test('an empty name_query item is dropped, never passed through', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'add_to_cart',
        'items': [
          {'name_query': '', 'quantity': 1, 'modifiers': []},
          {'name_query': 'pizza', 'quantity': 1, 'modifiers': []},
        ],
        'confidence': 0.9,
      });
      expect(parsed.items, hasLength(1));
      expect(parsed.items.first.nameQuery, 'pizza');
    });

    test('quantity is clamped to a sane positive range, never zero/negative', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'add_to_cart',
        'items': [
          {'name_query': 'burger', 'quantity': -3, 'modifiers': []},
        ],
        'confidence': 0.9,
      });
      expect(parsed.items.first.quantity, greaterThanOrEqualTo(1));
    });

    test('confidence is clamped to [0, 1] even if the model misbehaves', () {
      final over = ParsedVoiceOrder.fromJson({'items': [], 'confidence': 5.0});
      final under = ParsedVoiceOrder.fromJson({'items': [], 'confidence': -2.0});
      expect(over.confidence, 1.0);
      expect(under.confidence, 0.0);
    });

    test('malformed/missing items list never throws, resolves to empty', () {
      final parsed = ParsedVoiceOrder.fromJson({'confidence': 0.0});
      expect(parsed.items, isEmpty);
      expect(parsed.intent, VoiceOrderIntent.unknown);
    });

    test('a per-unit-modifier split (two entries) round-trips cleanly', () {
      final parsed = ParsedVoiceOrder.fromJson({
        'intent': 'add_to_cart',
        'restaurant_query': null,
        'items': [
          {
            'name_query': 'oxtail meal',
            'quantity': 1,
            'modifiers': ['rice and peas'],
          },
          {
            'name_query': 'oxtail meal',
            'quantity': 1,
            'modifiers': ['festival'],
          },
        ],
        'confidence': 1.0,
      });
      expect(parsed.items, hasLength(2));
      expect(parsed.items[0].modifiers, ['rice and peas']);
      expect(parsed.items[1].modifiers, ['festival']);
    });
  });
}
