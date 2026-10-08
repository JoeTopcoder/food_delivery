import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_driver/models/menu_model.dart';
import 'package:food_driver/providers/auth_user/user_provider.dart' show CartItem;
import 'package:food_driver/services/ai/speech_service.dart';
import 'package:food_driver/services/food/menu_service.dart';
import 'package:food_driver/services/food/restaurant_service.dart';
import 'package:food_driver/features/voice_ordering/data/voice_order_parser_service.dart';
import 'package:food_driver/features/voice_ordering/data/voice_order_repository.dart';

MenuItem _item(String id, String name, {double price = 10}) => MenuItem(
      id: id,
      restaurantId: 'r1',
      name: name,
      price: price,
      category: 'Entrees',
      createdAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // findMatchingCartItem is pure logic — no network call happens for it,
  // but the repository's constructor still wants real service instances
  // for typing. A SupabaseClient can be constructed offline (it doesn't
  // connect until a query actually runs), so this exercises the real
  // matching code, not a reimplementation of it. Construction happens
  // inside setUpAll (i.e. inside an active test zone) because
  // SupabaseClient's constructor builds an http.Client, and flutter_test's
  // _MockHttpOverrides requires that to happen inside a test zone rather
  // than in the bare body of main().
  late VoiceOrderRepository repo;
  setUpAll(() {
    // VoiceOrderRepository's constructor eagerly builds a real
    // AudioRecorder, whose constructor fires an async 'create' call over
    // this platform channel — there's no native implementation in the
    // test environment, so without a mock handler that call throws a
    // MissingPluginException as an unhandled/leaked async error. None of
    // the tests below actually record anything, so a no-op response is
    // enough to let construction settle quietly.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    repo = VoiceOrderRepository(
      speechService: SpeechService.instance,
      parserService: VoiceOrderParserService(client),
      restaurantService: RestaurantService(client),
      menuService: MenuService(client),
    );
  });

  group('VoiceOrderRepository.findMatchingCartItem', () {
    test('exact single substring match resolves unambiguously', () {
      final cart = [
        CartItem(menuItem: _item('1', 'Classic Smash Burger')),
        CartItem(menuItem: _item('2', 'Ting')),
      ];
      final match = repo.findMatchingCartItem(cart, 'the ting');
      expect(match?.menuItem.id, '2');
    });

    test('word-overlap fallback matches on shared significant words', () {
      final cart = [
        CartItem(menuItem: _item('1', 'Classic Smash Burger')),
      ];
      final match = repo.findMatchingCartItem(cart, 'burger');
      expect(match?.menuItem.id, '1');
    });

    test('no match returns null rather than guessing', () {
      final cart = [
        CartItem(menuItem: _item('1', 'Classic Smash Burger')),
      ];
      final match = repo.findMatchingCartItem(cart, 'pizza');
      expect(match, isNull);
    });

    test('empty cart returns null', () {
      final match = repo.findMatchingCartItem(const [], 'anything');
      expect(match, isNull);
    });

    test('when both real cart lines share a word, the substring match wins over a tie', () {
      final cart = [
        CartItem(menuItem: _item('1', 'Chicken Burger')),
        CartItem(menuItem: _item('2', 'Beef Burger')),
      ];
      // "chicken burger" is an exact-ish substring match for item 1 only.
      final match = repo.findMatchingCartItem(cart, 'chicken burger');
      expect(match?.menuItem.id, '1');
    });
  });
}
