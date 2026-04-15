import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Admin screen for viewing/editing the restaurant partnership agreement.
class AdminContractScreen extends ConsumerStatefulWidget {
  const AdminContractScreen({super.key});

  @override
  ConsumerState<AdminContractScreen> createState() =>
      _AdminContractScreenState();
}

class _AdminContractScreenState extends ConsumerState<AdminContractScreen> {
  bool _editing = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _contractId;

  // ── Editable fields ─────────────────────────────────────────────────────
  late final TextEditingController _proprietorName;
  late final TextEditingController _tradingAs;
  late final TextEditingController _clientName;
  late final TextEditingController _commissionMin;
  late final TextEditingController _commissionMax;
  late final TextEditingController _ownDriverCommissionMin;
  late final TextEditingController _ownDriverCommissionMax;
  late final TextEditingController _introDays;
  late final TextEditingController _paymentHours;
  late final TextEditingController _terminationDays;
  late final TextEditingController _supportEmail;
  late final TextEditingController _supportPhone;
  late final TextEditingController _restaurantName;
  late final TextEditingController _authorizedPersonnel;
  late final TextEditingController _contractDate;
  late final TextEditingController _ceoName;
  late final TextEditingController _ceoDate;

  @override
  void initState() {
    super.initState();
    _proprietorName = TextEditingController();
    _tradingAs = TextEditingController();
    _clientName = TextEditingController();
    _commissionMin = TextEditingController();
    _commissionMax = TextEditingController();
    _ownDriverCommissionMin = TextEditingController();
    _ownDriverCommissionMax = TextEditingController();
    _introDays = TextEditingController();
    _paymentHours = TextEditingController();
    _terminationDays = TextEditingController();
    _supportEmail = TextEditingController();
    _supportPhone = TextEditingController();
    _restaurantName = TextEditingController();
    _authorizedPersonnel = TextEditingController();
    _contractDate = TextEditingController();
    _ceoName = TextEditingController();
    _ceoDate = TextEditingController();
    _loadContracts();
  }

