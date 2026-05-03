import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Restaurant-facing read-only view of their partnership agreement.
class RestaurantContractScreen extends ConsumerStatefulWidget {
  const RestaurantContractScreen({super.key});

  @override
  ConsumerState<RestaurantContractScreen> createState() =>
      _RestaurantContractScreenState();
}

class _RestaurantContractScreenState
    extends ConsumerState<RestaurantContractScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _contract;
  String _storeName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Get restaurant name
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        final restaurant = await ref.read(
          restaurantByOwnerProvider(userId).future,
        );
        _storeName = restaurant?.name ?? '';
      }

      final session = Supabase.instance.client.auth.currentSession;
      final resp = await Supabase.instance.client.functions.invoke(
        'manage-contract',
        method: HttpMethod.get,
        headers: {
          if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = (body['contracts'] as List?) ?? [];
      if (list.isNotEmpty) {
        _contract = list.first as Map<String, dynamic>;
      }
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _val(String key, [String fallback = '']) =>
      _contract?[key]?.toString() ?? fallback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Partnership Agreement',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: AppLoadingIndicator(message: 'Loading contract…'),
            )
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : _contract == null
          ? const AppEmptyState(
              icon: Icons.description_outlined,
              title: 'No Contract Yet',
              subtitle:
                  'Your partnership agreement has not been created yet. '
                  'Please contact support.',
            )
          : _buildContract(),
    );
  }

  Widget _buildContract() {
    final proprietorName = _val('proprietor_name', 'Joel Scott');
    final tradingAs = _val('trading_as');
    final clientName = _storeName.isNotEmpty
        ? _storeName
        : _val('restaurant_name', 'Your Restaurant');
    final commissionMin = _val('commission_min', '10');
    final commissionMax = _val('commission_max', '15');
    final ownMin = _val('own_driver_commission_min', '5');
    final ownMax = _val('own_driver_commission_max', '10');
    final introDays = _val('intro_days', '14');
    final paymentHours = _val('payment_hours', '24-48');
    final terminationDays = _val('termination_days', '14');
    final supportEmail = _val(
      'support_email',
      'support@applizonecentralja.com',
    );
    final supportPhone = _val('support_phone', '876-305-4847');
    final authorizedRep = _val('authorized_personnel');
    final contractDate = _val('contract_date');
    final ceoName = _val('ceo_name', 'Joel Scott');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────
          _card([
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.handshake_rounded,
                  size: 36,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'RESTAURANT PARTNERSHIP\nAGREEMENT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  height: 1.3,
                ),
              ),
            ),
            const Divider(height: 24),
            // Store name ribbon
            if (_storeName.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _storeName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  height: 1.5,
                ),
                children: [
                  const TextSpan(
                    text:
                        'This Agreement for Services is made and entered into '
                        'on the date of signature between:\n\n',
                  ),
                  TextSpan(
                    text: proprietorName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (tradingAs.isNotEmpty) ...[
                    const TextSpan(text: ', trading as '),
                    TextSpan(
                      text: tradingAs,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const TextSpan(
                    text: ' (hereafter referred to as "THE PROPRIETOR")\nAND\n',
                  ),
                  TextSpan(
                    text: clientName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text:
                        ' (hereafter referred to as "THE CLIENT")\n\n'
                        'Collectively referred to as "the Parties".',
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // 1. Purpose
          _section('1. PURPOSE OF AGREEMENT', [
            'This Agreement outlines the terms under which THE CLIENT will '
                'utilize THE PROPRIETOR\'s food delivery platform to receive, '
                'prepare, and fulfill customer orders.',
            'The objective of this partnership is to enable THE CLIENT to '
                'increase profitability, retain customers, and grow sustainably '
                'through a transparent and low-cost delivery model.',
          ]),

          // 2. Platform Access
          _numberedSection('2. PLATFORM ACCESS & USAGE', {
            '2.1':
                'THE PROPRIETOR is authorized to display THE CLIENT\'s restaurant '
                'name, logo, menu, and related business information on the platform.',
            '2.2':
                'THE CLIENT agrees to use the provided application to manage menu '
                'items, pricing, availability, and operational status.',
            '2.3':
                'Initial onboarding, including menu setup and profile creation, '
                'will be completed by THE PROPRIETOR at no cost.',
            '2.4':
                'THE CLIENT is responsible for ensuring all menu details and '
                'pricing remain accurate and updated.',
          }),

          // 3. Order Management
          _numberedSection('3. ORDER MANAGEMENT', {
            '3.1':
                'Orders placed through the platform will be transmitted to THE '
                'CLIENT in real time.',
            '3.2':
                'THE CLIENT agrees to confirm and begin preparation of orders '
                'within a reasonable timeframe to ensure efficient delivery.',
            '3.3':
                'THE CLIENT agrees to prioritize delivery orders to maintain '
                'service quality and customer satisfaction.',
          }),

          // 4. Fees & Payment
          _card([
            _heading('4. FEES & PAYMENT TERMS'),
            const SizedBox(height: 8),
            _nItem('4.1', [
              const TextSpan(
                text: 'Introductory Offer:\n',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: 'THE CLIENT will receive '),
              const TextSpan(
                text: '0% commission',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' for the first '),
              TextSpan(
                text: '$introDays days',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const TextSpan(text: ' from activation.'),
            ]),
            _nItem('4.2', [
              const TextSpan(
                text: 'Standard Commission:\n',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: 'After the introductory period:\n• '),
              TextSpan(
                text: '$commissionMin%–$commissionMax%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const TextSpan(text: ' per order (standard delivery)\n• '),
              TextSpan(
                text: '$ownMin%–$ownMax%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const TextSpan(
                text: ' where THE CLIENT utilizes its own delivery drivers',
              ),
            ]),
            _nText(
              '4.3',
              'THE PROPRIETOR shall not impose hidden fees, mandatory '
                  'promotions, or additional charges without prior agreement.',
            ),
            _nItem('4.4', [
              const TextSpan(
                text:
                    'Payments for completed orders will be transferred to '
                    'THE CLIENT within ',
              ),
              TextSpan(
                text: '$paymentHours hours',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const TextSpan(text: '.'),
            ]),
          ]),
          const SizedBox(height: 12),

          // 5. Marketing
          _numberedSection('5. MARKETING & PROMOTION', {
            '5.1':
                'THE PROPRIETOR agrees to actively promote THE CLIENT\'s restaurant '
                'within the platform at no additional cost.',
            '5.2':
                'Promotional support may include:\n'
                '• Featured placement within the application\n'
                '• "Restaurant of the Week" campaigns\n'
                '• In-app visibility boosts',
            '5.3':
                'THE CLIENT may approve or decline any external promotional '
                'materials.',
          }),

          // 6. Customer Retention
          _numberedSection('6. CUSTOMER RETENTION SYSTEM', {
            '6.1':
                'THE PROPRIETOR will provide a built-in loyalty system designed to '
                'encourage repeat purchases for THE CLIENT.',
            '6.2':
                'Customers interacting with THE CLIENT through the platform may '
                'receive rewards and incentives tied directly to THE CLIENT\'s '
                'restaurant.',
          }),

          // 7. Business Control
          _numberedSection('7. BUSINESS CONTROL', {
            '7.1':
                'THE CLIENT retains full control over:\n'
                '• Menu pricing\n'
                '• Promotions and discounts\n'
                '• Brand identity and presentation',
            '7.2':
                'THE PROPRIETOR shall not enforce pricing changes or mandatory '
                'discounts.',
          }),

          // 8. Technical Support
          _numberedSection('8. TECHNICAL & OPERATIONAL SUPPORT', {
            '8.1':
                'THE PROPRIETOR will provide ongoing technical support for the '
                'platform and order system.',
            '8.2':
                'THE CLIENT may contact support for order issues, menu updates, '
                'or system assistance.',
          }),

          // 9. Liability
          _numberedSection('9. LIABILITY & RESPONSIBILITY', {
            '9.1':
                'THE CLIENT is responsible for food quality, accuracy of orders, '
                'and preparation standards.',
            '9.2':
                'THE PROPRIETOR is responsible for delivery operations and customer '
                'communication related to delivery.',
            '9.3':
                'Each party agrees to operate in good faith to resolve any '
                'service issues.',
          }),

          // 10. Term & Termination
          _card([
            _heading('10. TERM & TERMINATION'),
            const SizedBox(height: 8),
            _nText(
              '10.1',
              'This Agreement shall take effect upon signature and continue '
                  'until terminated by either party.',
            ),
            _nItem('10.2', [
              const TextSpan(
                text: 'Either party may terminate this Agreement with ',
              ),
              TextSpan(
                text: '$terminationDays days',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const TextSpan(text: ' written notice.'),
            ]),
            _nText('10.3', 'No long-term contractual obligation is required.'),
          ]),
          const SizedBox(height: 12),

          // 11. Confidentiality
          _numberedSection('11. CONFIDENTIALITY', {
            '11.1':
                'Both parties agree to keep confidential any proprietary or '
                'business-sensitive information shared during this partnership.',
          }),

          // 12. Dispute Resolution
          _numberedSection('12. DISPUTE RESOLUTION', {
            '12.1':
                'Any disputes arising under this Agreement shall first be resolved '
                'through mutual discussion.',
            '12.2':
                'If unresolved, the matter may be referred to mediation or legal '
                'proceedings in accordance with applicable laws.',
          }),

          // 13. Acceptance / Signatures
          _card([
            _heading('13. ACCEPTANCE'),
            const SizedBox(height: 8),
            const Text(
              'By signing below, both parties acknowledge that they have '
              'read, understood, and agreed to the terms outlined in this '
              'Agreement.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // Client
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE CLIENT',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow('Restaurant Name', clientName),
                  if (authorizedRep.isNotEmpty)
                    _infoRow('Authorized Representative', authorizedRep),
                  if (contractDate.isNotEmpty) _infoRow('Date', contractDate),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Proprietor
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE PROPRIETOR',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow('Name', ceoName),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Contact
          _card([
            _heading('CONTACT INFORMATION'),
            const SizedBox(height: 8),
            _infoRow('Email', supportEmail),
            _infoRow('Phone', supportPhone),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Layout helpers ──────────────────────────────────────────────────────

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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

  Widget _heading(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E293B),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Simple section with heading + plain paragraphs
  Widget _section(String title, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card([
        _heading(title),
        const SizedBox(height: 8),
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              p,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                height: 1.5,
              ),
            ),
          ),
      ]),
    );
  }

  /// Section with numbered items (plain text)
  Widget _numberedSection(String title, Map<String, String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card([
        _heading(title),
        const SizedBox(height: 8),
        for (final e in items.entries) _nText(e.key, e.value),
      ]),
    );
  }

  Widget _nText(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              num,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nItem(String num, List<InlineSpan> spans) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              num,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  height: 1.5,
                ),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
