import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/stripe/earnings_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/stripe/money_text.dart';

class RequestPayoutSheet extends ConsumerStatefulWidget {
  final String role;
  final int minCents;
  final int maxCents;
  final int availableCents;

  const RequestPayoutSheet({
    super.key,
    required this.role,
    required this.minCents,
    required this.maxCents,
    required this.availableCents,
  });

  @override
  ConsumerState<RequestPayoutSheet> createState() =>
      _RequestPayoutSheetState();
}

class _RequestPayoutSheetState extends ConsumerState<RequestPayoutSheet> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String _payoutMethod = 'standard'; // 'standard' | 'instant'

  static const double _instantFeeRate = 0.015; // 1.5%
  static const int _instantFeeMinCents = 50;   // $0.50 minimum

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _parseCents() {
    final text = _controller.text
        .trim()
        .replaceAll(r'$', '')
        .replaceAll(',', '');
    final dollars = double.tryParse(text);
    if (dollars == null || dollars <= 0) return 0;
    return (dollars * 100).round();
  }

  int _feeCents(int cents) {
    if (_payoutMethod != 'instant') return 0;
    return (cents * _instantFeeRate).ceil().clamp(_instantFeeMinCents, cents);
  }

  void _setMax() {
    final dollars = (widget.availableCents / 100).toStringAsFixed(2);
    _controller.text = dollars;
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    final cents = _parseCents();

    if (cents <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (cents < widget.minCents) {
      setState(() => _error =
          'Minimum payout is \$${(widget.minCents / 100).toStringAsFixed(2)}');
      return;
    }
    if (cents > widget.maxCents) {
      setState(() => _error =
          'Maximum payout is \$${(widget.maxCents / 100).toStringAsFixed(2)}');
      return;
    }
    if (cents > widget.availableCents) {
      setState(() => _error = 'Amount exceeds available balance');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final pr = await ref
        .read(earningsProvider(widget.role).notifier)
        .requestPayout(amountCents: cents, payoutMethod: _payoutMethod);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (pr != null) {
      Navigator.pop(context);
      final label = _payoutMethod == 'instant' ? 'Instant payout' : 'Payout';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label of \$${(cents / 100).toStringAsFixed(2)} requested!',
          ),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );
    } else {
      setState(() {
        _error = ref.read(earningsProvider(widget.role)).error ??
            'Request failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cents = _parseCents();
    final fee = _feeCents(cents);
    final receives = cents > 0 ? cents - fee : 0;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Request Payout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Available: ',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                MoneyText(
                  widget.availableCents,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Payout method selector
            Row(
              children: [
                Expanded(child: _MethodCard(
                  icon: Icons.account_balance_rounded,
                  title: 'Standard',
                  subtitle: '2–3 business days',
                  badge: 'Free',
                  badgeColor: const Color(0xFF22C55E),
                  selected: _payoutMethod == 'standard',
                  onTap: () => setState(() {
                    _payoutMethod = 'standard';
                    _error = null;
                  }),
                )),
                const SizedBox(width: 10),
                Expanded(child: _MethodCard(
                  icon: Icons.credit_card_rounded,
                  title: 'Instant',
                  subtitle: '~30 minutes',
                  badge: '1.5% fee',
                  badgeColor: const Color(0xFFF59E0B),
                  selected: _payoutMethod == 'instant',
                  onTap: () => setState(() {
                    _payoutMethod = 'instant';
                    _error = null;
                  }),
                )),
              ],
            ),
            const SizedBox(height: 16),

            // Amount field
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 28,
                      ),
                      hintText: '0.00',
                      hintStyle: const TextStyle(
                        color: Colors.white24,
                        fontSize: 28,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      errorText: _error,
                      errorStyle: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: _setMax,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: const Text(
                      'MAX',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Min: \$${(widget.minCents / 100).toStringAsFixed(2)} '
              '· Max: \$${(widget.maxCents / 100).toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),

            // Fee breakdown for instant
            if (_payoutMethod == 'instant' && cents > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x26F59E0B)),
                ),
                child: Column(
                  children: [
                    _FeeRow(
                      label: 'Payout amount',
                      value: '\$${(cents / 100).toStringAsFixed(2)}',
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    _FeeRow(
                      label: 'Instant fee (1.5%, min \$0.50)',
                      value: '−\$${(fee / 100).toStringAsFixed(2)}',
                      color: const Color(0xFFF59E0B),
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    _FeeRow(
                      label: 'You receive',
                      value: '\$${(receives / 100).toStringAsFixed(2)}',
                      color: Colors.white,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _payoutMethod == 'instant'
                      ? const Color(0xFFF59E0B)
                      : AppTheme.primaryColor,
                  disabledBackgroundColor: Colors.white12,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _payoutMethod == 'instant'
                            ? 'Send to Debit Card'
                            : 'Confirm Payout',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Helper widgets
// ----------------------------------------------------------------

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? badgeColor.withValues(alpha:0.12) : const Color(0xFF0F1117),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? badgeColor : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? badgeColor : Colors.white54),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _FeeRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
