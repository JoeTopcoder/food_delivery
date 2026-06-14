import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

enum _SearchMode {
  card('Card', 'Last 4 digits (e.g. 3432)', Icons.credit_card_rounded, 'Enter last 4 digits of a card to find associated orders & customer info'),
  order('Order ID', 'Full or partial order UUID', Icons.receipt_long_rounded, 'Enter an order ID to see full details, customer, payment & delivery info'),
  customer('Customer', 'Email, phone, or name', Icons.person_search_rounded, 'Search by email, phone, or name to see customer details & orders');

  final String label;
  final String hint;
  final IconData icon;
  final String emptyPrompt;
  const _SearchMode(this.label, this.hint, this.icon, this.emptyPrompt);
}

class WebAdminLookupPage extends ConsumerStatefulWidget {
  const WebAdminLookupPage({super.key});

  @override
  ConsumerState<WebAdminLookupPage> createState() => _WebAdminLookupPageState();
}

class _WebAdminLookupPageState extends ConsumerState<WebAdminLookupPage> {
  final _searchCtrl = TextEditingController();
  _SearchMode _mode = _SearchMode.card;
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>>? _cardResults;
  Map<String, dynamic>? _orderResult;
  Map<String, dynamic>? _customerResult;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _cardResults = null;
      _orderResult = null;
      _customerResult = null;
    });
    try {
      final svc = ref.read(adminServiceProvider);
      switch (_mode) {
        case _SearchMode.card:
          final r = await svc.lookupByCard(query);
          setState(() { _cardResults = r; if (r.isEmpty) _error = 'No cards found ending in "$query"'; });
          break;
        case _SearchMode.order:
          final r = await svc.lookupByOrderId(query);
          setState(() { _orderResult = r; if (r == null) _error = 'No order found for "$query"'; });
          break;
        case _SearchMode.customer:
          final r = await svc.lookupByCustomer(query);
          setState(() { _customerResult = r; if (r == null) _error = 'No customer found matching "$query"'; });
          break;
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _clear() {
    _searchCtrl.clear();
    setState(() { _cardResults = null; _orderResult = null; _customerResult = null; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Database Lookup', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Search by card number, order ID, or customer identity', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ],
          ),
          const SizedBox(height: 24),

          // ── Search panel ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode chips
                Wrap(
                  spacing: 8,
                  children: _SearchMode.values.map((mode) {
                    final sel = _mode == mode;
                    return GestureDetector(
                      onTap: () { setState(() { _mode = mode; _clear(); }); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(mode.icon, size: 16, color: sel ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(mode.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF374151))),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Search field
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onSubmitted: (_) => _search(),
                        textInputAction: TextInputAction.search,
                        keyboardType: _mode == _SearchMode.card ? TextInputType.number : TextInputType.text,
                        inputFormatters: _mode == _SearchMode.card
                            ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]
                            : null,
                        decoration: InputDecoration(
                          hintText: _mode.hint,
                          prefixIcon: Icon(Icons.search, color: AppTheme.primaryColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: _loading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search_rounded, size: 18, color: Colors.white),
                      label: const Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Results ──────────────────────────────────────────────────
          if (_loading)
            const SizedBox(height: 200, child: AppLoadingIndicator(message: 'Searching…'))
          else if (_error != null)
            _EmptyState(message: _error!)
          else if (_cardResults == null && _orderResult == null && _customerResult == null)
            _EmptyState(message: _mode.emptyPrompt, icon: Icons.manage_search_rounded)
          else ...[
            if (_cardResults != null) _CardResultsSection(results: _cardResults!),
            if (_orderResult != null) _OrderResultSection(data: _orderResult!),
            if (_customerResult != null) _CustomerResultSection(data: _customerResult!),
          ],
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyState({required this.message, this.icon = Icons.search_off_rounded});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 56, color: const Color(0xFFD1D5DB)),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.5)),
      ]),
    ),
  );
}

// ── Section header helper ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader({required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 16)),
    const SizedBox(width: 10),
    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
  ]);
}

// ── Card results ──────────────────────────────────────────────────────────────

