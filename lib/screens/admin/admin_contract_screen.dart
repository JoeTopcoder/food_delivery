import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';

/// Admin screen for viewing/editing the proprietor–client service agreement.
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
  String? _contractId; // null = new contract

  // ── Editable fields ─────────────────────────────────────────────────────
  late final TextEditingController _proprietorName;
  late final TextEditingController _tradingAs;
  late final TextEditingController _clientName;
  late final TextEditingController _feePercent;
  late final TextEditingController _feeCapPercent;
  late final TextEditingController _feeCapMonths;
  late final TextEditingController _supportEmail;
  late final TextEditingController _bankName;
  late final TextEditingController _accountNumber;
  late final TextEditingController _accountName;
  late final TextEditingController _branch;
  late final TextEditingController _accountType;
  late final TextEditingController _restaurantName;
  late final TextEditingController _authorizedPersonnel;
  late final TextEditingController _restaurantEmail;
  late final TextEditingController _contractDate;
  late final TextEditingController _ceoName;
  late final TextEditingController _ceoTitle;
  late final TextEditingController _ceoCompany;
  late final TextEditingController _ceoDate;
  late final TextEditingController _docRef;

  @override
  void initState() {
    super.initState();
    _proprietorName = TextEditingController();
    _tradingAs = TextEditingController();
    _clientName = TextEditingController();
    _feePercent = TextEditingController();
    _feeCapPercent = TextEditingController();
    _feeCapMonths = TextEditingController();
    _supportEmail = TextEditingController();
    _bankName = TextEditingController();
    _accountNumber = TextEditingController();
    _accountName = TextEditingController();
    _branch = TextEditingController();
    _accountType = TextEditingController();
    _restaurantName = TextEditingController();
    _authorizedPersonnel = TextEditingController();
    _restaurantEmail = TextEditingController();
    _contractDate = TextEditingController();
    _ceoName = TextEditingController();
    _ceoTitle = TextEditingController();
    _ceoCompany = TextEditingController();
    _ceoDate = TextEditingController();
    _docRef = TextEditingController();
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
    _proprietorName.text = d['proprietor_name'] ?? '';
    _tradingAs.text = d['trading_as'] ?? '';
    _clientName.text = d['client_name'] ?? '';
    _feePercent.text = (d['fee_percent'] ?? 10).toString();
    _feeCapPercent.text = (d['fee_cap_percent'] ?? 5).toString();
    _feeCapMonths.text = (d['fee_cap_months'] ?? 24).toString();
    _supportEmail.text = d['support_email'] ?? '';
    _bankName.text = d['bank_name'] ?? '';
    _accountNumber.text = d['account_number'] ?? '';
    _accountName.text = d['account_name'] ?? '';
    _branch.text = d['branch'] ?? '';
    _accountType.text = d['account_type'] ?? '';
    _restaurantName.text = d['restaurant_name'] ?? '';
    _authorizedPersonnel.text = d['authorized_personnel'] ?? '';
    _restaurantEmail.text = d['restaurant_email'] ?? '';
    _contractDate.text = d['contract_date'] ?? '';
    _ceoName.text = d['ceo_name'] ?? '';
    _ceoTitle.text = d['ceo_title'] ?? '';
    _ceoCompany.text = d['ceo_company'] ?? '';
    _ceoDate.text = d['ceo_date'] ?? '';
    _docRef.text = d['doc_ref'] ?? '';
  }

  void _applyDefaults() {
    _proprietorName.text = 'Innovative Menu Solutions Limited';
    _tradingAs.text = '7Krave';
    _clientName.text = '';
    _feePercent.text = '10';
    _feeCapPercent.text = '5';
    _feeCapMonths.text = '24';
    _supportEmail.text = 'support@7krave.com';
    _bankName.text = '';
    _accountNumber.text = '';
    _accountName.text = '';
    _branch.text = '';
    _accountType.text = 'Saving';
    _restaurantName.text = '';
    _authorizedPersonnel.text = '';
    _restaurantEmail.text = '';
    _contractDate.text = '';
    _ceoName.text = 'Mr. Rory White';
    _ceoTitle.text = 'Chief Executive Officer';
    _ceoCompany.text = 'Innovative Menu Solutions Ltd';
    _ceoDate.text = '';
    _docRef.text = '';
  }

  Map<String, dynamic> _toPayload() => {
    if (_contractId != null) 'id': _contractId,
    'proprietor_name': _proprietorName.text,
    'trading_as': _tradingAs.text,
    'client_name': _clientName.text,
    'fee_percent': double.tryParse(_feePercent.text) ?? 10,
    'fee_cap_percent': double.tryParse(_feeCapPercent.text) ?? 5,
    'fee_cap_months': int.tryParse(_feeCapMonths.text) ?? 24,
    'support_email': _supportEmail.text,
    'bank_name': _bankName.text,
    'account_number': _accountNumber.text,
    'account_name': _accountName.text,
    'branch': _branch.text,
    'account_type': _accountType.text,
    'restaurant_name': _restaurantName.text,
    'authorized_personnel': _authorizedPersonnel.text,
    'restaurant_email': _restaurantEmail.text,
    'contract_date': _contractDate.text.isEmpty ? null : _contractDate.text,
    'ceo_name': _ceoName.text,
    'ceo_title': _ceoTitle.text,
    'ceo_company': _ceoCompany.text,
    'ceo_date': _ceoDate.text.isEmpty ? null : _ceoDate.text,
    'doc_ref': _docRef.text,
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
      _feePercent,
      _feeCapPercent,
      _feeCapMonths,
      _supportEmail,
      _bankName,
      _accountNumber,
      _accountName,
      _branch,
      _accountType,
      _restaurantName,
      _authorizedPersonnel,
      _restaurantEmail,
      _contractDate,
      _ceoName,
      _ceoTitle,
      _ceoCompany,
      _ceoDate,
      _docRef,
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
            'Service Agreement',
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
          'Service Agreement',
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
                // Cancel: reload from DB
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
                      Icons.description_rounded,
                      size: 36,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'AGREEMENT BETWEEN\nPROPRIETOR AND CLIENT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _docRefLine(),
                const Divider(height: 24),
                _para(
                  'This is a contract for services and agreement in accordance '
                  'with the terms stated herein, and will take effect on the date '
                  'of signature between ',
                  spans: [
                    _editableSpan(_proprietorName, bold: true),
                    const TextSpan(text: ' trading as '),
                    _editableSpan(_tradingAs, bold: true),
                    const TextSpan(
                      text: ' (hereafter called The Proprietor) and ',
                    ),
                    _editableSpan(_clientName, bold: true),
                    const TextSpan(text: ' (hereafter called The Client).'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Terms & Conditions ────────────────────────────────────
            _sectionCard(
              children: [
                _heading('TERMS AND CONDITIONS'),
                const SizedBox(height: 8),
                _bullet(
                  'THE PROPRIETOR will have authorization to use THE CLIENT\'S '
                  'store logo and other store details to be displayed on the '
                  'delivery platform, ${_tradingAs.text}.',
                ),
                _bullet(
                  'THE CLIENT will be required to use the provided delivery '
                  'application to manage their restaurant\'s profile, including '
                  'updating the pricing of menu items. This will enable THE CLIENT '
                  'to keep all relevant information such as contact details and '
                  'menu details accurate and up-to-date on the ${_tradingAs.text} platform.',
                ),
                _bullet(
                  'The initial entry of the restaurant\'s profile and menu items '
                  'will be completed by THE PROPRIETOR at no cost.',
                ),
                _bullet(
                  'THE CLIENT should ensure that their menu is always up to date. '
                  'This can be updated from the delivery application or via '
                  'instructions sent with all menu changes to THE PROPRIETOR\'S '
                  'e-mail, ${_supportEmail.text}, at least 48 hours in advance of '
                  'when the change should be effective. Failure to abide by this '
                  'clause, THE PROPRIETOR will not be responsible to cover any '
                  'price differences.',
                ),
                _bullet(
                  'THE PROPRIETOR should be able to display promotional items at '
                  'THE CLIENT\'S restaurant. These items could include posters, '
                  'flyers, brochures etc., which will be subjected to THE CLIENT\'S '
                  'approval, to highlight the partnership.',
                ),
                _bullet(
                  'Orders received from ${_tradingAs.text} customers on the '
                  '${_tradingAs.text} app will be sent to THE CLIENT\'s restaurant '
                  'on the provided delivery application within a maximum time of '
                  'ten (10) minutes. THE CLIENT is then responsible to initiate '
                  'preparation of orders sent via the delivery app within 10 '
                  'minutes of receipt.',
                ),
                _bullet(
                  'Preference should be given to the agents of our Delivery '
                  'service (Delivery Personnel). The agent should not be treated '
                  'as a regular \'walk-in\' but more so as an express service. '
                  'This is to facilitate a quick delivery turnaround time and a '
                  'happy customer.',
                ),
                _bullet(
                  'Delivery Personnel will conduct themselves in a professional '
                  'manner. Only uniformed personnel should be given access to the '
                  'restaurant to conduct business on THE PROPRIETOR\'s behalf. '
                  'Only the approved and branded delivery bags should be used for '
                  'food collection. Delivery Personnel are not allowed to be rowdy, '
                  'including raising their voice or using defamatory words in the '
                  'restaurant whether in front of or to any customer or staff.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 1. FEES ───────────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('1. FEES'),
                const SizedBox(height: 8),
                _numberedItem(
                  '1.1',
                  spans: [
                    const TextSpan(
                      text:
                          'Any order from THE CLIENT\'S restaurant done through '
                          '${'' /* placeholder */} will be charged a ',
                    ),
                    _editableSpan(_feePercent, bold: true, suffix: '%'),
                    const TextSpan(
                      text:
                          ' fee. THE PROPRIETOR is not concerned with \'walk-in\' '
                          'transactions or any transactions done outside of the '
                          'platform. This fee charged to THE CLIENT is a charge on '
                          'the original menu item cost. The menu item cost is the '
                          'cost being charged to the customers.',
                    ),
                  ],
                ),
                _numberedText(
                  '1.2',
                  'The menu items\' cost to be displayed on the platform will '
                      'have a zero surcharge to THE CLIENT\'s original menu items\' '
                      'cost, unless stated otherwise in an APPENDIX.',
                ),
                _numberedText(
                  '1.3',
                  'For all meals prepared by THE CLIENT through the platform, '
                      'the transfer to THE CLIENT\'S bank account will be calculated '
                      'as ${100 - (int.tryParse(_feePercent.text) ?? 10)}% of the '
                      'original menu item cost plus any General Consumption Tax (GCT). '
                      'For example, if the cost of a meal is \$100 plus GCT, resulting '
                      'in a total of \$115, the transfer amount will be '
                      '${AppConstants.currencySymbol}${100 - (int.tryParse(_feePercent.text) ?? 10)} '
                      '(${100 - (int.tryParse(_feePercent.text) ?? 10)}% of \$100) '
                      'plus GCT, totaling \$${((100 - (int.tryParse(_feePercent.text) ?? 10)) * 1.15).toStringAsFixed(2)}. '
                      'These transfers will be made by THE PROPRIETOR to THE CLIENT\'S '
                      'bank account every Tuesday and Friday by 3:00 pm. Tuesday '
                      'transfers will cover outstanding orders not yet paid for up to '
                      'and including the Sunday before, and Friday transfers will cover '
                      'outstanding orders not yet paid for up to and including the '
                      'Wednesday before.',
                ),
                _numberedItem(
                  '1.4',
                  spans: [
                    const TextSpan(
                      text:
                          'The CLIENT agrees that any increase in the fee charged '
                          'by THE PROPRIETOR shall not exceed ',
                    ),
                    _editableSpan(_feeCapPercent, bold: true, suffix: '%'),
                    const TextSpan(text: ' over the next '),
                    _editableSpan(_feeCapMonths, bold: true, suffix: ' months'),
                    const TextSpan(
                      text:
                          ' from the date of this contract. In the event of an '
                          'economic recession or higher than normal inflation, both '
                          'parties shall negotiate in good faith to determine an '
                          'appropriate fee adjustment. Any fee increase notification '
                          'will be one (1) month in advance.',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 2-5: Marketing, Technical, Operational, Training ──────
            _sectionCard(
              children: [
                _heading('2. MARKETING SUPPORT'),
                const SizedBox(height: 4),
                _numberedText(
                  '2.1',
                  'THE PROPRIETOR will collaborate with THE CLIENT to create and '
                      'implement marketing campaigns and promotional materials to '
                      'increase visibility and awareness of THE CLIENT\'s restaurant '
                      'on the platform. This support may include social media '
                      'promotions, email marketing, and in-app promotions.',
                ),
                const SizedBox(height: 12),
                _heading('3. TECHNICAL SUPPORT'),
                const SizedBox(height: 4),
                _numberedText(
                  '3.1',
                  'THE PROPRIETOR will provide technical support to THE CLIENT, '
                      'assisting with any issues or concerns related to the platform '
                      'and the delivery application. Technical support will be '
                      'available during regular business hours and can be accessed '
                      'via email, ${_supportEmail.text} or via telephone.',
                ),
                const SizedBox(height: 12),
                _heading('4. OPERATIONAL SUPPORT'),
                const SizedBox(height: 4),
                _numberedText(
                  '4.1',
                  'The delivery application will be online for orders whenever '
                      'the restaurant is open. To transition to offline status, an '
                      'authorized individual must communicate with the support team '
                      'using the support button in the delivery application.',
                ),
                _numberedText(
                  '4.2',
                  'If an order is received through the delivery application and '
                      'the restaurant encounters any difficulties in processing it, '
                      'they can use the designated support button to contact THE '
                      'PROPRIETOR and report the issues, such as an item being '
                      '\'out of stock,\' or \'kitchen being unable to fulfill.\' '
                      'Should an item be out of stock, the restaurant is obliged to '
                      'deactivate that item on the delivery application for a '
                      'specified duration.',
                ),
                _numberedText(
                  '4.3',
                  'Delivery personnel are required to sign the receipt provided '
                      'by the restaurant at the time of pick-up. The management and '
                      'retention of this receipt documentation are the responsibility '
                      'of the restaurant.',
                ),
                const SizedBox(height: 12),
                _heading('5. TRAINING'),
                const SizedBox(height: 4),
                _numberedText(
                  '5.1',
                  'THE PROPRIETOR will provide training to THE CLIENT\'s team '
                      'members on the proper use of tablets, the delivery application, '
                      'and any other relevant technology. The training will cover order '
                      'management, menu updates, and any other necessary functions to '
                      'ensure a smooth operation of the partnership.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 6-7: Dispute & Confidentiality ────────────────────────
            _sectionCard(
              children: [
                _heading('6. DISPUTE RESOLUTION'),
                const SizedBox(height: 4),
                _numberedText(
                  '6.1',
                  'If any dispute arises between THE CLIENT and THE PROPRIETOR, '
                      'it will be settled by mediation whereby a neutral third party '
                      'will offer a solution to resolve the dispute. If mediation '
                      'proves unsuccessful, the parties reserve their legal rights to '
                      'seek the intervention in the Courts.',
                ),
                const SizedBox(height: 12),
                _heading('7. CONFIDENTIALITY'),
                const SizedBox(height: 4),
                _numberedText(
                  '7.1',
                  'THE CLIENT shall not disclose any such details mentioned '
                      'within this contract or documentation connected to it while '
                      'the contract is in effect.\n\n'
                      'All contractors or agents affiliated with both THE CLIENT and '
                      'THE PROPRIETOR must observe and comply with either party\'s '
                      'intellectual property. The affiliates shall not disclose any '
                      'of the details associated with the intellectual property to '
                      'any third party.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 8: Duration ───────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('8. DURATION'),
                const SizedBox(height: 4),
                _numberedText(
                  '8.1',
                  'The agreement shall come into force on the date of THE '
                      'CLIENT\'s signature and will continue indefinitely, or until '
                      'terminated by either party hereto.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 9: Indemnification ────────────────────────────────────
            _sectionCard(
              children: [
                _heading('9. INDEMNIFICATION'),
                const SizedBox(height: 4),
                _numberedText(
                  '9.1',
                  'Any order processed by THE CLIENT\'s restaurant that has been '
                      'collected by THE PROPRIETOR\'s delivery personnel, who in turn, '
                      'has left the restaurant and is en route to customer for '
                      'delivery, accidents that are meal related or otherwise are '
                      'fully borne by THE PROPRIETOR.',
                ),
                _numberedText(
                  '9.2',
                  'If customer receives meal from THE CLIENT\'s restaurant that '
                      'does not match the order on the receipt and/or the order '
                      'summary received on the delivery application that is used for '
                      'processing, then the responsibility is fully borne by THE '
                      'CLIENT, once proof of missed delivery of item has been '
                      'established.',
                ),
                _numberedText(
                  '9.3',
                  'THE PROPRIETOR shall be responsible for the payment of meals '
                      'once an order has been processed on the delivery application '
                      'and the preparation of the meal has commenced. If the '
                      'preparation of the meal has not begun, the order may be '
                      'cancelled, and neither party shall be held responsible for any '
                      'losses. However, if the preparation of the order has already '
                      'started, and the meals are not collected in a timely manner, or '
                      'if the order is cancelled by the customer, all responsibility '
                      'and any associated costs or losses will be borne solely by THE '
                      'PROPRIETOR.',
                ),
                _numberedText(
                  '9.4',
                  'In the event an order is not processed within the 10-minute '
                      'time frame of receipt, it shall not be automatically cancelled. '
                      'THE PROPRIETOR\'s support team shall contact the restaurant to '
                      'facilitate processing. Should the restaurant continue to fail '
                      'to process the order, our support team shall then contact the '
                      'customer, offering the option to either wait or cancel the '
                      'order. If the customer opts to cancel the order, THE PROPRIETOR '
                      'shall not be held responsible or liable for any issues, '
                      'damages, or claims that may arise if the restaurant decides to '
                      'process the order subsequent to the cancellation. THE CLIENT '
                      'hereby agrees to indemnify and hold harmless THE PROPRIETOR '
                      'from and against all liabilities, losses, damages, or expenses '
                      'resulting from or arising out of the restaurant\'s decision to '
                      'process the order after cancellation.',
                ),
                _numberedText(
                  '9.5',
                  'Any cancellation request by a customer because of a long delay '
                      'in processing the order by THE CLIENT, a time exceeding thirty '
                      'minutes after the order is sent to the restaurant delivery '
                      'application, the order will be automatically cancelled and THE '
                      'CLIENT will be responsible for any losses that may arise from '
                      'the preparation of the meals.',
                ),
                _numberedText(
                  '9.6',
                  'Any refunds or returns requested by the customer because of an '
                      'error on THE PROPRIETOR\'s behalf (e.g cold food or long wait '
                      'times due to delayed food pick-up or delivery), THE PROPRIETOR '
                      'will be responsible for any losses arising from the preparation '
                      'of the meals.',
                ),
                _numberedText(
                  '9.7',
                  'THE PROPRIETOR agrees to indemnify and protect THE CLIENT '
                      'against any actions or failures to act committed by THE '
                      'PROPRIETOR, its employees, agents, and other associates, '
                      'including but not limited to acts of fraud or errors.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 10: Termination ───────────────────────────────────────
            _sectionCard(
              children: [
                _heading('10. TERMINATION'),
                const SizedBox(height: 4),
                _numberedText(
                  '10.1',
                  'This contract shall remain in effect indefinitely until '
                      'either THE CLIENT or THE PROPRIETOR decides to terminate it. '
                      'Termination may occur immediately in the event of a breach of '
                      'this agreement. In all other cases, if either party chooses to '
                      'end the partnership, they must provide a two-week notice to the '
                      'other party. Upon termination, both parties must cease all use '
                      'of the other\'s intellectual property.',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Bank Details ──────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('BANK DETAILS'),
                const SizedBox(height: 8),
                _fieldRow('Name of Bank', _bankName),
                _fieldRow('Account Number', _accountNumber),
                _fieldRow('Name on Account', _accountName),
                _fieldRow('Branch', _branch),
                _fieldRow('Type of Account', _accountType),
              ],
            ),
            const SizedBox(height: 12),

            // ── Signatures ────────────────────────────────────────────
            _sectionCard(
              children: [
                _heading('SIGNATURES'),
                const SizedBox(height: 8),
                const Text(
                  'The undersigned agrees to the legally binding AGREEMENT and '
                  'fully understands the terms as outlined in said AGREEMENT.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      _fieldRow('Authorized Personnel', _authorizedPersonnel),
                      _fieldRow('Restaurant Email', _restaurantEmail),
                      _fieldRow('Date of Contract', _contractDate),
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
                      _fieldRow('Title', _ceoTitle),
                      _fieldRow('Company', _ceoCompany),
                      _fieldRow('Date', _ceoDate),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Footer ────────────────────────────────────────────────
            Center(
              child: Text(
                'Should you require any further information or have any queries '
                'regarding this contract, please contact us via telephone or '
                'via email at ${_supportEmail.text}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
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

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
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
    // In edit mode show inline chip
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
            width: 130,
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

  Widget _docRefLine() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: _editing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ref: ',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _docRef,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              )
            : Text(
                'Document Ref: ${_docRef.text}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
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
