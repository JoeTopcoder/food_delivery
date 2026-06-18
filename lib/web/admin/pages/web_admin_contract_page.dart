import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminContractPage extends ConsumerStatefulWidget {
  const WebAdminContractPage({super.key});

  @override
  ConsumerState<WebAdminContractPage> createState() => _WebAdminContractPageState();
}

class _WebAdminContractPageState extends ConsumerState<WebAdminContractPage> {
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _error;
  String? _contractId;

  late final TextEditingController _proprietorName = TextEditingController();
  late final TextEditingController _tradingAs = TextEditingController();
  late final TextEditingController _clientName = TextEditingController();
  late final TextEditingController _commissionMin = TextEditingController();
  late final TextEditingController _commissionMax = TextEditingController();
  late final TextEditingController _ownDriverCommissionMin = TextEditingController();
  late final TextEditingController _ownDriverCommissionMax = TextEditingController();
  late final TextEditingController _introDays = TextEditingController();
  late final TextEditingController _paymentHours = TextEditingController();
  late final TextEditingController _terminationDays = TextEditingController();
  late final TextEditingController _supportEmail = TextEditingController();
  late final TextEditingController _supportPhone = TextEditingController();
  late final TextEditingController _restaurantName = TextEditingController();
  late final TextEditingController _authorizedPersonnel = TextEditingController();
  late final TextEditingController _contractDate = TextEditingController();
  late final TextEditingController _ceoName = TextEditingController();
  late final TextEditingController _ceoDate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_proprietorName, _tradingAs, _clientName, _commissionMin, _commissionMax,
      _ownDriverCommissionMin, _ownDriverCommissionMax, _introDays, _paymentHours,
      _terminationDays, _supportEmail, _supportPhone, _restaurantName,
      _authorizedPersonnel, _contractDate, _ceoName, _ceoDate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final resp = await Supabase.instance.client.functions.invoke(
        'manage-contract',
        method: HttpMethod.get,
        headers: { if (session != null) 'Authorization': 'Bearer ${session.accessToken}' },
      );
      final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = (body['contracts'] as List?) ?? [];
      if (list.isNotEmpty) {
        _applyData(list.first as Map<String, dynamic>);
      } else {
        _applyDefaults();
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
      _applyDefaults();
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyData(Map<String, dynamic> d) {
    _contractId = d['id']?.toString();
    _proprietorName.text = d['proprietor_name'] ?? 'Joel Scott';
    _tradingAs.text = d['trading_as'] ?? '7Dash';
    _clientName.text = d['client_name'] ?? '';
    _commissionMin.text = d['commission_min']?.toString() ?? '15';
    _commissionMax.text = d['commission_max']?.toString() ?? '30';
    _ownDriverCommissionMin.text = d['own_driver_commission_min']?.toString() ?? '5';
    _ownDriverCommissionMax.text = d['own_driver_commission_max']?.toString() ?? '10';
    _introDays.text = d['intro_days']?.toString() ?? '30';
    _paymentHours.text = d['payment_hours']?.toString() ?? '48';
    _terminationDays.text = d['termination_days']?.toString() ?? '30';
    _supportEmail.text = d['support_email'] ?? '';
    _supportPhone.text = d['support_phone'] ?? '';
    _restaurantName.text = d['restaurant_name'] ?? '';
    _authorizedPersonnel.text = d['authorized_personnel'] ?? '';
    _contractDate.text = d['contract_date'] ?? '';
    _ceoName.text = d['ceo_name'] ?? 'Joel Scott';
    _ceoDate.text = d['ceo_date'] ?? '';
  }

  void _applyDefaults() {
    _proprietorName.text = 'Joel Scott';
    _tradingAs.text = '7Dash';
    _commissionMin.text = '15';
    _commissionMax.text = '30';
    _ownDriverCommissionMin.text = '5';
    _ownDriverCommissionMax.text = '10';
    _introDays.text = '30';
    _paymentHours.text = '48';
    _terminationDays.text = '30';
    _ceoName.text = 'Joel Scott';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final payload = {
        if (_contractId != null) 'id': _contractId,
        'proprietor_name': _proprietorName.text.trim(),
        'trading_as': _tradingAs.text.trim(),
        'client_name': _clientName.text.trim(),
        'commission_min': int.tryParse(_commissionMin.text.trim()) ?? 15,
        'commission_max': int.tryParse(_commissionMax.text.trim()) ?? 30,
        'own_driver_commission_min': int.tryParse(_ownDriverCommissionMin.text.trim()) ?? 5,
        'own_driver_commission_max': int.tryParse(_ownDriverCommissionMax.text.trim()) ?? 10,
        'intro_days': int.tryParse(_introDays.text.trim()) ?? 30,
        'payment_hours': int.tryParse(_paymentHours.text.trim()) ?? 48,
        'termination_days': int.tryParse(_terminationDays.text.trim()) ?? 30,
        'support_email': _supportEmail.text.trim(),
        'support_phone': _supportPhone.text.trim(),
        'restaurant_name': _restaurantName.text.trim(),
        'authorized_personnel': _authorizedPersonnel.text.trim(),
        'contract_date': _contractDate.text.trim(),
        'ceo_name': _ceoName.text.trim(),
        'ceo_date': _ceoDate.text.trim(),
      };
      await Supabase.instance.client.functions.invoke(
        'manage-contract',
        method: HttpMethod.post,
        headers: { if (session != null) 'Authorization': 'Bearer ${session.accessToken}' },
        body: payload,
      );
      if (mounted) {
        setState(() => _editing = false);
        AppSnackbar.success(context, 'Contract saved successfully');
        _load();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Restaurant Contract', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Partnership agreement template for restaurant onboarding', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            if (!_loading) ...[
              if (_editing) ...[
                TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                  label: const Text('Save', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: _saving ? null : _save,
                ),
              ] else
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                  label: const Text('Edit Contract', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => setState(() => _editing = true),
                ),
            ],
          ]),
          const SizedBox(height: 28),

          if (_loading)
            const SizedBox(height: 300, child: AppLoadingIndicator())
          else if (_error != null)
            AppErrorState(message: _error!, onRetry: _load)
          else ...[
            _section('Platform Details', [
              _row('Proprietor Name', _proprietorName),
              _row('Trading As', _tradingAs),
              _row('CEO Name', _ceoName),
              _row('CEO Date', _ceoDate),
            ]),
            const SizedBox(height: 16),
            _section('Restaurant Party', [
              _row('Restaurant Name', _restaurantName),
              _row('Client / Owner Name', _clientName),
              _row('Authorized Personnel', _authorizedPersonnel),
              _row('Contract Date', _contractDate),
            ]),
            const SizedBox(height: 16),
            _section('Commission Terms', [
              _row('Commission Min (%)', _commissionMin),
              _row('Commission Max (%)', _commissionMax),
              _row('Own-Driver Commission Min (%)', _ownDriverCommissionMin),
              _row('Own-Driver Commission Max (%)', _ownDriverCommissionMax),
            ]),
            const SizedBox(height: 16),
            _section('Agreement Terms', [
              _row('Intro Period (days)', _introDays),
              _row('Payment Window (hours)', _paymentHours),
              _row('Termination Notice (days)', _terminationDays),
              _row('Support Email', _supportEmail),
              _row('Support Phone', _supportPhone),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B))),
          ),
          const Divider(height: 1),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: _editing
          ? Row(children: [
              SizedBox(width: 240, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500))),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true, fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
                  ),
                ),
              ),
            ])
          : Row(children: [
              SizedBox(width: 240, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500))),
              Expanded(child: Text(ctrl.text.isEmpty ? '—' : ctrl.text, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w500))),
            ]),
    );
  }
}
