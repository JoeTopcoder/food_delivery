import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Admin database lookup screen.
/// Search by card last-4, order ID, or customer email/phone/name.
class AdminLookupScreen extends ConsumerStatefulWidget {
  const AdminLookupScreen({super.key});

  @override
  ConsumerState<AdminLookupScreen> createState() => _AdminLookupScreenState();
}

class _AdminLookupScreenState extends ConsumerState<AdminLookupScreen> {
  final _searchCtrl = TextEditingController();
  _SearchMode _mode = _SearchMode.card;
  bool _loading = false;
  String? _error;

  // Results
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
          final results = await svc.lookupByCard(query);
          setState(() => _cardResults = results);
          if (results.isEmpty) {
            setState(() => _error = 'No cards found ending in "$query"');
          }
          break;
        case _SearchMode.order:
          final result = await svc.lookupByOrderId(query);
          setState(() => _orderResult = result);
          if (result == null) {
            setState(() => _error = 'No order found for "$query"');
          }
          break;
        case _SearchMode.customer:
          final result = await svc.lookupByCustomer(query);
          setState(() => _customerResult = result);
          if (result == null) {
            setState(() => _error = 'No customer found matching "$query"');
          }
          break;
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Database Lookup',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Search Header ────────────────────────────────────────────
          Container(
            color: const Color(0xFF1E293B),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  // Search mode chips
                  Row(
                    children: _SearchMode.values.map((mode) {
                      final selected = _mode == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            mode.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF374151),
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          avatar: Icon(
                            mode.icon,
                            size: 16,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF6B7280),
                          ),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _mode = mode;
                              _searchCtrl.clear();
                              _cardResults = null;
                              _orderResult = null;
                              _customerResult = null;
                              _error = null;
                            });
                          },
                          selectedColor: AppTheme.primaryColor,
                          backgroundColor: Colors.white,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  // Search field
                  TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                    keyboardType: _mode == _SearchMode.card
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: _mode == _SearchMode.card
                        ? [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ]
                        : null,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _mode.hint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: _search,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Results ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const AppLoadingIndicator(message: 'Searching...')
                : _error != null
                ? _EmptyState(message: _error!)
                : _cardResults == null &&
                      _orderResult == null &&
                      _customerResult == null
                ? _EmptyState(
                    message: _mode.emptyPrompt,
                    icon: Icons.manage_search_rounded,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_cardResults != null)
                          _CardResultsView(results: _cardResults!),
                        if (_orderResult != null)
                          _OrderResultView(data: _orderResult!),
                        if (_customerResult != null)
                          _CustomerResultView(data: _customerResult!),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search modes
// ─────────────────────────────────────────────────────────────────────────────

enum _SearchMode {
  card(
    label: 'Card',
    hint: 'Last 4 digits (e.g. 3432)',
    icon: Icons.credit_card_rounded,
    emptyPrompt:
        'Enter last 4 digits of a card to find associated orders & customer info',
  ),
  order(
    label: 'Order ID',
    hint: 'Full or partial order UUID',
    icon: Icons.receipt_long_rounded,
    emptyPrompt:
        'Enter an order ID to see full details, customer, payment & delivery info',
  ),
  customer(
    label: 'Customer',
    hint: 'Email, phone, or name',
    icon: Icons.person_search_rounded,
    emptyPrompt:
        'Search by email, phone, or name to see customer details & orders',
  );

  final String label;
  final String hint;
  final IconData icon;
  final String emptyPrompt;

