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
import '../../core/utils/responsive.dart';

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
    final clean = uid.replaceAll('-', '');
    return clean.substring(0, clean.length.clamp(0, 6)).toUpperCase();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _topUp() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    if (!mounted) return;

    final result = await Navigator.of(context).push<_TopUpResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _TopUpPage(walletDisplayId: _walletDisplayId(), userId: userId),
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
          // walletBalanceStreamProvider auto-updates when the DB row changes,
          // which then triggers walletTransactionsStreamProvider to re-fetch.
          ref.invalidate(walletTransactionsStreamProvider);
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

  Future<void> _depositWithSavedCard(
    double amount,
    SavedCard card,
    String cvv,
  ) async {
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
        AppSnackbar.error(
          context,
          e.error.localizedMessage ?? 'Payment failed. Please try again.',
        );
      }
      return;
    }
    if (!mounted) return;
    try {
      await ref.read(walletNotifierProvider.notifier).deposit(amount);
      ref.invalidate(walletTransactionsStreamProvider);
      if (mounted) {
        AppSnackbar.success(
          context,
          '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} added via ${card.displayBrand} ••••${card.lastFour}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Payment charged but wallet update failed. Contact support with ref: wallet-topup',
        );
      }
    }
  }

  Future<void> _depositWithNewCard(double amount) async {
    final paymentService = ref.read(paymentServiceProvider);
    final authUser = Supabase.instance.client.auth.currentUser;
    final email = authUser?.email ?? '';
    final name = authUser?.userMetadata?['name'] as String? ?? 'Customer';
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
    try {
      await ref.read(walletNotifierProvider.notifier).deposit(amount);
      ref.invalidate(walletTransactionsStreamProvider);
      if (mounted) {
        AppSnackbar.success(
          context,
          '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)} added to wallet',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Payment charged but wallet update failed. Contact support with ref: wallet-topup',
        );
      }
    }
  }

  // ── Saved cards section ───────────────────────────────────────────────────

  Widget _buildCardsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.credit_card_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
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
          error: (e, _) => Text(
            friendlyError(e),
            style: TextStyle(color: AppTheme.errorColor),
          ),
          data: (cards) {
            if (cards.isEmpty) {
              return _EmptyCardsPlaceholder(onAdd: _addNewCard);
            }

            final pendingCards = cards
                .where((c) => c.isPending && !c.isExpired)
                .toList();
            final expiredCards = cards
                .where((c) => c.isPending && c.isExpired)
                .toList();
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
                            'Check your bank statement for the charge amount, then tap Verify.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                ...failedCards.map(
                  (card) => _SavedCardTile(
                    key: ValueKey('${card.id}_${card.status}'),
                    card: card,
                    isDark: isDark,
                    onSetDefault: () {},
                    onDelete: () => _deleteCard(card),
                  ),
                ),
                ...verifiedCards.map(
                  (card) => _SavedCardTile(
                    key: ValueKey('${card.id}_${card.status}'),
                    card: card,
                    isDark: isDark,
                    onSetDefault: () => _setDefaultCard(card),
                    onDelete: () => _deleteCard(card),
                  ),
                ),

                const SizedBox(height: 12),

                // "Add New Card +" bottom button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addNewCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add New Card +',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
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
    // Stream provider gives real-time balance updates from Supabase.
    // walletNotifierProvider is kept only for mutation actions (deposit, send).
    final walletAsync = ref.watch(walletBalanceStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Payment & Wallet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Invalidating both recreates the streams and forces an immediate
          // re-fetch of balance and full transaction history.
          ref.invalidate(walletBalanceStreamProvider);
          ref.invalidate(walletTransactionsStreamProvider);
        },
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            16,
            Responsive.horizontalPadding(context),
            32,
          ),
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
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                friendlyError(e),
                style: TextStyle(color: AppTheme.errorColor),
              ),
            ),

            const SizedBox(height: 16),

            // Outstanding debt banner
            if (walletAsync.valueOrNull?.hasDebt == true)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Outstanding Balance',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.orange.shade800)),
                          const SizedBox(height: 3),
                          Text(
                            '${AppConstants.currencySymbol}${walletAsync.valueOrNull!.debtBalance.toStringAsFixed(2)} '
                            'will be automatically deducted from your next top-up.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 28),

            // Saved cards
            _buildCardsSection(),
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
    final balance  = wallet?.balance ?? 0;
    final cashback = wallet?.cashbackBalance ?? 0;
    final reserved = wallet?.reservedBalance ?? 0;
    // Show spendable balance (what the user can actually use right now).
    final available = (balance + cashback - reserved).clamp(0.0, double.infinity);

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
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 20,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5B03C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'History',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'Available Balance',
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
                '${AppConstants.currencySymbol}${available.toStringAsFixed(2)}',
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
                  AppConstants.currencyCode,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (reserved > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${AppConstants.currencySymbol}${reserved.toStringAsFixed(2)} on hold',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ],
          if ((wallet?.debtBalance ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${AppConstants.currencySymbol}${wallet!.debtBalance.toStringAsFixed(2)} outstanding — clears on next top-up',
              style: TextStyle(
                color: Colors.orange.shade200,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

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
  const _EmptyCardsPlaceholder({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.credit_card_off_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'No cards added yet',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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

  static _TxMeta _meta(String type, String? desc) {
    final d = (desc ?? '').toLowerCase();
    // Laundry-specific overrides
    if (d.contains('laundry') && d.contains('refund')) {
      return _TxMeta('Laundry Refund', Icons.local_laundry_service_rounded,
          const Color(0xFF3B82F6));
    }
    if (d.contains('laundry') && d.contains('payment')) {
      return _TxMeta('Laundry Payment', Icons.local_laundry_service_rounded,
          const Color(0xFF8B5CF6));
    }
    if (d.contains('laundry') && d.contains('cancel')) {
      return _TxMeta('Laundry Cancelled', Icons.local_laundry_service_rounded,
          const Color(0xFF3B82F6));
    }
    return switch (type) {
      'deposit'           => _TxMeta('Top Up',           Icons.add_circle_rounded,           const Color(0xFF10B981)),
      'payment'           => _TxMeta('Payment',          Icons.shopping_bag_outlined,         const Color(0xFF6366F1)),
      'cashback'          => _TxMeta('Cashback',         Icons.card_giftcard_rounded,         const Color(0xFFF59E0B)),
      'refund'            => _TxMeta('Refund',           Icons.keyboard_return_rounded,       const Color(0xFF3B82F6)),
      'penalty'           => _TxMeta('Penalty',          Icons.warning_amber_rounded,         const Color(0xFFEF4444)),
      'tip_received'      => _TxMeta('Tip Received',     Icons.favorite_rounded,              const Color(0xFF10B981)),
      'transfer_sent'     => _TxMeta('Sent',             Icons.send_rounded,                  const Color(0xFF6366F1)),
      'transfer_received' => _TxMeta('Received',         Icons.call_received_rounded,         const Color(0xFF10B981)),
      _                   => _TxMeta(type.replaceAll('_', ' ').capitalize(), Icons.receipt_rounded, Colors.grey),
    };
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final c   = AppConstants.currencySymbol;
    final meta = _meta(tx.type, tx.description);
    final isCredit = tx.amount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Icon bubble
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(meta.icon, color: meta.color, size: 22),
          ),
          const SizedBox(width: 12),
          // Label + description + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      meta.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (tx.status != 'completed') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tx.status.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange),
                        ),
                      ),
                    ],
                  ],
                ),
                if (tx.description != null &&
                    tx.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _relativeTime(tx.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}$c${tx.amount.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: isCredit
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _TxMeta(this.label, this.icon, this.color);
}

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
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
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (card.isDefault && card.isVerified) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(
                              label: 'DEFAULT',
                              color: AppTheme.primaryColor,
                            ),
                          ],
                          if (isPending) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(
                              label: 'PENDING',
                              color: Colors.orange,
                            ),
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
                            fontSize: 11,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Menu or delete
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
                      Icons.more_horiz_rounded,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      size: 22,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                    color: Colors.orange.withValues(alpha: 0.25),
                  ),
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
                                      if (matched) _amountCtrl.clear();
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
          Text(
            'Enter CVV',
            style: TextStyle(
              fontSize: Responsive.headingMedium(context),
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.card.displayBrand}  ••••  ${widget.card.lastFour}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
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
                borderRadius: BorderRadius.circular(12),
              ),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Pay  ${AppConstants.currencySymbol}${widget.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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

class _TopUpPage extends ConsumerStatefulWidget {
  final String walletDisplayId;
  final String userId;
  const _TopUpPage({required this.walletDisplayId, required this.userId});

  @override
  ConsumerState<_TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends ConsumerState<_TopUpPage> {
  final _amountCtrl = TextEditingController();
  SavedCard? _selectedCard;

  @override
  void initState() {
    super.initState();
    // Read the initial provider value synchronously on first frame.
    // ref.listen only fires on *changes*, so if the provider is already cached
    // the listener never triggers and _selectedCard stays null.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSelectedCard(ref.read(savedCardsProvider(widget.userId)));
    });
  }

  void _syncSelectedCard(AsyncValue<List<SavedCard>> cardsAsync) {
    final cards =
        cardsAsync.valueOrNull
            ?.where((c) => c.isVerified && c.stripePaymentMethodId != null)
            .toList() ??
        [];
    if (cards.isEmpty) {
      if (_selectedCard != null) setState(() => _selectedCard = null);
      return;
    }
    // Keep current selection if it's still in the list
    if (_selectedCard != null && cards.any((c) => c.id == _selectedCard!.id)) {
      return;
    }
    setState(
      () => _selectedCard = cards.firstWhere(
        (c) => c.isDefault,
        orElse: () => cards.first,
      ),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _addNewCard() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddCardScreen()));
    if (result == true && mounted) {
      ref.invalidate(savedCardsProvider(widget.userId));
      setState(() => _selectedCard = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardsAsync = ref.watch(savedCardsProvider(widget.userId));
    final verifiedCards =
        cardsAsync.valueOrNull
            ?.where((c) => c.isVerified && c.stripePaymentMethodId != null)
            .toList() ??
        [];

    // Keep selection in sync whenever the provider emits a new value
    ref.listen<AsyncValue<List<SavedCard>>>(
      savedCardsProvider(widget.userId),
      (_, next) => _syncSelectedCard(next),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Top-up',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Wallet ID
          Text(
            'Your 7Dash Wallet ID',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.walletDisplayId,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Amount
          Text(
            'Amount',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Card selector section
          Row(
            children: [
              Text(
                'Select Credit / Debit Card',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addNewCard,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Card', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          cardsAsync.when(
            loading: () => const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => const SizedBox.shrink(),
            data: (_) {
              if (verifiedCards.isEmpty) {
                return GestureDetector(
                  onTap: _addNewCard,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1F2937)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF374151)
                            : Colors.grey.shade200,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_card_rounded,
                          color: AppTheme.primaryColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Add New Card',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: verifiedCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final card = verifiedCards[i];
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
                                  Text(
                                    card.displayBrand,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    '••••${card.lastFour}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
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
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          Text(
            '*This money can only be spent on 7Dash.\n'
            '*You can send 7Dash wallet money to other 7Dash wallets.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.primaryColor,
              height: 1.6,
            ),
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
                    ? () {
                        // Defensive: if _selectedCard is still null but there are
                        // verified cards (e.g. listener never fired), pick the default.
                        final card =
                            _selectedCard ??
                            (verifiedCards.isNotEmpty
                                ? verifiedCards.firstWhere(
                                    (c) => c.isDefault,
                                    orElse: () => verifiedCards.first,
                                  )
                                : null);
                        Navigator.of(
                          context,
                        ).pop(_TopUpResult(amount: amount, savedCard: card));
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled
                      ? AppTheme.primaryColor
                      : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Add Money',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
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
      await widget.ref
          .read(walletNotifierProvider.notifier)
          .transfer(
            recipientWalletId: recipientId,
            amount: amount,
            note: note.isEmpty ? null : note,
          );
      widget.ref.invalidate(walletTransactionsStreamProvider);
      widget.ref.invalidate(walletBalanceStreamProvider);
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
                Text(
                  'My Current Balance',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
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
          Text(
            '7Dash Wallet ID',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : const Color(0xFFECF8F5),
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
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Amount field
          Text(
            'Amount (JMD)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Note field
          Text(
            'Note',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : const Color(0xFFECF8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                hintText: 'Add special Note',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.note_alt_outlined,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            '*This money can only be spent on 7Dash',
            style: TextStyle(fontSize: 12, color: AppTheme.primaryColor),
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
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Send Money',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Transaction history sheet ────────────────────────────────────────────────

class _TransactionHistorySheet extends ConsumerStatefulWidget {
  const _TransactionHistorySheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_TransactionHistorySheet> createState() =>
      _TransactionHistorySheetState();
}

class _TransactionHistorySheetState
    extends ConsumerState<_TransactionHistorySheet> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.watch(currentUserIdProvider);
    // Stream provider — updates live whenever a new transaction is written.
    final txAsync = ref.watch(walletTransactionsStreamProvider);

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Transaction History',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (currentUserId == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No user session detected. Transactions require login.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Divider(height: 1),
            Expanded(
              child: txAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Error loading transactions',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(friendlyError(error),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          onPressed: () =>
                              ref.invalidate(walletTransactionsStreamProvider),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (txns) {
                  if (txns.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 56,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('No transactions yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                            const SizedBox(height: 6),
                            Text('Top up or make a booking to get started.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    );
                  }

                  // Group transactions by date label
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final yesterday = today.subtract(const Duration(days: 1));
                  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));

                  String dateLabel(DateTime dt) {
                    final d = DateTime(dt.year, dt.month, dt.day);
                    if (!d.isBefore(today)) return 'Today';
                    if (!d.isBefore(yesterday) && d.isBefore(today)) return 'Yesterday';
                    if (!d.isBefore(thisWeekStart)) return 'This Week';
                    return DateFormat('MMMM yyyy').format(dt);
                  }

                  final List<Object> items = [];
                  String? lastLabel;
                  for (final tx in txns) {
                    final label = dateLabel(tx.createdAt);
                    if (label != lastLabel) {
                      items.add(label);
                      lastLabel = label;
                    }
                    items.add(tx);
                  }

                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            item,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              letterSpacing: 0.3,
                            ),
                          ),
                        );
                      }
                      return _TransactionTile(tx: item as WalletTransaction);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
