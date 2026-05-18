import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
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
          if (mounted) ref.invalidate(savedCardsProvider(userId));
        });
  }

  @override
  void dispose() {
    _cardsSub?.cancel();
    super.dispose();
  }

  String _walletDisplayId() {
    final user = ref.read(currentUserProvider);
    final refCode = user?.referralCode;
    if (refCode != null && refCode.isNotEmpty) return refCode.toUpperCase();
    final uid = ref.read(currentUserIdProvider) ?? '';
    return uid.replaceAll('-', '').substring(0, 6).toUpperCase();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _topUp() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final cardsAsync = ref.read(savedCardsProvider(userId));
    final verifiedCards = cardsAsync.valueOrNull
            ?.where((c) => c.isVerified && c.stripePaymentMethodId != null)
            .toList() ??
        [];

    if (!mounted) return;

    final result = await Navigator.of(context).push<_TopUpResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TopUpPage(
          walletDisplayId: _walletDisplayId(),
          verifiedCards: verifiedCards,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _isDepositing = true);
    try {
      if (result.savedCard != null) {
        final cvv = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              _CvvSheet(card: result.savedCard!, amount: result.amount),
        );
        if (cvv == null || !mounted) return;
        await _depositWithSavedCard(result.amount, result.savedCard!, cvv);
      } else {
        await _depositWithNewCard(result.amount);
      }
    } finally {
      if (mounted) setState(() => _isDepositing = false);
    }
  }

  Future<void> _sendMoney() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final wallet = ref.read(walletNotifierProvider).valueOrNull;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SendMoneySheet(
        senderUserId: userId,
        currentBalance: wallet?.balance ?? 0,
        ref: ref,
        onSuccess: () {
          ref.read(walletNotifierProvider.notifier).refresh();
          ref.invalidate(walletTransactionsProvider);
        },
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TransactionHistorySheet(ref: ref),
    );
  }

  // ── Add / Manage cards ────────────────────────────────────────────────────

  Future<void> _addNewCard() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddCardScreen()),
    );
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
            'Remove ${card.displayBrand} ending in ${card.lastFour}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Remove', style: TextStyle(color: Colors.red))),
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

  Future<bool> _verifyCardInline(String cardId, double amount) async {
    final svc = ref.read(paymentServiceProvider);
    final userId = ref.read(currentUserIdProvider);
    final matched = await svc.verifyPendingCard(cardId, amount);
    if (userId != null) ref.invalidate(savedCardsProvider(userId));
    if (!mounted) return matched;
    if (matched) {
      AppSnackbar.success(
          context, 'Card verified successfully! Charge will be reversed.');
    } else {
      final updatedCards =
          userId != null ? await svc.getSavedCards(userId) : <SavedCard>[];
      final updatedCard =
          updatedCards.where((c) => c.id == cardId).firstOrNull;
      if (updatedCard != null && updatedCard.isFailed) {
        if (!mounted) return false;
        AppSnackbar.error(context,
            'Verification failed — too many wrong attempts. Please try adding the card again.');
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

  Future<void> _depositWithSavedCard(
      double amount, SavedCard card, String cvv) async {
    final paymentService = ref.read(paymentServiceProvider);
    final topupId = 'wallet-${DateTime.now().millisecondsSinceEpoch}';
    final session = await paymentService.prepareSavedCardPayment(
      orderId: topupId,
      amount: amount,
      paymentMethodId: card.stripePaymentMethodId!,
      type: 'wallet_topup',
    );
    if (!mounted) return;
    if (Stripe.publishableKey.isEmpty) {
      final key = AppConstants.stripePublishableKey;
      if (key.isNotEmpty) {
        Stripe.publishableKey = key;
        Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
        await Stripe.instance.applySettings();
      }
    }
    try {
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: session.clientSecret,
        data: PaymentMethodParams.cardFromMethodId(
          paymentMethodData: PaymentMethodDataCardFromMethod(
            paymentMethodId: card.stripePaymentMethodId!,
            cvc: cvv,
          ),
        ),
      );
    } on StripeException catch (e) {
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        AppSnackbar.warning(context, 'Payment cancelled');
      } else {
        AppSnackbar.error(context,
            e.error.localizedMessage ?? 'Payment failed. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    await ref.read(walletNotifierProvider.notifier).deposit(amount);
    ref.invalidate(walletTransactionsProvider);
    if (mounted) {
      AppSnackbar.success(
        context,
        '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} added via ${card.displayBrand} ••••${card.lastFour}',
      );
    }
  }

  Future<void> _depositWithNewCard(double amount) async {
    final paymentService = ref.read(paymentServiceProvider);
    final authUser = Supabase.instance.client.auth.currentUser;
    final email = authUser?.email ?? '';
    final name =
        authUser?.userMetadata?['name'] as String? ?? 'Customer';
    final topupId = 'wallet-${DateTime.now().millisecondsSinceEpoch}';
    final result = await paymentService.presentStripePaymentSheet(
      orderId: topupId,
      amount: amount,
      customerEmail: email,
      customerName: name,
      type: 'wallet_topup',
    );
    if (!mounted) return;
    if (result == null) {
      AppSnackbar.warning(context, 'Top-up cancelled');
      return;
    }
    await ref.read(walletNotifierProvider.notifier).deposit(amount);
    ref.invalidate(walletTransactionsProvider);
    if (mounted) {
      AppSnackbar.success(
        context,
        '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} added to wallet',
      );
    }
  }

  // ── Saved cards section ───────────────────────────────────────────────────

  Widget _buildCardsSection(bool isDark) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const SizedBox.shrink();
    final cardsAsync = ref.watch(savedCardsProvider(userId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.credit_card_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 10),
            Text(
              'Saved Cards',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _addNewCard,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Card'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        cardsAsync.when(
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(friendlyError(e),
              style: TextStyle(color: AppTheme.errorColor)),
          data: (cards) {
            if (cards.isEmpty) {
              return _EmptyCardsPlaceholder(onAdd: _addNewCard, isDark: isDark);
            }

            final pendingCards =
                cards.where((c) => c.isPending && !c.isExpired).toList();
            final expiredCards =
                cards.where((c) => c.isPending && c.isExpired).toList();
            final failedCards = cards.where((c) => c.isFailed).toList();
            final verifiedCards = cards.where((c) => c.isVerified).toList();

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
                // Pending verification notice
                if (pendingCards.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Check your bank statement for the charge amount, then tap Verify.',
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
                ],

                // Card type label (only if there are verified/pending cards)
                if (verifiedCards.isNotEmpty || pendingCards.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Credit/Debit Card',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),

                ...pendingCards.map((card) => _SavedCardTile(
                      key: ValueKey(
                          '${card.id}_${card.status}_${card.verificationAttempts}'),
                      card: card,
                      isDark: isDark,
                      onSetDefault: () {},
                      onDelete: () => _deleteCard(card),
                      onVerifyAmount: (cardId, amount) =>
                          _verifyCardInline(cardId, amount),
                    )),
                ...failedCards.map((card) => _SavedCardTile(
                      key: ValueKey('${card.id}_${card.status}'),
                      card: card,
                      isDark: isDark,
                      onSetDefault: () {},
                      onDelete: () => _deleteCard(card),
                    )),
                ...verifiedCards.map((card) => _SavedCardTile(
                      key: ValueKey('${card.id}_${card.status}'),
                      card: card,
                      isDark: isDark,
                      onSetDefault: () => _setDefaultCard(card),
                      onDelete: () => _deleteCard(card),
                    )),

                const SizedBox(height: 12),

                // "Add New Card +" bottom button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addNewCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Add New Card +',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment & Wallet',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(walletNotifierProvider.notifier).refresh();
          ref.invalidate(walletTransactionsProvider);
        },
        child: ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Wallet card
            walletAsync.when(
              data: (wallet) => _WalletCard(
                wallet: wallet,
                walletDisplayId: _walletDisplayId(),
                isDepositing: _isDepositing,
                onTopUp: _topUp,
                onSendMoney: _sendMoney,
                onHistory: _showHistory,
              ),
              loading: () => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text(friendlyError(e),
                  style: TextStyle(color: AppTheme.errorColor)),
            ),

            const SizedBox(height: 28),

            // Saved cards
            _buildCardsSection(isDark),
          ],
        ),
      ),
    );
  }
}

// ─── Wallet card ──────────────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  final Wallet? wallet;
  final String walletDisplayId;
  final bool isDepositing;
  final VoidCallback onTopUp;
  final VoidCallback onSendMoney;
  final VoidCallback onHistory;

  const _WalletCard({
    required this.wallet,
    required this.walletDisplayId,
    required this.isDepositing,
    required this.onTopUp,
    required this.onSendMoney,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final balance = wallet?.balance ?? 0;
    final cashback = wallet?.cashbackBalance ?? 0;
    final total = balance + cashback;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, const Color(0xFFFF8C5A)],
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
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                '7Dash Wallet',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onHistory,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5B03C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('History',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'My Balance',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'JMD',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            'Wallet ID: $walletDisplayId',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _WalletActionButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: isDepositing ? 'Processing…' : 'Top-up',
                  onTap: isDepositing ? null : onTopUp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletActionButton(
                  icon: Icons.send_rounded,
                  label: 'Send Money',
                  onTap: onSendMoney,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _WalletActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFFF5B03C).withValues(alpha: 0.5)
              : const Color(0xFFF5B03C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty cards placeholder ──────────────────────────────────────────────────

class _EmptyCardsPlaceholder extends StatelessWidget {
  final VoidCallback onAdd;
  final bool isDark;
  const _EmptyCardsPlaceholder({required this.onAdd, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.credit_card_off_outlined,
              size: 40,
              color:
                  isDark ? Colors.grey.shade500 : Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('No cards added yet',
              style: TextStyle(
                color:
                    isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Your First Card'),
          ),
        ],
      ),
    );
  }
}

// ─── Card brand logo ──────────────────────────────────────────────────────────

class _CardBrandLogo extends StatelessWidget {
  final String brand;
  const _CardBrandLogo({required this.brand});

  @override
  Widget build(BuildContext context) {
    final lower = brand.toLowerCase();
    if (lower.contains('master')) {
      return SizedBox(
        width: 48,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 4,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 4,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (lower.contains('visa')) {
      return Container(
        width: 48,
        height: 36,
        alignment: Alignment.center,
        child: const Text(
          'VISA',
          style: TextStyle(
            color: Color(0xFF1A1F71),
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
      );
    }
    if (lower.contains('amex') || lower.contains('american')) {
      return Container(
        width: 48,
        height: 36,
        alignment: Alignment.center,
        child: const Text(
          'AMEX',
          style: TextStyle(
            color: Color(0xFF007BC1),
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return Container(
      width: 48,
      height: 36,
      alignment: Alignment.center,
      child: const Icon(Icons.credit_card, size: 26, color: Colors.grey),
    );
  }
}

// ─── Transaction tile ─────────────────────────────────────────────────────────

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
      'transfer_sent' => (Icons.send_rounded, AppTheme.primaryColor),
      'transfer_received' => (Icons.call_received_rounded, AppTheme.successColor),
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
                    color:
                        isDark ? Colors.grey.shade400 : AppTheme.textLight,
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
              color: tx.isCredit
                  ? AppTheme.successColor
                  : AppTheme.errorColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Saved card tile ──────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final isPending = card.isPending;
    final isFailed = card.isFailed;

    return Opacity(
      opacity: isFailed ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
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
                // Brand logo
                Container(
                  width: 56,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  alignment: Alignment.center,
                  child: _CardBrandLogo(brand: card.cardBrand),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cardholder name + badges
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              card.cardholderName.isNotEmpty
                                  ? card.cardholderName
                                  : card.displayBrand,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (card.isDefault && card.isVerified) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(
                                label: 'DEFAULT',
                                color: AppTheme.primaryColor),
                          ],
                          if (isPending) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(
                                label: 'PENDING', color: Colors.orange),
                          ],
                          if (isFailed) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(label: 'FAILED', color: Colors.red),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Masked number
                      Text(
                        'xxxx xxxx xxxx ${card.lastFour}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isPending && card.timeRemaining != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${card.timeRemaining!.inMinutes} min to verify',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange.shade700),
                        ),
                      ],
                    ],
                  ),
                ),

                // Menu or delete
                if (isPending && widget.onVerifyAmount != null)
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: Icon(Icons.delete_outline,
                        color: Colors.red.shade400, size: 20),
                    tooltip: 'Remove card',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else if (!isPending)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz_rounded,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        size: 22),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
                            Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Remove',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Pending card verification inline section
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
                      color: Colors.orange.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A small charge (between \$${AppConstants.cardVerificationChargeMin.toStringAsFixed(0)} and \$${AppConstants.cardVerificationChargeMax.toStringAsFixed(0)}) was sent. '
                      'Check your banking app, then enter the exact amount below:',
                      style: TextStyle(
                        fontSize: 12,
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
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]')),
                              ],
                              decoration: InputDecoration(
                                prefixText: '\$ ',
                                hintText: 'e.g. 3.00',
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1F2937)
                                    : Colors.white,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
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
                                        _amountCtrl.text.trim());
                                    if (amount == null || amount <= 0) {
                                      AppSnackbar.warning(context,
                                          'Please enter a valid amount.');
                                      return;
                                    }
                                    setState(
                                        () => _isVerifying = true);
                                    final matched =
                                        await widget.onVerifyAmount!(
                                            card.id, amount);
                                    if (mounted) {
                                      setState(
                                          () => _isVerifying = false);
                                      if (matched) _amountCtrl.clear();
                                    }
                                  },
                            icon: _isVerifying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle, size: 18),
                            label: const Text('Verify',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8)),
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

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─── CVV sheet (unchanged) ────────────────────────────────────────────────────

