import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/saved_card_model.dart';
import '../../models/wallet_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'add_card_screen.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  final _amountCtrl = TextEditingController();
  final _presetAmounts = [500, 1000, 2000, 5000];
  bool _isDepositing = false;
  StreamSubscription? _cardsSub;

  @override
  void initState() {
    super.initState();
    _listenForCardChanges();
  }

  void _listenForCardChanges() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _cardsSub = Supabase.instance.client
        .from('saved_cards')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((_) {
          if (mounted) {
            ref.invalidate(savedCardsProvider(userId));
          }
        });
  }

  @override
  void dispose() {
    _cardsSub?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _addNewCard() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddCardScreen()));
    if (result == true && mounted) {
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(savedCardsProvider(userId));
      setState(() {});
    }
  }

  Future<void> _deleteCard(SavedCard card) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Card'),
        content: Text(
          'Remove ${card.displayBrand} ending in ${card.lastFour}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final svc = ref.read(paymentServiceProvider);
    await svc.deleteSavedCard(card.id);
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) ref.invalidate(savedCardsProvider(userId));
  }

  Future<void> _setDefaultCard(SavedCard card) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final svc = ref.read(paymentServiceProvider);
    await svc.setDefaultCard(userId, card.id);
    ref.invalidate(savedCardsProvider(userId));
  }

  /// Inline verify — called from the amount field inside _SavedCardTile.
  /// Returns true if the amount matched.
  Future<bool> _verifyCardInline(String cardId, double amount) async {
    final svc = ref.read(paymentServiceProvider);
    final userId = ref.read(currentUserIdProvider);

    final matched = await svc.verifyPendingCard(cardId, amount);
    if (userId != null) ref.invalidate(savedCardsProvider(userId));

    if (!mounted) return matched;

    if (matched) {
      AppSnackbar.success(
        context,
        'Card verified successfully! Charge will be reversed.',
      );
    } else {
      final updatedCards = userId != null
          ? await svc.getSavedCards(userId)
          : <SavedCard>[];
      final updatedCard = updatedCards.where((c) => c.id == cardId).firstOrNull;

      if (updatedCard != null && updatedCard.isFailed) {
        if (!mounted) return false;
        AppSnackbar.error(
          context,
          'Verification failed — too many wrong attempts. Please try adding the card again.',
        );
      } else {
        if (!mounted) return false;
        final attemptsLeft = 3 - (updatedCard?.verificationAttempts ?? 1);
        AppSnackbar.warning(
          context,
          'Amount didn\'t match. $attemptsLeft ${attemptsLeft == 1 ? "attempt" : "attempts"} remaining.',
        );
      }
    }
    return matched;
  }

  Widget _buildCardsSection(bool isDark) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const SizedBox.shrink();

    final cardsAsync = ref.watch(savedCardsProvider(userId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Cards',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: _addNewCard,
              icon: const Icon(Icons.add_card, size: 18),
              label: const Text('Add Card'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        cardsAsync.when(
          data: (cards) {
            if (cards.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF374151)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.credit_card_off_outlined,
                      size: 40,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No cards added yet',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addNewCard,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Your First Card'),
                    ),
                  ],
                ),
              );
            }

            final pendingCards = cards
                .where((c) => c.isPending && !c.isExpired)
                .toList();
            final expiredCards = cards
                .where((c) => c.isPending && c.isExpired)
                .toList();
            final failedCards = cards.where((c) => c.isFailed).toList();
            final verifiedCards = cards.where((c) => c.isVerified).toList();

            // Auto-expire any pending cards that are past their window
            if (expiredCards.isNotEmpty) {
              Future.microtask(() {
                for (final ec in expiredCards) {
                  ref.read(paymentServiceProvider).verifyPendingCard(ec.id, -1);
                }
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pending verification cards
                if (pendingCards.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Check your bank statement for the charge amount, '
                            'then tap Verify.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.orange.shade200
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...pendingCards.map(
                    (card) => _SavedCardTile(
                      key: ValueKey(
                        '${card.id}_${card.status}_${card.verificationAttempts}',
                      ),
                      card: card,
                      isDark: isDark,
                      onSetDefault: () {},
                      onDelete: () => _deleteCard(card),
                      onVerifyAmount: (cardId, amount) =>
                          _verifyCardInline(cardId, amount),
                    ),
                  ),
                ],
                // Failed cards
                ...failedCards.map(
                  (card) => _SavedCardTile(
                    key: ValueKey('${card.id}_${card.status}'),
                    card: card,
                    isDark: isDark,
                    onSetDefault: () {},
                    onDelete: () => _deleteCard(card),
                  ),
                ),
                // Verified cards
                ...verifiedCards.map(
                  (card) => _SavedCardTile(
                    key: ValueKey('${card.id}_${card.status}'),
                    card: card,
                    isDark: isDark,
                    onSetDefault: () => _setDefaultCard(card),
                    onDelete: () => _deleteCard(card),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(
            friendlyError(e),
            style: TextStyle(
              color: isDark ? Colors.red.shade300 : AppTheme.errorColor,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _deposit(double amount) async {
    if (amount <= 0) return;
    setState(() => _isDepositing = true);
    try {
      // 1. Create a Stripe PaymentIntent for the wallet top-up
      final paymentService = ref.read(paymentServiceProvider);
      final authUser = Supabase.instance.client.auth.currentUser;
      final email = authUser?.email ?? '';
      final name = authUser?.userMetadata?['name'] as String? ?? 'Customer';

      // Use a unique wallet-topup ID
      final topupId = 'wallet-${DateTime.now().millisecondsSinceEpoch}';

      final session = await paymentService.createStripeCheckout(
        orderId: topupId,
        amount: amount,
        customerEmail: email,
        customerName: name,
        type: 'wallet_topup',
      );

      if (!mounted) return;

      // 2. Present Stripe Payment Sheet
      final paymentCompleted = await paymentService.presentStripePaymentSheet(
        session: session,
        customerEmail: email,
        customerName: name,
      );

      if (!mounted) return;

      if (!paymentCompleted) {
        AppSnackbar.warning(context, 'Wallet top-up cancelled');
        return;
      }

      // Confirm payment server-side
      await paymentService.confirmStripePayment(
        paymentIntentId: session.paymentIntentId,
        orderId: topupId,
        type: 'wallet_topup',
      );

      // 3. Card payment succeeded — credit the wallet
      await ref.read(walletNotifierProvider.notifier).deposit(amount);
      ref.invalidate(walletTransactionsProvider);
      if (mounted) {
        AppSnackbar.success(
          context,
          '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} added to wallet',
        );
        _amountCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isDepositing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletNotifierProvider);
    final txAsync = ref.watch(walletTransactionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Wallet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(walletNotifierProvider.notifier).refresh();
          ref.invalidate(walletTransactionsProvider);
        },
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          children: [
            // ── Balance Card ──────────────────────────────────
            walletAsync.when(
              data: (wallet) => _BalanceCard(wallet: wallet),
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                friendlyError(e),
                style: TextStyle(
                  color: isDark ? Colors.red.shade300 : AppTheme.errorColor,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Add Funds ─────────────────────────────────────
            Text(
              'Add Funds',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetAmounts
                  .map(
                    (a) => ActionChip(
                      label: Text(
                        '\$$a',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF374151)
                          : Colors.grey.shade100,
                      onPressed: () => _deposit(a.toDouble()),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: 'Custom amount',
                      hintStyle: TextStyle(
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isDepositing
                      ? null
                      : () {
                          final amt = double.tryParse(_amountCtrl.text) ?? 0;
                          _deposit(amt);
                        },
                  child: _isDepositing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Add'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── My Cards ──────────────────────────────────────
            _buildCardsSection(isDark),

            const SizedBox(height: 24),

            // ── Transaction History ───────────────────────────
            Text(
              'Transaction History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            txAsync.when(
              data: (txns) {
                if (txns.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No transactions yet',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: txns.map((tx) => _TransactionTile(tx: tx)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                friendlyError(e),
                style: TextStyle(
                  color: isDark ? Colors.red.shade300 : AppTheme.errorColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final Wallet? wallet;
  const _BalanceCard({this.wallet});

  @override
  Widget build(BuildContext context) {
    final balance = wallet?.balance ?? 0;
    final cashback = wallet?.cashbackBalance ?? 0;
    final total = balance + cashback;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Available Balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BalanceChip(label: 'Main', amount: balance),
              const SizedBox(width: 12),
              _BalanceChip(label: 'Cashback', amount: cashback),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final double amount;
  const _BalanceChip({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: \$${amount.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (IconData icon, Color color) = switch (tx.type) {
      'deposit' => (Icons.add_circle_outline, AppTheme.successColor),
      'payment' => (Icons.shopping_cart_outlined, AppTheme.primaryColor),
      'cashback' => (Icons.card_giftcard, const Color(0xFFF59E0B)),
      'refund' => (Icons.replay, const Color(0xFF3B82F6)),
      'penalty' => (Icons.warning_amber_rounded, AppTheme.errorColor),
      'tip_received' => (Icons.favorite, AppTheme.successColor),
      _ => (Icons.receipt, Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade200,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? tx.type.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat.yMMMd().add_jm().format(tx.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${tx.isCredit ? '+' : ''}\$${tx.amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: tx.isCredit ? AppTheme.successColor : AppTheme.errorColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedCardTile extends StatefulWidget {
  final SavedCard card;
  final bool isDark;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final Future<bool> Function(String cardId, double amount)? onVerifyAmount;

  const _SavedCardTile({
    super.key,
    required this.card,
    required this.isDark,
    required this.onSetDefault,
    required this.onDelete,
    this.onVerifyAmount,
  });

  @override
  State<_SavedCardTile> createState() => _SavedCardTileState();
}

class _SavedCardTileState extends State<_SavedCardTile> {
  final _amountCtrl = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  SavedCard get card => widget.card;
  bool get isDark => widget.isDark;

  IconData _brandIcon() {
    switch (card.cardBrand.toLowerCase()) {
      case 'visa':
        return Icons.credit_card;
      case 'mastercard':
        return Icons.credit_card;
      case 'keycard':
        return Icons.credit_card;
      default:
        return Icons.credit_card;
    }
  }

  Color _brandColor() {
    switch (card.cardBrand.toLowerCase()) {
      case 'visa':
        return const Color(0xFF1A1F71);
      case 'mastercard':
        return const Color(0xFFEB001B);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = card.isPending;
    final isFailed = card.isFailed;
    final dimmed = isFailed;

    return Opacity(
      opacity: dimmed ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPending
                ? Colors.orange.withValues(alpha: 0.6)
                : isFailed
                ? Colors.red.withValues(alpha: 0.4)
                : card.isDefault
                ? AppTheme.primaryColor.withValues(alpha: 0.5)
                : isDark
                ? const Color(0xFF374151)
                : Colors.grey.shade200,
            width: (isPending || card.isDefault) ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brandColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_brandIcon(), color: _brandColor(), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${card.displayBrand}  •••• ${card.lastFour}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (card.isDefault && card.isVerified)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'DEFAULT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          if (isPending)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'PENDING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          if (isFailed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'FAILED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (card.cardholderName.isNotEmpty)
                        Text(
                          card.cardholderName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : AppTheme.textLight,
                          ),
                        ),
                      if (isPending) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'CVC: ***',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (card.timeRemaining != null)
                              Text(
                                '${card.timeRemaining!.inMinutes} min left',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: card.status == 'verified'
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : card.status == 'failed'
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Status: ${card.status.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: card.status == 'verified'
                                      ? Colors.green.shade700
                                      : card.status == 'failed'
                                      ? Colors.red.shade700
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: card.verificationAttempts >= 3
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Attempts: ${card.verificationAttempts}/3',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: card.verificationAttempts >= 3
                                      ? Colors.red.shade700
                                      : Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (isPending && widget.onVerifyAmount != null)
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    tooltip: 'Remove card',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else if (!isPending)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'default') widget.onSetDefault();
                      if (value == 'delete') widget.onDelete();
                    },
                    itemBuilder: (_) => [
                      if (!card.isDefault && card.isVerified)
                        const PopupMenuItem(
                          value: 'default',
                          child: Row(
                            children: [
                              Icon(Icons.star_outline, size: 18),
                              SizedBox(width: 8),
                              Text('Set as default'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text('Remove', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // Inline verification amount field for pending cards
            if (isPending && widget.onVerifyAmount != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.08)
                      : Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter the exact amount charged to verify:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                prefixText: '\$ ',
                                hintText: 'e.g. 3.00',
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1F2937)
                                    : Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                              ),
                              enabled: !_isVerifying,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isVerifying
                                ? null
                                : () async {
                                    final amount = double.tryParse(
                                      _amountCtrl.text.trim(),
                                    );
                                    if (amount == null || amount <= 0) {
                                      AppSnackbar.warning(
                                        context,
                                        'Please enter a valid amount.',
                                      );
                                      return;
                                    }
                                    setState(() => _isVerifying = true);
                                    final matched = await widget
                                        .onVerifyAmount!(card.id, amount);
                                    if (mounted) {
                                      setState(() => _isVerifying = false);
                                      if (matched) {
                                        _amountCtrl.clear();
                                      }
                                    }
                                  },
                            icon: _isVerifying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle, size: 18),
                            label: const Text(
                              'Verify',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
