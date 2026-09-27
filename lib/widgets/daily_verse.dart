import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

/// A daily Bible verse, chosen server-side per user per day (varied across
/// users, stable for one user for the day) via the get_daily_verse RPC.
class DailyVerse {
  final String reference;
  final String text;
  const DailyVerse(this.reference, this.text);
}

/// Today's verse for the signed-in user. Null when disabled / none available.
final dailyVerseProvider =
    FutureProvider.autoDispose<DailyVerse?>((ref) async {
  try {
    final res = await SupabaseConfig.client.rpc('get_daily_verse');
    if (res is List && res.isNotEmpty) {
      final row = res.first as Map;
      final r = row['reference'] as String?;
      final t = row['text'] as String?;
      if (r != null && t != null) return DailyVerse(r, t);
    }
    return null;
  } catch (e) {
    AppLogger.error('get_daily_verse failed: $e');
    return null;
  }
});

/// Feature flag + timing knobs from app_config.
final dailyVerseConfigProvider =
    FutureProvider.autoDispose<({bool enabled, int delaySeconds})>((ref) async {
  try {
    final rows = await SupabaseConfig.client
        .from('app_config')
        .select('key, value')
        .inFilter('key', ['daily_verse_enabled', 'daily_verse_delay_seconds']);
    var enabled = true;
    var delay = 150;
    for (final row in (rows as List)) {
      final k = row['key'] as String?;
      final v = (row['value'] as String?)?.trim();
      if (k == 'daily_verse_enabled') enabled = v == 'true' || v == '1';
      if (k == 'daily_verse_delay_seconds') delay = int.tryParse(v ?? '') ?? 150;
    }
    return (enabled: enabled, delaySeconds: delay);
  } catch (_) {
    return (enabled: true, delaySeconds: 150);
  }
});

const _kVerseShownDateKey = 'daily_verse_shown_date';

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

/// Whether the verse has already been shown to this device today.
Future<bool> verseAlreadyShownToday() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVerseShownDateKey) == _todayKey();
  } catch (_) {
    return false; // fail open — showing once is harmless
  }
}

Future<void> _markVerseShownToday() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVerseShownDateKey, _todayKey());
  } catch (_) {}
}

/// Shows the verse-of-the-day sheet (once per day is enforced by the caller).
Future<void> showDailyVerseSheet(
    BuildContext context, DailyVerse verse) async {
  await _markVerseShownToday();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return Padding(
        // Clear the keyboard AND the system nav bar (see CLAUDE.md gotcha).
        padding: EdgeInsets.only(
          bottom: media.viewInsets.bottom + media.padding.bottom + 12,
          left: 12,
          right: 12,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A8A), Color(0xFF3B0764)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('📖', style: TextStyle(fontSize: 34)),
                  const SizedBox(height: 8),
                  Text(
                    'Verse of the Day',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '"${verse.text}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '— ${verse.reference}',
                    style: TextStyle(
                      color: Colors.amber.shade200,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E3A8A),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Amen 🙏',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A drop-in mixin-free helper: schedules the verse to appear after the
/// configured delay, once per day, for a screen that holds a [WidgetRef].
/// Call [DailyVerseScheduler.start] from initState and [cancel] from dispose.
class DailyVerseScheduler {
  DailyVerseScheduler(this._ref);
  final WidgetRef _ref;
  bool _cancelled = false;

  Future<void> start(
    BuildContext Function() contextOf, {
    bool Function()? canShow,
  }) async {
    if (await verseAlreadyShownToday()) return;
    final cfg = await _ref.read(dailyVerseConfigProvider.future);
    if (!cfg.enabled || _cancelled) return;
    await Future<void>.delayed(Duration(seconds: cfg.delaySeconds));
    if (_cancelled) return;
    if (await verseAlreadyShownToday()) return;
    if (canShow != null && !canShow()) return; // e.g. not on the home tab
    final verse = await _ref.read(dailyVerseProvider.future);
    if (verse == null || _cancelled) return;
    // Present AFTER the current frame so showing the sheet can never trigger a
    // re-entrant layout of the host screen while it is mid-build/layout, and
    // wrap it so a verse failure can never blank the screen behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_cancelled) return;
      final ctx = contextOf();
      if (!ctx.mounted) return;
      try {
        await showDailyVerseSheet(ctx, verse);
      } catch (e, st) {
        AppLogger.error('showDailyVerseSheet failed (suppressed): $e\n$st');
      }
    });
  }

  void cancel() => _cancelled = true;
}