class _CardResultsSection extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  const _CardResultsSection({required this.results});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.credit_card_rounded, title: '${results.length} Card Match${results.length > 1 ? 'es' : ''}', color: const Color(0xFF7C3AED)),
        const SizedBox(height: 12),
        ...results.map((entry) {
          final card = entry['card'] as Map<String, dynamic>? ?? {};
          final customer = entry['customer'] as Map<String, dynamic>? ?? {};
          final orders = (entry['orders'] as List?) ?? [];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.credit_card_rounded, size: 20, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 8),
                  Text('•••• •••• •••• ${card['last4'] ?? '????'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2)),
                  const SizedBox(width: 12),
                  Text('${card['brand'] ?? ''} · ${card['exp_month'] ?? '??'}/${card['exp_year'] ?? '??'}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ]),
                const SizedBox(height: 8),
                Text('Customer: ${customer['name'] ?? '—'} · ${customer['email'] ?? '—'}', style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                const SizedBox(height: 12),
                Text('${orders.length} Order${orders.length != 1 ? 's' : ''} with this card', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              ]),
            ),
          );
        }),
      ],
    );
  }
}

// ── Order result ──────────────────────────────────────────────────────────────

class _OrderResultSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OrderResultSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final order = data['order'] as Map<String, dynamic>? ?? data;
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final driver = data['driver'] as Map<String, dynamic>? ?? {};
    final restaurant = data['restaurant'] as Map<String, dynamic>? ?? {};
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final status = order['status'] as String? ?? '—';
    final orderedAt = order['ordered_at'] != null ? DateTime.tryParse(order['ordered_at'] as String) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.receipt_long_rounded, title: 'Order Result', color: const Color(0xFF0EA5E9)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Order ID: ${(order['id'] as String? ?? '').substring(0, 8)}…', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF374151)))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                ),
                const SizedBox(width: 12),
                Text('${AppConstants.currencySymbol}${fmt.format(total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              if (orderedAt != null) Text(DateFormat('MMM d, y HH:mm').format(orderedAt), style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              const Divider(height: 20),
              _Row2('Customer', customer['name'] ?? '—', customer['email'] ?? '—'),
              if (restaurant.isNotEmpty) _Row2('Restaurant', restaurant['name'] ?? '—', ''),
              if (driver.isNotEmpty) _Row2('Driver', driver['name'] ?? '—', driver['phone'] ?? ''),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Row2 extends StatelessWidget {
  final String label;
  final String v1;
  final String v2;
  const _Row2(this.label, this.v1, this.v2);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600))),
      Text(v1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      if (v2.isNotEmpty) ...[const Text(' · ', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))), Text(v2, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))],
    ]),
  );
}

// ── Customer result ───────────────────────────────────────────────────────────

class _CustomerResultSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CustomerResultSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final customer = data['customer'] as Map<String, dynamic>? ?? data;
    final orders = (data['orders'] as List?) ?? [];
    final cards = (data['cards'] as List?) ?? [];
    final walletBalance = (data['wallet_balance'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.person_search_rounded, title: 'Customer Found', color: const Color(0xFF10B981)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Profile
              Row(children: [
                Container(width: 52, height: 52, decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.person_rounded, color: Color(0xFF10B981), size: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer['name'] ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(customer['email'] ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                  if (customer['phone'] != null) Text(customer['phone'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${AppConstants.currencySymbol}${fmt.format(walletBalance)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                  const Text('Wallet', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ]),
              ]),
              const Divider(height: 20),

              // Stats row
              Row(children: [
                _StatItem('Orders', '${orders.length}'),
                const SizedBox(width: 24),
                _StatItem('Cards', '${cards.length}'),
                const SizedBox(width: 24),
                _StatItem('Total Spent', '${AppConstants.currencySymbol}${fmt.format(orders.fold<double>(0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0)))}'),
              ]),

              if (cards.isNotEmpty) ...[
                const Divider(height: 20),
                const Text('Saved Cards', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                const SizedBox(height: 8),
                ...cards.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${c['brand'] ?? ''} •••• ${c['last4'] ?? ''}  ${c['exp_month'] ?? ''}/${c['exp_year'] ?? ''}',
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFF374151))),
                )),
              ],

              if (orders.isNotEmpty) ...[
                const Divider(height: 20),
                const Text('Recent Orders', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                const SizedBox(height: 8),
                ...orders.take(5).map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: Text('…${(o['id'] as String? ?? '').substring(((o['id'] as String?) ?? '').length > 8 ? ((o['id'] as String?) ?? '').length - 8 : 0)}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF9CA3AF)))),
                    Text('${AppConstants.currencySymbol}${fmt.format((o['total_amount'] as num?)?.toDouble() ?? 0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Text((o['status'] as String? ?? '').toUpperCase(), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ]),
                )),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
    ],
  );
}