  Future<void> _loadContracts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
        _applyData(list.first as Map<String, dynamic>);
      } else {
        _applyDefaults();
      }
    } catch (e) {
      debugPrint('Contract load error: $e');
      setState(() => _error = friendlyError(e));
      _applyDefaults();
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyData(Map<String, dynamic> d) {
    _contractId = d['id']?.toString();
    _proprietorName.text = d['proprietor_name'] ?? 'Joel Scott';
    _tradingAs.text = d['trading_as'] ?? '';
    _clientName.text = d['client_name'] ?? '';
    _commissionMin.text = (d['commission_min'] ?? 10).toString();
    _commissionMax.text = (d['commission_max'] ?? 15).toString();
    _ownDriverCommissionMin.text = (d['own_driver_commission_min'] ?? 5)
        .toString();
    _ownDriverCommissionMax.text = (d['own_driver_commission_max'] ?? 10)
        .toString();
    _introDays.text = (d['intro_days'] ?? 14).toString();
    _paymentHours.text = d['payment_hours'] ?? '24-48';
    _terminationDays.text = (d['termination_days'] ?? 14).toString();
    _supportEmail.text = d['support_email'] ?? 'suppor@applizonecentralja.com';
    _supportPhone.text = d['support_phone'] ?? '876-305-4847';
    _restaurantName.text = d['restaurant_name'] ?? '';
    _authorizedPersonnel.text = d['authorized_personnel'] ?? '';
    _contractDate.text = d['contract_date'] ?? '';
    _ceoName.text = d['ceo_name'] ?? 'Joel Scott';
    _ceoDate.text = d['ceo_date'] ?? '';
  }

  void _applyDefaults() {
    _proprietorName.text = 'Joel Scott';
    _tradingAs.text = '';
    _clientName.text = '';
    _commissionMin.text = '10';
    _commissionMax.text = '15';
    _ownDriverCommissionMin.text = '5';
    _ownDriverCommissionMax.text = '10';
    _introDays.text = '14';
    _paymentHours.text = '24-48';
    _terminationDays.text = '14';
    _supportEmail.text = 'suppor@applizonecentralja.com';
    _supportPhone.text = '876-305-4847';
    _restaurantName.text = '';
    _authorizedPersonnel.text = '';
    _contractDate.text = '';
    _ceoName.text = 'Joel Scott';
    _ceoDate.text = '';
  }

  Map<String, dynamic> _toPayload() => {
    if (_contractId != null) 'id': _contractId,
    'proprietor_name': _proprietorName.text,
    'trading_as': _tradingAs.text,
    'client_name': _clientName.text,
    'commission_min': double.tryParse(_commissionMin.text) ?? 10,
    'commission_max': double.tryParse(_commissionMax.text) ?? 15,
    'own_driver_commission_min':
        double.tryParse(_ownDriverCommissionMin.text) ?? 5,
    'own_driver_commission_max':
        double.tryParse(_ownDriverCommissionMax.text) ?? 10,
    'intro_days': int.tryParse(_introDays.text) ?? 14,
    'payment_hours': _paymentHours.text,
    'termination_days': int.tryParse(_terminationDays.text) ?? 14,
    'support_email': _supportEmail.text,
    'support_phone': _supportPhone.text,
    'restaurant_name': _restaurantName.text,
    'authorized_personnel': _authorizedPersonnel.text,
    'contract_date': _contractDate.text.isEmpty ? null : _contractDate.text,
    'ceo_name': _ceoName.text,
    'ceo_date': _ceoDate.text.isEmpty ? null : _ceoDate.text,
  };

  Future<void> _save() async {
    if (_clientName.text.trim().isEmpty) {
      AppSnackbar.warning(context, 'Client name is required');
      return;
    }
    setState(() => _saving = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final isNew = _contractId == null;
      final resp = await Supabase.instance.client.functions.invoke(
        'manage-contract',
        method: isNew ? HttpMethod.post : HttpMethod.put,
        headers: {
          if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        },
        body: _toPayload(),
      );
      final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (body['error'] != null) throw Exception(body['error']);
      _applyData(body['contract'] as Map<String, dynamic>);
      setState(() => _editing = false);
      if (mounted) {
        AppSnackbar.success(
          context,
          isNew ? 'Contract created' : 'Contract saved',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _proprietorName,
      _tradingAs,
      _clientName,
      _commissionMin,
      _commissionMax,
      _ownDriverCommissionMin,
      _ownDriverCommissionMax,
      _introDays,
      _paymentHours,
      _terminationDays,
      _supportEmail,
      _supportPhone,
      _restaurantName,
      _authorizedPersonnel,
      _contractDate,
      _ceoName,
      _ceoDate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: const Text(
            'Partnership Agreement',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: AppLoadingIndicator(message: 'Loading contract…'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Partnership Agreement',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_editing) ...[
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save_rounded),
                tooltip: 'Save to database',
                onPressed: _save,
              ),
          ],
          IconButton(
            icon: Icon(_editing ? Icons.close_rounded : Icons.edit_rounded),
            tooltip: _editing ? 'Cancel editing' : 'Edit fields',
            onPressed: () {
              if (_editing) {
                _loadContracts();
              }
              setState(() => _editing = !_editing);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: _loadContracts,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Header ────────────────────────────────────────────────
            _sectionCard(
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
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
                _para(
                  'This Agreement for Services is made and entered into on the '
                  'date of signature between:\n\n',
                  spans: [
                    _editableSpan(_proprietorName, bold: true),
                    const TextSpan(text: ', trading as '),
                    _editableSpan(_tradingAs, bold: true),
                    const TextSpan(
                      text:
                          ' (hereafter referred to as "THE PROPRIETOR")\n'
                          'AND\n',
                    ),
                    _editableSpan(_clientName, bold: true),
                    const TextSpan(
                      text:
                          ' (hereafter referred to as "THE CLIENT")\n\n'
                          'Collectively referred to as "the Parties".',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 1. Purpose ────────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('1. PURPOSE OF AGREEMENT'),
                const SizedBox(height: 8),
                _bodyText(
                  'This Agreement outlines the terms under which THE CLIENT will '
                  'utilize THE PROPRIETOR\'s food delivery platform to receive, '
                  'prepare, and fulfill customer orders.\n\n'
                  'The objective of this partnership is to enable THE CLIENT to '
                  'increase profitability, retain customers, and grow sustainably '
                  'through a transparent and low-cost delivery model.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 2. Platform Access & Usage ─────────────────────────────
            _sectionCard(
              children: [
                _heading('2. PLATFORM ACCESS & USAGE'),
                const SizedBox(height: 8),
                _numberedText(
                  '2.1',
                  'THE PROPRIETOR is authorized to display THE CLIENT\'s '
                      'restaurant name, logo, menu, and related business information '
                      'on the platform.',
                ),
                _numberedText(
                  '2.2',
                  'THE CLIENT agrees to use the provided application to manage '
                      'menu items, pricing, availability, and operational status.',
                ),
                _numberedText(
                  '2.3',
                  'Initial onboarding, including menu setup and profile creation, '
                      'will be completed by THE PROPRIETOR at no cost.',
                ),
                _numberedText(
                  '2.4',
                  'THE CLIENT is responsible for ensuring all menu details and '
                      'pricing remain accurate and updated.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 3. Order Management ───────────────────────────────────
            _sectionCard(
              children: [
                _heading('3. ORDER MANAGEMENT'),
                const SizedBox(height: 8),
                _numberedText(
                  '3.1',
                  'Orders placed through the platform will be transmitted to '
                      'THE CLIENT in real time.',
                ),
                _numberedText(
                  '3.2',
                  'THE CLIENT agrees to confirm and begin preparation of orders '
                      'within a reasonable timeframe to ensure efficient delivery.',
                ),
                _numberedText(
                  '3.3',
                  'THE CLIENT agrees to prioritize delivery orders to maintain '
                      'service quality and customer satisfaction.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 4. Fees & Payment ─────────────────────────────────────
            _sectionCard(
              children: [
                _heading('4. FEES & PAYMENT TERMS'),
                const SizedBox(height: 8),
                _numberedItem(
                  '4.1',
                  spans: [
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
                    _editableSpan(_introDays, bold: true),
                    const TextSpan(text: ' days from activation.'),
                  ],
                ),
                _numberedItem(
                  '4.2',
                  spans: [
                    const TextSpan(
                      text: 'Standard Commission:\n',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: 'After the introductory period:\n• '),
                    _editableSpan(_commissionMin, bold: true),
                    const TextSpan(text: '%–'),
                    _editableSpan(_commissionMax, bold: true),
                    const TextSpan(text: '% per order (standard delivery)\n• '),
                    _editableSpan(_ownDriverCommissionMin, bold: true),
                    const TextSpan(text: '%–'),
                    _editableSpan(_ownDriverCommissionMax, bold: true),
                    const TextSpan(
                      text:
                          '% where THE CLIENT utilizes its own delivery drivers',
                    ),
                  ],
                ),
                _numberedText(
                  '4.3',
                  'THE PROPRIETOR shall not impose hidden fees, mandatory '
                      'promotions, or additional charges without prior agreement.',
                ),
                _numberedItem(
                  '4.4',
                  spans: [
                    const TextSpan(
                      text:
                          'Payments for completed orders will be transferred to '
                          'THE CLIENT within ',
                    ),
                    _editableSpan(_paymentHours, bold: true),
                    const TextSpan(text: ' hours.'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 5. Marketing ──────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('5. MARKETING & PROMOTION'),
                const SizedBox(height: 8),
                _numberedText(
                  '5.1',
                  'THE PROPRIETOR agrees to actively promote THE CLIENT\'s '
                      'restaurant within the platform at no additional cost.',
                ),
                _numberedText(
                  '5.2',
                  'Promotional support may include:\n'
                      '• Featured placement within the application\n'
                      '• "Restaurant of the Week" campaigns\n'
                      '• In-app visibility boosts',
                ),
                _numberedText(
                  '5.3',
                  'THE CLIENT may approve or decline any external promotional '
                      'materials.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 6. Customer Retention ─────────────────────────────────
            _sectionCard(
              children: [
                _heading('6. CUSTOMER RETENTION SYSTEM'),
                const SizedBox(height: 8),
                _numberedText(
                  '6.1',
                  'THE PROPRIETOR will provide a built-in loyalty system designed '
                      'to encourage repeat purchases for THE CLIENT.',
                ),
                _numberedText(
                  '6.2',
                  'Customers interacting with THE CLIENT through the platform '
                      'may receive rewards and incentives tied directly to THE '
                      'CLIENT\'s restaurant.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 7. Business Control ───────────────────────────────────
            _sectionCard(
              children: [
                _heading('7. BUSINESS CONTROL'),
                const SizedBox(height: 8),
                _numberedText(
                  '7.1',
                  'THE CLIENT retains full control over:\n'
                      '• Menu pricing\n'
                      '• Promotions and discounts\n'
                      '• Brand identity and presentation',
                ),
                _numberedText(
                  '7.2',
                  'THE PROPRIETOR shall not enforce pricing changes or '
                      'mandatory discounts.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 8. Technical Support ──────────────────────────────────
            _sectionCard(
              children: [
                _heading('8. TECHNICAL & OPERATIONAL SUPPORT'),
                const SizedBox(height: 8),
                _numberedText(
                  '8.1',
                  'THE PROPRIETOR will provide ongoing technical support for '
                      'the platform and order system.',
                ),
                _numberedText(
                  '8.2',
                  'THE CLIENT may contact support for order issues, menu '
                      'updates, or system assistance.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 9. Liability ──────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('9. LIABILITY & RESPONSIBILITY'),
                const SizedBox(height: 8),
                _numberedText(
                  '9.1',
                  'THE CLIENT is responsible for food quality, accuracy of '
                      'orders, and preparation standards.',
                ),
                _numberedText(
                  '9.2',
                  'THE PROPRIETOR is responsible for delivery operations and '
                      'customer communication related to delivery.',
                ),
                _numberedText(
                  '9.3',
                  'Each party agrees to operate in good faith to resolve any '
                      'service issues.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 10. Term & Termination ────────────────────────────────
            _sectionCard(
              children: [
                _heading('10. TERM & TERMINATION'),
                const SizedBox(height: 8),
                _numberedText(
                  '10.1',
                  'This Agreement shall take effect upon signature and '
                      'continue until terminated by either party.',
                ),
                _numberedItem(
                  '10.2',
                  spans: [
                    const TextSpan(
                      text: 'Either party may terminate this Agreement with ',
                    ),
                    _editableSpan(_terminationDays, bold: true),
                    const TextSpan(text: ' days written notice.'),
                  ],
                ),
                _numberedText(
                  '10.3',
                  'No long-term contractual obligation is required.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 11. Confidentiality ───────────────────────────────────
            _sectionCard(
              children: [
                _heading('11. CONFIDENTIALITY'),
                const SizedBox(height: 8),
                _numberedText(
                  '11.1',
                  'Both parties agree to keep confidential any proprietary or '
                      'business-sensitive information shared during this partnership.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 12. Dispute Resolution ────────────────────────────────
            _sectionCard(
              children: [
                _heading('12. DISPUTE RESOLUTION'),
                const SizedBox(height: 8),
                _numberedText(
                  '12.1',
                  'Any disputes arising under this Agreement shall first be '
                      'resolved through mutual discussion.',
                ),
                _numberedText(
                  '12.2',
                  'If unresolved, the matter may be referred to mediation or '
                      'legal proceedings in accordance with applicable laws.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 13. Acceptance / Signatures ───────────────────────────
            _sectionCard(
              children: [
                _heading('13. ACCEPTANCE'),
                const SizedBox(height: 8),
                _bodyText(
                  'By signing below, both parties acknowledge that they have '
                  'read, understood, and agreed to the terms outlined in this '
                  'Agreement.',
                ),
                const SizedBox(height: 16),
                // Client side
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
                      _fieldRow('Restaurant Name', _restaurantName),
                      _fieldRow(
                        'Authorized Representative',
                        _authorizedPersonnel,
                      ),
                      _fieldRow('Date', _contractDate),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Proprietor side
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
                      _fieldRow('Name', _ceoName),
                      _fieldRow(
                        'Date',
                        TextEditingController(text: _ceoDate.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Contact Info ──────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('CONTACT INFORMATION'),
                const SizedBox(height: 8),
                _fieldRow('Email', _supportEmail),
                _fieldRow('Phone', _supportPhone),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
        border: const Border(
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

  Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF334155),
        height: 1.5,
      ),
    );
  }

  Widget _numberedText(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              num,
              style: const TextStyle(
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

  Widget _numberedItem(String num, {required List<InlineSpan> spans}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              num,
              style: const TextStyle(
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

  InlineSpan _editableSpan(
    TextEditingController ctrl, {
    bool bold = false,
    String suffix = '',
  }) {
    if (!_editing) {
      return TextSpan(
        text: '${ctrl.text}$suffix',
        style: TextStyle(
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          color: AppTheme.primaryColor,
        ),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
          ),
        ),
        child: IntrinsicWidth(
          child: TextField(
            controller: ctrl,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              color: AppTheme.primaryColor,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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
            child: _editing
                ? TextField(
                    controller: ctrl,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      filled: true,
                      fillColor: AppTheme.primaryColor.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                : Text(
                    ctrl.text,
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

  Widget _para(String prefix, {List<InlineSpan>? spans}) {
    return RichText(
      text: TextSpan(
        text: prefix,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF334155),
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }
}
