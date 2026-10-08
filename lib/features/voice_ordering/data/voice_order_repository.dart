import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../models/catalog/menu_model.dart';
import '../../../models/catalog/restaurant_model.dart';
import '../../../providers/auth_user/user_provider.dart' show CartItem;
import '../../../services/ai/speech_service.dart';
import '../../../services/food/menu_service.dart';
import '../../../services/food/restaurant_service.dart';
import '../domain/models/parsed_voice_order.dart';
import '../domain/models/resolved_voice_order.dart';
import 'voice_order_parser_service.dart';

/// Outcome of one add-to-cart resolution attempt. Exactly one of
/// [resolved]/[clarificationQuestion]/[errorMessage] is set.
class VoiceAddResult {
  const VoiceAddResult.success(this.resolved)
      : clarificationQuestion = null,
        errorMessage = null;
  const VoiceAddResult.needsClarification(this.clarificationQuestion)
      : resolved = null,
        errorMessage = null;
  const VoiceAddResult.error(this.errorMessage)
      : resolved = null,
        clarificationQuestion = null;

  final ResolvedVoiceOrder? resolved;
  final String? clarificationQuestion;
  final String? errorMessage;
}

/// Orchestrates capture → parse → resolve for one voice-order attempt.
/// Wraps the app's EXISTING [SpeechService] (shared singleton — also used
/// by the AI chat feature, so capture here is started/stopped cleanly and
/// never left running), [RestaurantService], and [MenuService]. Nothing in
/// this class touches the cart — resolution only ever produces a
/// [ResolvedVoiceOrder] for the confirm screen to review, or (for
/// [findMatchingCartItem]) an id for the controller to hand to the
/// existing `CartNotifier`.
class VoiceOrderRepository {
  VoiceOrderRepository({
    required this.speechService,
    required this.parserService,
    required this.restaurantService,
    required this.menuService,
  });

  final SpeechService speechService;
  final VoiceOrderParserService parserService;
  final RestaurantService restaurantService;
  final MenuService menuService;
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  String? _onDeviceText;

  // Safety net only — the customer's own press-and-hold defines the
  // recording window (see [startCapture]/[stopCaptureAndTranscribe]), so
  // this just prevents a runaway recording if a release is somehow missed.
  static const _maxHoldDuration = Duration(seconds: 30);
  Timer? _maxHoldTimer;

  // ── Capture ────────────────────────────────────────────────────────────

