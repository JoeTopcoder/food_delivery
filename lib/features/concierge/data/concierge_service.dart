import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_logger.dart';

/// Server-computed totals. Every figure here comes from the database via
/// `price_cart` — never from the model's prose — so the UI can render money
/// without parsing it out of a sentence.
class ConciergePricing {
  const ConciergePricing({
    required this.subtotalCents,
    required this.discountCents,
    required this.feesCents,
    required this.deliveryCents,
    required this.totalCents,
    required this.meetsMinimum,
    this.repricedItems = const [],
  });

  final int subtotalCents;
  final int discountCents;
  final int feesCents;
  final int deliveryCents;
  final int totalCents;
  final bool meetsMinimum;

  /// Items whose live price moved since the draft was assembled, or which went
  /// out of stock. Surfaced so a stale figure is never shown as current.
  final List<String> repricedItems;

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  factory ConciergePricing.fromJson(Map<String, dynamic> j) => ConciergePricing(
    subtotalCents: _int(j['subtotal_cents']),
    discountCents: _int(j['discount_cents']),
    feesCents: _int(j['fees_cents']),
    deliveryCents: _int(j['delivery_cents']),
    totalCents: _int(j['total_cents']),
    meetsMinimum: j['meets_minimum'] != false,
    repricedItems:
        (j['repriced_items'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}

class ConciergeReply {
  const ConciergeReply({
    required this.message,
    this.cartDraftId,
    this.pricing,
    this.checkoutUrl,
  });

  final String message;
  final String? cartDraftId;
  final ConciergePricing? pricing;

  /// Set once the concierge has finalized a cart and handed it off. This is the
  /// existing in-app route — the concierge never completes a purchase itself.
  final String? checkoutUrl;
}

/// Thin client over the `ai-concierge` edge function.
///
/// Deliberately holds no ordering logic of its own: restaurant search, dietary
/// filtering, pricing and promotion selection all happen server-side, where the
/// constraints can actually be enforced against the database.
class ConciergeService {
  ConciergeService(this._client);

  final SupabaseClient _client;

  Future<ConciergeReply> ask({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final res = await _client.functions.invoke(
        'ai-concierge',
        body: {'message': message, 'history': history},
      );

      final data = res.data;
      if (data is! Map) {
        throw Exception('Unexpected response from concierge');
      }
      if (data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      final pricingJson = data['pricing'];
      return ConciergeReply(
        message: (data['message'] ?? '').toString(),
        cartDraftId: data['cart_draft_id']?.toString(),
        pricing: pricingJson is Map
            ? ConciergePricing.fromJson(Map<String, dynamic>.from(pricingJson))
            : null,
        checkoutUrl: data['checkout_url']?.toString(),
      );
    } catch (e) {
      AppLogger.error('Concierge request failed: $e');
      rethrow;
    }
  }

  /// Line items of a draft, for the review screen. Read directly under RLS —
  /// the policy scopes drafts to their owner, so a customer can only ever load
  /// their own.
  Future<List<Map<String, dynamic>>> draftLineItems(String draftId) async {
    final row = await _client
        .from('concierge_cart_drafts')
        .select('line_items')
        .eq('id', draftId)
        .maybeSingle();
    final items = row?['line_items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Transcribes a recording server-side via Whisper.
  ///
  /// Returns null when nothing usable was captured — including Whisper's stock
  /// near-silence outputs ("You", "Thanks for watching!"), which the server
  /// filters, since replying to those produces a baffling answer to something
  /// the customer never said.
  ///
  /// The file is deleted as soon as it has been read, whatever the outcome: a
  /// recording of someone's voice has no reason to outlive its transcription.
  Future<String?> transcribe(String filePath) async {
    final file = File(filePath);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 2000) return null; // too short to contain speech

      final res = await _client.functions.invoke(
        'ai-concierge',
        body: {'mode': 'transcribe', 'audio_base64': base64Encode(bytes)},
      );
      final data = res.data;
      if (data is! Map || data['error'] != null) return null;
      final text = (data['text'] ?? '').toString().trim();
      return text.isEmpty ? null : text;
    } catch (e) {
      AppLogger.error('Transcription failed: $e');
      return null;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort — a leftover temp file is not worth failing the turn over.
      }
    }
  }

  /// The draft's restaurant, needed to detect a cart conflict before applying.
  Future<String?> draftRestaurantId(String draftId) async {
    final row = await _client
        .from('concierge_cart_drafts')
        .select('restaurant_id')
        .eq('id', draftId)
        .maybeSingle();
    return row?['restaurant_id'] as String?;
  }
}
