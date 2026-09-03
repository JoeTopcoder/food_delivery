import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../models/menu_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/food/menu_service.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../data/concierge_service.dart';

final conciergeServiceProvider = Provider<ConciergeService>(
  (ref) => ConciergeService(Supabase.instance.client),
);

class _Turn {
  _Turn.user(this.text) : isUser = true, reply = null;
  _Turn.assistant(this.reply) : isUser = false, text = reply!.message;

  final bool isUser;
  final String text;
  final ConciergeReply? reply;
}

/// Conversational entry point to the Food Concierge.
///
/// The screen deliberately renders money from [ConciergeReply.pricing] — the
/// server's own figures — rather than from the assistant's prose, so what the
/// customer is asked to pay can never drift from what the database computed.
class ConciergeScreen extends ConsumerStatefulWidget {
  const ConciergeScreen({super.key});

  @override
  ConsumerState<ConciergeScreen> createState() => _ConciergeScreenState();
}

class _ConciergeScreenState extends ConsumerState<ConciergeScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  bool _busy = false;

  static const _examples = [
    'Dinner for two, something spicy, no pork, under \$40',
    'I want jerk chicken delivered before 7',
    'Something vegetarian and light, nothing too expensive',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _turns.add(_Turn.user(text));
      _busy = true;
      _controller.clear();
    });
    _scrollToEnd();

    try {
      // Only the plain text of prior turns is replayed. The draft ids and
      // totals stay server-side, so nothing the model previously said about
      // money can be re-fed to it as if it were fact.
      final history = <Map<String, String>>[
        for (final t in _turns.take(_turns.length - 1))
          {'role': t.isUser ? 'user' : 'assistant', 'content': t.text},
      ];

      final reply = await ref
          .read(conciergeServiceProvider)
          .ask(message: text, history: history);

      if (!mounted) return;
      setState(() => _turns.add(_Turn.assistant(reply)));
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _turns.add(
          _Turn.assistant(ConciergeReply(message: friendlyError(e))),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  /// Moves a concierge draft into the REAL cart, then opens it.
  ///
  /// This step is the whole point of the feature and was missing: the concierge
  /// built and priced a server-side draft, then navigated to /cart — which
  /// still held whatever was there before. The customer was shown one order and
  /// handed a different one.
  ///
  /// Everything goes through the existing CartNotifier rather than any parallel
  /// path, so merging, restaurant rules and persistence behave exactly as they
  /// do for a manual add.
  Future<void> _applyDraftAndOpenCart(String draftId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final service = ref.read(conciergeServiceProvider);
      final lines = await service.draftLineItems(draftId);
      if (lines.isEmpty) throw Exception('That order is no longer available');

      final menuService = MenuService(Supabase.instance.client);
      final cart = ref.read(cartProvider.notifier);

      // Re-read each item from the menu rather than trusting the draft's
      // snapshot, so the cart carries real current prices and options.
      final resolved = <MenuItem, int>{};
      for (final line in lines) {
        final id = line['item_id']?.toString();
        if (id == null) continue;
        final item = await menuService.getMenuItemById(id);
        if (item == null) continue;
        final qty = (line['qty'] as num?)?.toInt() ?? 1;
        resolved[item] = qty;
      }
      if (resolved.isEmpty) {
        throw Exception('Those items are no longer on the menu');
      }

      // The concierge picks a single restaurant, so a non-empty cart from
      // somewhere else is a genuine conflict. Ask rather than silently
      // discarding something the customer chose themselves.
      final first = resolved.keys.first;
      if (cart.isDifferentRestaurant(first) && mounted) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Start a new order?'),
            content: const Text(
              'Your cart has items from another restaurant. Adding this order '
              'will clear them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep my cart'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace != true) return;
        cart.clearCart();
      }

      resolved.forEach((item, qty) {
        for (var i = 0; i < qty; i++) {
          cart.addItem(item);
        }
      });

      if (!mounted) return;
      Navigator.of(context).pushNamed('/cart');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Food Concierge'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: _turns.isEmpty
                ? _buildEmptyState(scheme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _turns.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _turns.length) return const _ThinkingBubble();
                      final t = _turns[i];
                      final draftId = t.reply?.cartDraftId;
                      return _TurnBubble(
                        turn: t,
                        // Applies the draft to the real cart first — navigating
                        // straight to /cart was what showed the customer one
                        // order and delivered whatever was already in there.
                        onCheckout: draftId == null
                            ? null
                            : () => _applyDraftAndOpenCart(draftId),
                      );
                    },
                  ),
          ),
          _buildComposer(scheme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(
          Icons.restaurant_menu_rounded,
          size: 56,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          'Tell me what you feel like',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "I'll find it, check it's available, build your cart and apply any "
          'discount you qualify for. You confirm and pay as normal.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        for (final ex in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: _busy ? null : () => _send(ex),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                alignment: Alignment.centerLeft,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                ex,
                style: TextStyle(color: scheme.onSurface, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildComposer(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        // Both insets: the keyboard AND the system nav bar. Missing the latter
        // puts the send button underneath the nav bar, where taps go to the
        // system rather than the app.
        10 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_busy,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'What are you in the mood for?',
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 23,
            backgroundColor: _busy
                ? scheme.outlineVariant
                : AppTheme.primaryColor,
            child: IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: _busy ? null : () => _send(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            // Honest about what's happening — this genuinely runs several
            // database round trips, so it can take a few seconds.
            Text(
              'Searching menus…',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnBubble extends StatelessWidget {
  const _TurnBubble({required this.turn, required this.onCheckout});

  final _Turn turn;

  /// Null when this turn produced no cart draft — there is nothing to check
  /// out, so the button must not appear at all.
  final VoidCallback? onCheckout;

  String _money(int cents) =>
      '${AppConstants.currencySymbol}${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (turn.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            turn.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    final pricing = turn.reply?.pricing;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 32),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (turn.text.trim().isNotEmpty)
              Text(
                turn.text,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),

            // Totals are rendered from the server's figures, never parsed out
            // of the assistant's sentence.
            if (pricing != null && onCheckout != null) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 10),
              _row(context, 'Subtotal', _money(pricing.subtotalCents)),
              if (pricing.discountCents > 0)
                _row(
                  context,
                  'Discount',
                  '−${_money(pricing.discountCents)}',
                  highlight: Colors.green.shade600,
                ),
              _row(context, 'Delivery', _money(pricing.deliveryCents)),
              if (pricing.feesCents > 0)
                _row(context, 'Service fee', _money(pricing.feesCents)),
              const SizedBox(height: 4),
              _row(context, 'Total', _money(pricing.totalCents), bold: true),

              if (pricing.repricedItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Prices changed for: ${pricing.repricedItems.join(', ')}. '
                  'The total above is current.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ],
              if (!pricing.meetsMinimum) ...[
                const SizedBox(height: 8),
                Text(
                  "This is below the restaurant's minimum order.",
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onCheckout,
                  child: const Text(
                    'Review & checkout',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Nothing is charged until you confirm.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
    Color? highlight,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14.5 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color:
                  highlight ??
                  (bold ? scheme.onSurface : scheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: highlight ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