  /// Begins capturing — call the moment the customer presses the mic
  /// button down. [onPartial] fires with interim text for a live
  /// "Listening..." transcript (on-device, best-effort — never the final
  /// answer). Pairs with [stopCaptureAndTranscribe], called on release:
  /// press-and-hold defines the recording window directly — far more
  /// reliable than any auto-detected cutoff. Auto silence-detection and the
  /// on-device engine's own stop signal both proved too quick to give up in
  /// practice on this app's own test hardware (clips cut short before the
  /// customer finished talking, too short for Whisper to transcribe — it
  /// returned the classic near-silence hallucination "You" every time).
  Future<void> startCapture({void Function(String text)? onPartial}) async {
    if (!speechService.speechAvailable) await speechService.init();

    _recordingPath = null;
    _onDeviceText = null;
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordingPath =
            '${dir.path}/voice_order_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordingPath!,
        );
      }
    } catch (_) {
      _recordingPath = null; // recording unavailable — on-device only
    }

    speechService.onSpeechResult = (text, isFinal) {
      onPartial?.call(text);
      if (isFinal && text.trim().isNotEmpty) _onDeviceText = text.trim();
    };
    // Deliberately not used to end capture — the button release does that.
    speechService.onListeningStopped = () {};
    speechService.onError = (_) {};
    // Deliberately NOT awaited: on-device STT is best-effort caption-only —
    // Whisper transcription of the actual recording (already started above)
    // is the authoritative transcript. On at least this app's own test
    // hardware, the on-device engine's `listen()` call can hang indefinitely
    // (broken offline language pack) rather than erroring quickly, and
    // awaiting it here would block _captureReady from ever completing —
    // stalling the whole capture on an engine whose result we don't even
    // trust. Let it run in the background purely for live "Listening..."
    // captions; its own onError/onSpeechResult callbacks handle whatever it
    // does from here.
    unawaited(speechService.startListening());

    _maxHoldTimer?.cancel();
    _maxHoldTimer = Timer(_maxHoldDuration, () {
      unawaited(stopCapture());
    });
  }

  /// Ends capture — call the moment the customer releases the mic button.
  /// Returns the transcript (preferring server-side Whisper transcription
  /// of the recording; falling back to the on-device result only if
  /// recording/Whisper failed entirely), or null if nothing usable was
  /// captured at all.
  Future<String?> stopCaptureAndTranscribe() async {
    _maxHoldTimer?.cancel();
    // Force the native session down regardless of SpeechService's own
    // isListening bookkeeping — it listens with cancelOnError: false, so
    // the platform side can still be alive even after a status callback
    // already reported "done".
    await speechService.forceStopListening();

    String? recordedPath;
    if (_recordingPath != null) {
      try {
        recordedPath = await _recorder.stop();
      } catch (_) {}
    }

    if (recordedPath != null) {
      final whisperText = await parserService.transcribe(recordedPath);
      if (whisperText != null && whisperText.trim().isNotEmpty) {
        return whisperText.trim();
      }
    }
    return _onDeviceText;
  }

  /// Aborts an in-progress capture without transcribing it.
  Future<void> stopCapture() async {
    _maxHoldTimer?.cancel();
    await speechService.forceStopListening();
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  // ── Parse ──────────────────────────────────────────────────────────────

  Future<ParsedVoiceOrder?> parse({
    required String transcript,
    String? restaurantHint,
    List<String> cartItemNames = const [],
    List<Map<String, String>> history = const [],
  }) {
    return parserService.parse(
      transcript: transcript,
      restaurantHint: restaurantHint,
      cartItemNames: cartItemNames,
      history: history,
    );
  }

  // ── Add-to-cart resolution ────────────────────────────────────────────

  /// Resolves a [ParsedVoiceOrder] (intent == addToCart) against the REAL
  /// database. Single strong match → resolved silently. Several materially
  /// different real matches, or a required modifier with no
  /// restaurant-configured default → [VoiceAddResult.needsClarification]
  /// with a question naming the real options, never a guess.
  Future<VoiceAddResult> resolveAddToCart(
    ParsedVoiceOrder parsed, {
    String? cartRestaurantId,
  }) async {
    Restaurant? restaurant;

    if (parsed.restaurantQuery == null && cartRestaurantId != null) {
      restaurant = await restaurantService.getRestaurantById(cartRestaurantId);
    }

    List<Restaurant> restaurantCandidates = const [];
    if (restaurant == null && parsed.restaurantQuery != null) {
      restaurantCandidates = await restaurantService.searchRestaurants(
        parsed.restaurantQuery!,
      );
      if (restaurantCandidates.isNotEmpty) {
        final exact = restaurantCandidates.where(
          (r) => r.name.toLowerCase() == parsed.restaurantQuery!.toLowerCase(),
        );
        if (exact.isNotEmpty) {
          restaurant = exact.first;
        } else if (restaurantCandidates.length == 1) {
          restaurant = restaurantCandidates.first;
        }
        // else: multiple materially different real restaurants — ask below.
      }
    }

    if (restaurant == null) {
      if (restaurantCandidates.length > 1) {
        final names = restaurantCandidates.map((r) => r.name).join(', ');
        return VoiceAddResult.needsClarification(
          'I found a few restaurants matching that — $names. Which one did you mean?',
        );
      }
      return VoiceAddResult.error(
        parsed.restaurantQuery != null
            ? "I couldn't find a restaurant called \"${parsed.restaurantQuery}\"."
            : 'Which restaurant would you like to order from?',
      );
    }

    final menuItems = await menuService.getMenuByRestaurant(restaurant.id);
    final matched = <MatchedVoiceOrderItem>[];
    final unmatched = <UnmatchedVoiceOrderItem>[];

    for (final draft in parsed.items) {
      final term = draft.nameQuery.toLowerCase();
      var candidates = menuItems
          .where(
            (m) =>
                m.name.toLowerCase().contains(term) ||
                term.contains(m.name.toLowerCase()),
          )
          .toList();

      if (candidates.isEmpty) {
        final words = _significantWords(term);
        if (words.isNotEmpty) {
          final scored = menuItems
              .map((m) => MapEntry(m, _wordOverlapScore(words, m.name)))
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          if (scored.isNotEmpty) {
            final top = scored.first.value;
            candidates = scored.where((e) => e.value == top).map((e) => e.key).toList();
          }
        }
      }

      if (candidates.isEmpty) {
        unmatched.add(
          UnmatchedVoiceOrderItem(
            nameAsSaid: draft.nameQuery,
            reason: "Not found on ${restaurant.name}'s menu",
          ),
        );
        continue;
      }

      MenuItem match;
      final exactItem = candidates.where((m) => m.name.toLowerCase() == term);
      if (exactItem.isNotEmpty) {
        match = exactItem.first;
      } else if (candidates.length == 1) {
        match = candidates.first;
      } else {
        // Several materially different real items — ask, per spec: don't
        // guess between e.g. Beef/Chicken/Fish Burger.
        final names = candidates.take(5).map((m) => m.name).join(', ');
        return VoiceAddResult.needsClarification(
          '${restaurant.name} has a few options for "${draft.nameQuery}" — $names. Which one would you like?',
        );
      }

      final full = await menuService.getMenuItemWithOptions(match.id) ?? match;
      // Default selection for each REQUIRED group = its first available choice
      // (by sort order), derived from the loaded options.
      final defaultChoiceIds = <String>{};
      for (final g in full.optionGroups.where((g) => g.isRequired)) {
        final avail = g.choices.where((c) => c.isAvailable).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (avail.isNotEmpty) defaultChoiceIds.add(avail.first.id);
      }

      final modWords = _significantWords(draft.modifiers.join(' '));
      final matchedOptions = <String, List<OptionChoice>>{};
      for (final group in full.optionGroups) {
        OptionChoice? chosen;
        if (modWords.isNotEmpty) {
          final scored = group.choices
              .map((c) => MapEntry(c, _wordOverlapScore(modWords, c.name)))
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          if (scored.isNotEmpty) chosen = scored.first.key;
        }
        if (chosen == null && group.isRequired) {
          final defaultChoice = group.choices
              .where((c) => c.isAvailable && defaultChoiceIds.contains(c.id))
              .cast<OptionChoice?>()
              .firstWhere((_) => true, orElse: () => null);
          if (defaultChoice != null) {
            chosen = defaultChoice;
          } else {
            // Required, nothing mentioned, no configured default — ask,
            // naming the real choices. Never invents one.
            final choiceNames = group.choices.map((c) => c.name).join(', ');
            return VoiceAddResult.needsClarification(
              'What ${group.name.toLowerCase()} would you like for ${full.name} — $choiceNames?',
            );
          }
        }
        if (chosen != null) {
          matchedOptions[group.id] = [chosen];
        }
      }

      final matchedSides = <MenuItemSide>[];
      if (modWords.isNotEmpty) {
        for (final side in full.sides ?? const <MenuItemSide>[]) {
          if (_wordOverlapScore(modWords, side.name) > 0) matchedSides.add(side);
        }
      }

      final unmatchedModifierNote = _unmatchedModifiersNote(
        draft.modifiers,
        matchedSides,
        matchedOptions,
      );

      matched.add(
        MatchedVoiceOrderItem(
          menuItem: full,
          quantity: draft.quantity,
          matchedSides: matchedSides,
          matchedOptions: matchedOptions,
          notes: [
            if (draft.notes != null) draft.notes!,
            if (unmatchedModifierNote != null) unmatchedModifierNote,
          ].isEmpty
              ? null
              : [
                  if (draft.notes != null) draft.notes!,
                  if (unmatchedModifierNote != null) unmatchedModifierNote,
                ].join('; '),
        ),
      );
    }

    if (matched.isEmpty && unmatched.isNotEmpty) {
      final missed = unmatched.map((u) => u.nameAsSaid).join(', ');
      return VoiceAddResult.error(
        "I couldn't find $missed on ${restaurant.name}'s menu right now.",
      );
    }
    if (matched.isEmpty) {
      return VoiceAddResult.error("What would you like from ${restaurant.name}?");
    }

    return VoiceAddResult.success(
      ResolvedVoiceOrder(restaurant: restaurant, matchedItems: matched, unmatchedItems: unmatched),
    );
  }

  // ── Cart-item reference matching (for remove/update-quantity) ─────────

  /// Finds the real cart line the customer meant by name ("the Ting",
  /// "the burger") — matched against what's ACTUALLY in the cart right
  /// now, never invented. Returns null if nothing matches.
  CartItem? findMatchingCartItem(List<CartItem> cartItems, String reference) {
    if (cartItems.isEmpty) return null;
    final term = reference.toLowerCase();

    final substringMatches = cartItems.where(
      (c) =>
          c.menuItem.name.toLowerCase().contains(term) ||
          term.contains(c.menuItem.name.toLowerCase()),
    ).toList();
    if (substringMatches.length == 1) return substringMatches.first;
    if (substringMatches.length > 1) return substringMatches.first; // most recent-ish; simple v1 tie-break

    final words = _significantWords(term);
    if (words.isEmpty) return null;
    final scored = cartItems
        .map((c) => MapEntry(c, _wordOverlapScore(words, c.menuItem.name)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.isEmpty ? null : scored.first.key;
  }

  // ── Shared fuzzy-matching helpers ──────────────────────────────────────

  static const _stopwords = {
    'the', 'a', 'an', 'and', 'with', 'of', 'for', 'to', 'please', 'some',
  };

  static List<String> _significantWords(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 3 && !_stopwords.contains(w))
      .toList();

  static int _wordOverlapScore(List<String> spokenWords, String candidateName) {
    final nameWords = _significantWords(candidateName);
    return spokenWords
        .where((w) => nameWords.any((nw) => nw.contains(w) || w.contains(nw)))
        .length;
  }

  static String? _unmatchedModifiersNote(
    List<String> modifiers,
    List<MenuItemSide> matchedSides,
    Map<String, List<OptionChoice>> matchedOptions,
  ) {
    if (modifiers.isEmpty) return null;
    final matchedNames = {
      ...matchedSides.map((s) => s.name.toLowerCase()),
      ...matchedOptions.values.expand((c) => c).map((c) => c.name.toLowerCase()),
    };
    final leftover = modifiers.where((m) {
      final words = _significantWords(m);
      if (words.isEmpty) return false;
      return !matchedNames.any(
        (mn) => words.any((w) => mn.contains(w) || w.contains(mn)),
      );
    }).toList();
    return leftover.isEmpty ? null : leftover.join(', ');
  }
}