  const _SearchMode({
    required this.label,
    required this.hint,
    required this.icon,
    required this.emptyPrompt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _EmptyState({
    required this.message,
    this.icon = Icons.search_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFFD1D5DB)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card lookup results
// ─────────────────────────────────────────────────────────────────────────────

class _CardResultsView extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  const _CardResultsView({required this.results});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.credit_card_rounded,
          title:
              '${results.length} Card Match${results.length > 1 ? 'es' : ''}',
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(height: 12),
        for (final entry in results) ...[
          _buildCardEntry(entry),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildCardEntry(Map<String, dynamic> entry) {
    final card = entry['card'] as Map<String, dynamic>? ?? {};
    final customer = entry['customer'] as Map<String, dynamic>?;
    final orders = entry['orders'] as List? ?? [];
    final payments = entry['payments'] as List? ?? [];

    final brand = (card['card_brand'] as String? ?? 'card').toUpperCase();
    final last4 = card['last_four'] as String? ?? '????';
    final holder = card['cardholder_name'] as String? ?? 'Unknown';
    final isDefault = card['is_default'] as bool? ?? false;

    return _ResultCard(
      children: [
        // Card info header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.credit_card_rounded,
                color: Color(0xFF7C3AED),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$brand •••• $last4',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    holder,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Customer info
        if (customer != null) ...[
          const Divider(height: 24),
          _InfoSection(
            title: 'Customer',
            icon: Icons.person_rounded,
            rows: [
              _InfoRow('Name', customer['name'] as String? ?? 'N/A'),
              _InfoRow('Email', customer['email'] as String? ?? 'N/A'),
              _InfoRow('Phone', customer['phone'] as String? ?? 'N/A'),
              _InfoRow(
                'Status',
                (customer['is_active'] as bool? ?? false) ? 'Active' : 'Banned',
              ),
            ],
          ),
        ],

        // Orders
        if (orders.isNotEmpty) ...[
          const Divider(height: 24),
          _InfoSection(
            title: 'Card Orders (${orders.length})',
            icon: Icons.receipt_long_rounded,
            rows: [],
          ),
          const SizedBox(height: 8),
          for (final order in orders)
            _OrderRow(order: order as Map<String, dynamic>, payments: payments),
        ],

        if (orders.isEmpty) ...[
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No card-paid orders found',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order lookup result
// ─────────────────────────────────────────────────────────────────────────────

class _OrderResultView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OrderResultView({required this.data});

  @override
  Widget build(BuildContext context) {
    final order = data['order'] as Map<String, dynamic>? ?? {};
    final customer = data['customer'] as Map<String, dynamic>?;
    final payment = data['payment'] as Map<String, dynamic>?;
    final restaurant = data['restaurant'] as Map<String, dynamic>?;
    final driver = data['driver'] as Map<String, dynamic>?;

    final orderId = order['id'] as String? ?? '';
    final shortId = orderId.length >= 8
        ? orderId.substring(0, 8).toUpperCase()
        : orderId.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.receipt_long_rounded,
          title: 'Order #$shortId',
          color: const Color(0xFFF59E0B),
        ),
        const SizedBox(height: 12),
        _ResultCard(
          children: [
            // Order details
            _InfoSection(
              title: 'Order Details',
              icon: Icons.info_outline_rounded,
              rows: [
                _InfoRow('Order ID', orderId),
                _InfoRow(
                  'Status',
                  _statusLabel(order['status'] as String? ?? ''),
                ),
                _InfoRow(
                  'Total',
                  '\$${(order['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ),
                _InfoRow(
                  'Subtotal',
                  '\$${(order['subtotal'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ),
                _InfoRow(
                  'Delivery Fee',
                  '\$${(order['delivery_fee'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ),
                if (order['discount'] != null)
                  _InfoRow(
                    'Discount',
                    '\$${(order['discount'] as num).toStringAsFixed(2)}',
                  ),
                _InfoRow(
                  'Payment',
                  '${order['payment_method'] ?? 'N/A'} (${order['payment_status'] ?? '?'})',
                ),
                _InfoRow('Ordered At', _formatDateTime(order['ordered_at'])),
                if (order['delivery_address'] != null)
                  _InfoRow('Delivery To', order['delivery_address'] as String),
                if (order['notes'] != null &&
                    (order['notes'] as String).isNotEmpty)
                  _InfoRow('Notes', order['notes'] as String),
              ],
            ),

            // Customer
            if (customer != null) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Customer',
                icon: Icons.person_rounded,
                rows: [
                  _InfoRow('Name', customer['name'] as String? ?? 'N/A'),
                  _InfoRow('Email', customer['email'] as String? ?? 'N/A'),
                  _InfoRow('Phone', customer['phone'] as String? ?? 'N/A'),
                  _InfoRow(
                    'Status',
                    (customer['is_active'] as bool? ?? false)
                        ? 'Active'
                        : 'Banned',
                  ),
                ],
              ),
            ],

            // Payment
            if (payment != null) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Payment Record',
                icon: Icons.payments_rounded,
                rows: [
                  _InfoRow(
                    'Amount',
                    '\$${(payment['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                  _InfoRow('Method', payment['method'] as String? ?? 'N/A'),
                  _InfoRow('Status', payment['status'] as String? ?? 'N/A'),
                  if (payment['transaction_id'] != null)
                    _InfoRow(
                      'Transaction',
                      payment['transaction_id'] as String,
                    ),
                ],
              ),
            ],

            // Restaurant
            if (restaurant != null) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Restaurant',
                icon: Icons.store_rounded,
                rows: [
                  _InfoRow('Name', restaurant['name'] as String? ?? 'N/A'),
                  if (restaurant['phone'] != null)
                    _InfoRow('Phone', restaurant['phone'] as String),
                  if (restaurant['address'] != null)
                    _InfoRow('Address', restaurant['address'] as String),
                ],
              ),
            ],

            // Driver
            if (driver != null) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Driver',
                icon: Icons.delivery_dining_rounded,
                rows: [
                  _InfoRow(
                    'Vehicle',
                    '${driver['vehicle_type'] ?? ''} ${driver['vehicle_number'] ?? ''}',
                  ),
                  if (driver['rating'] != null)
                    _InfoRow(
                      'Rating',
                      '${(driver['rating'] as num).toStringAsFixed(1)} ★',
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _statusLabel(String status) {
    return status.replaceAll('_', ' ').toUpperCase();
  }

  static String _formatDateTime(dynamic dt) {
    if (dt == null) return 'N/A';
    try {
      final parsed = DateTime.parse(dt.toString()).toLocal();
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year} at ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dt.toString();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer lookup result
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerResultView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CustomerResultView({required this.data});

  @override
  Widget build(BuildContext context) {
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final orders = data['orders'] as List? ?? [];
    final cards = data['saved_cards'] as List? ?? [];
    final wallet = data['wallet'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.person_rounded,
          title: customer['name'] as String? ?? 'Customer',
          color: const Color(0xFF3B82F6),
        ),
        const SizedBox(height: 12),
        _ResultCard(
          children: [
            // Customer info
            _InfoSection(
              title: 'Account Info',
              icon: Icons.badge_rounded,
              rows: [
                _InfoRow('ID', customer['id'] as String? ?? ''),
                _InfoRow('Name', customer['name'] as String? ?? 'N/A'),
                _InfoRow('Email', customer['email'] as String? ?? 'N/A'),
                _InfoRow('Phone', customer['phone'] as String? ?? 'N/A'),
                _InfoRow('Role', customer['role'] as String? ?? 'N/A'),
                _InfoRow(
                  'Status',
                  (customer['is_active'] as bool? ?? false)
                      ? 'Active'
                      : 'Banned',
                ),
                _InfoRow(
                  'Member Since',
                  _OrderResultView._formatDateTime(customer['created_at']),
                ),
              ],
            ),

            // Wallet
            if (wallet != null) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Wallet',
                icon: Icons.account_balance_wallet_rounded,
                rows: [
                  _InfoRow(
                    'Balance',
                    '\$${(wallet['balance'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                ],
              ),
            ],

            // Saved cards
            if (cards.isNotEmpty) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Saved Cards (${cards.length})',
                icon: Icons.credit_card_rounded,
                rows: [],
              ),
              const SizedBox(height: 4),
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Icon(
                        Icons.credit_card,
                        size: 16,
                        color: const Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${((card as Map)['card_brand'] as String? ?? '').toUpperCase()} •••• ${card['last_four'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      if (card['is_default'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],

            // Recent orders
            if (orders.isNotEmpty) ...[
              const Divider(height: 24),
              _InfoSection(
                title: 'Recent Orders (${orders.length})',
                icon: Icons.receipt_long_rounded,
                rows: [],
              ),
              const SizedBox(height: 8),
              for (final order in orders)
                _OrderRow(
                  order: order as Map<String, dynamic>,
                  payments: const [],
                ),
            ],

            if (orders.isEmpty) ...[
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No orders found',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final List<Widget> children;
  const _ResultCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoRow> rows;

  const _InfoSection({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      row.value,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<dynamic> payments;

  const _OrderRow({required this.order, required this.payments});

  @override
  Widget build(BuildContext context) {
    final orderId = order['id'] as String? ?? '';
    final shortId = orderId.length >= 8
        ? orderId.substring(0, 8).toUpperCase()
        : orderId.toUpperCase();
    final status = order['status'] as String? ?? '';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final method = order['payment_method'] as String? ?? '';
    final paymentStatus = order['payment_status'] as String? ?? '';
    final orderedAt = order['ordered_at'];

    // Find matching payment record
    final paymentRecord = payments
        .cast<Map<String, dynamic>?>()
        .where((p) => p != null && p['order_id'] == orderId)
        .firstOrNull;
    final txnId = paymentRecord?['transaction_id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$shortId',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$method ($paymentStatus)',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          if (txnId != null) ...[
            const SizedBox(height: 2),
            Text(
              'TXN: $txnId',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF9CA3AF),
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (orderedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              _OrderResultView._formatDateTime(orderedAt),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'delivered':
        bg = const Color(0xFF10B981).withValues(alpha: 0.1);
        fg = const Color(0xFF10B981);
        break;
      case 'cancelled':
        bg = const Color(0xFFEF4444).withValues(alpha: 0.1);
        fg = const Color(0xFFEF4444);
        break;
      case 'pending':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.1);
        fg = const Color(0xFFF59E0B);
        break;
      default:
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.1);
        fg = const Color(0xFF3B82F6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