class _CvvSheet extends StatefulWidget {
  final SavedCard card;
  final double amount;
  const _CvvSheet({required this.card, required this.amount});

  @override
  State<_CvvSheet> createState() => _CvvSheetState();
}

class _CvvSheetState extends State<_CvvSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isAmex {
    final b = widget.card.cardBrand.toLowerCase();
    return b.contains('amex') || b.contains('american');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxLen = _isAmex ? 4 : 3;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 8,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Enter CVV',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            '${widget.card.displayBrand}  ••••  ${widget.card.lastFour}',
            style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: maxLen,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _isAmex ? '4-digit security code' : '3-digit CVV',
              hintText: _isAmex ? '••••' : '•••',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              counterText: '',
            ),
            onSubmitted: (val) {
              if (val.length == maxLen) Navigator.of(context).pop(val);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, val, __) => ElevatedButton(
                onPressed: val.text.length == maxLen
                    ? () => Navigator.of(context).pop(_ctrl.text)
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Pay  ${AppConstants.currencySymbol}${widget.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top-up page (new route) ──────────────────────────────────────────────────

class _TopUpResult {
  final double amount;
  final SavedCard? savedCard;
  const _TopUpResult({required this.amount, this.savedCard});
}

class _TopUpPage extends StatefulWidget {
  final String walletDisplayId;
  final List<SavedCard> verifiedCards;
  const _TopUpPage(
      {required this.walletDisplayId, required this.verifiedCards});

  @override
  State<_TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<_TopUpPage> {
  final _amountCtrl = TextEditingController();
  SavedCard? _selectedCard;

  @override
  void initState() {
    super.initState();
    if (widget.verifiedCards.isNotEmpty) {
      _selectedCard = widget.verifiedCards.firstWhere(
        (c) => c.isDefault,
        orElse: () => widget.verifiedCards.first,
      );
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top-up',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Wallet ID
          Text('Your 7Dash Wallet ID',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1F2937)
                  : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(widget.walletDisplayId,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),

          const SizedBox(height: 24),

          // Amount
          Text('Amount',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1F2937)
                  : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Card selector
          if (widget.verifiedCards.isNotEmpty) ...[
            Text('Select Credit / Debit Card',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.verifiedCards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final card = widget.verifiedCards[i];
                  final selected = _selectedCard?.id == card.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCard = card),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primaryColor.withValues(alpha: 0.08)
                            : isDark
                                ? const Color(0xFF1F2937)
                                : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primaryColor
                              : isDark
                                  ? const Color(0xFF374151)
                                  : Colors.grey.shade200,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          _CardBrandLogo(brand: card.cardBrand),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(card.displayBrand,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
                                Text('••••${card.lastFour}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          if (selected)
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  color: Colors.white, size: 14),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            '*This money can only be spent on 7Dash.\n'
            '*You can send 7Dash wallet money to other 7Dash wallets.',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryColor,
                height: 1.6),
          ),

          const SizedBox(height: 24),

          // Add Money button
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _amountCtrl,
            builder: (_, val, __) {
              final amount = double.tryParse(val.text) ?? 0;
              final enabled = amount > 0;
              return ElevatedButton(
                onPressed: enabled
                    ? () => Navigator.of(context).pop(
                          _TopUpResult(
                            amount: amount,
                            savedCard: _selectedCard,
                          ),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled
                      ? AppTheme.primaryColor
                      : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Add Money',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Send Money sheet ─────────────────────────────────────────────────────────

class _SendMoneySheet extends StatefulWidget {
  final String senderUserId;
  final double currentBalance;
  final WidgetRef ref;
  final VoidCallback onSuccess;

  const _SendMoneySheet({
    required this.senderUserId,
    required this.currentBalance,
    required this.ref,
    required this.onSuccess,
  });

  @override
  State<_SendMoneySheet> createState() => _SendMoneySheetState();
}

class _SendMoneySheetState extends State<_SendMoneySheet> {
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final recipientId = _recipientCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final note = _noteCtrl.text.trim();

    if (recipientId.isEmpty) {
      AppSnackbar.error(context, 'Enter the recipient\'s wallet ID');
      return;
    }
    if (amount <= 0) {
      AppSnackbar.error(context, 'Enter a valid amount');
      return;
    }
    if (amount > widget.currentBalance) {
      AppSnackbar.error(context, 'Insufficient wallet balance');
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.ref.read(walletNotifierProvider.notifier).transfer(
            recipientWalletId: recipientId,
            amount: amount,
            note: note.isEmpty ? null : note,
          );
      widget.ref.invalidate(walletTransactionsProvider);
      widget.onSuccess();
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(
          context,
          '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} sent!',
        );
      }
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2937) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 8,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Current balance display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, const Color(0xFFFF8C5A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text('My Current Balance',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.currencySymbol}${widget.currentBalance.toStringAsFixed(2)}JMD',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Wallet ID field
          Text('7Dash Wallet ID',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF111827)
                  : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _recipientCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Enter 7Dash Wallet ID',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Amount field
          Text('Amount (JMD)',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF111827)
                  : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Note field
          Text('Note',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF111827)
                  : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                hintText: 'Add special Note',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.note_alt_outlined,
                    color: AppTheme.primaryColor, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            '*This money can only be spent on 7Dash',
            style: TextStyle(
                fontSize: 12, color: AppTheme.primaryColor),
          ),

          const SizedBox(height: 20),

          // Send Money button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send Money',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Transaction history sheet ────────────────────────────────────────────────

class _TransactionHistorySheet extends StatelessWidget {
  final WidgetRef ref;
  const _TransactionHistorySheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final txAsync = ref.watch(walletTransactionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text('Transaction History',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color:
                              Theme.of(context).colorScheme.onSurface)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: txAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(friendlyError(e))),
                data: (txns) => txns.isEmpty
                    ? const Center(child: Text('No transactions yet'))
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: txns.length,
                        itemBuilder: (_, i) =>
                            _TransactionTile(tx: txns[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
