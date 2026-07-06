import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

// ---------------------------------------------------------------------------
// Simple customer model for the picker
// ---------------------------------------------------------------------------
class _Customer {
  final String id;
  final String name;
  final String email;
  _Customer({required this.id, required this.name, required this.email});
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AdminEmailNotificationsScreen extends ConsumerStatefulWidget {
  const AdminEmailNotificationsScreen({super.key});

  @override
  ConsumerState<AdminEmailNotificationsScreen> createState() =>
      _AdminEmailNotificationsScreenState();
}

class _AdminEmailNotificationsScreenState
    extends ConsumerState<AdminEmailNotificationsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  // 'all' | 'active' | 'inactive' | 'specific'
  String _target = 'all';

  bool _sending = false;

  // Specific-customer picker
  List<_Customer> _allCustomers = [];
  List<_Customer> _filtered = [];
  final Set<String> _selectedIds = {};
  bool _loadingCustomers = false;
  bool _customersLoaded = false;

  // Last send result
  Map<String, dynamic>? _lastResult;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    _promoCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    if (_customersLoaded) return;
    setState(() => _loadingCustomers = true);
    try {
      final res = await SupabaseConfig.client
          .from('users')
          .select('id, name, email')
          .eq('role', 'user')
          .order('name');
      final list = (res as List).map((r) {
        final m = r as Map<String, dynamic>;
        return _Customer(
          id: m['id'] as String,
          name: (m['name'] as String?) ?? 'Unknown',
          email: (m['email'] as String?) ?? '',
        );
      }).where((c) => c.email.isNotEmpty).toList();
      setState(() {
        _allCustomers = list;
        _filtered = list;
        _customersLoaded = true;
      });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Failed to load customers');
    } finally {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  void _filterCustomers(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filtered = _allCustomers
          .where((c) =>
              c.name.toLowerCase().contains(lower) ||
              c.email.toLowerCase().contains(lower))
          .toList();
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_target == 'specific' && _selectedIds.isEmpty) {
      AppSnackbar.error(context, 'Select at least one customer.');
      return;
    }

    setState(() {
      _sending = true;
      _lastResult = null;
    });

    try {
      final body = <String, dynamic>{
        'title': _subjectCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'subject': _subjectCtrl.text.trim(),
        'send_push': false,
        'send_email': true,
        'target': _target == 'specific' ? 'user_ids' : _target,
        if (_target == 'specific')
          'user_ids': _selectedIds.toList(),
        if (_promoCtrl.text.trim().isNotEmpty)
          'promo_code': _promoCtrl.text.trim(),
      };

      final resp = await SupabaseConfig.client.functions.invoke(
        'admin-broadcast',
        body: body,
      );

      final data = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error']);

      setState(() => _lastResult = data);
      if (mounted) {
        AppSnackbar.success(
          context,
          'Sent to ${data['email_sent'] ?? 0} of ${data['recipients'] ?? 0} customers',
        );
      }
    } on FunctionException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Email Notifications'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              icon: Icons.people_rounded,
              title: 'Recipients',
              child: _buildRecipientSelector(),
            ),
            const SizedBox(height: 12),
            if (_target == 'specific') ...[
              _buildCustomerPicker(),
              const SizedBox(height: 12),
            ],
            _buildSection(
              icon: Icons.email_rounded,
              title: 'Email Content',
              child: _buildEmailFields(),
            ),
            const SizedBox(height: 24),
            _buildSendButton(),
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(_lastResult!),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildRecipientSelector() {
    final options = <String, String>{
      'all': 'All Customers',
      'active': 'Active (ordered in last 30 days)',
      'inactive': 'Inactive (no order in 30+ days)',
      'specific': 'Select Specific Customers',
    };
    final icons = <String, IconData>{
      'all': Icons.groups_rounded,
      'active': Icons.trending_up_rounded,
      'inactive': Icons.person_off_rounded,
      'specific': Icons.checklist_rounded,
    };
    return Column(
      children: options.entries.map((e) {
        final isSelected = _target == e.key;
        return GestureDetector(
          onTap: () {
            setState(() => _target = e.key);
            if (e.key == 'specific') _loadCustomers();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.07)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icons[e.key]!,
                  size: 20,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.grey[400]!,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomerPicker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_search_rounded,
                  size: 18, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Choose Customers',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (_selectedIds.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Search bar
          TextField(
            controller: _searchCtrl,
            onChanged: _filterCustomers,
            decoration: InputDecoration(
              hintText: 'Search by name or email...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingCustomers)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AppLoadingIndicator(color: AppTheme.primaryColor),
              ),
            )
          else if (_filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: Text('No customers found',
                      style: TextStyle(color: Color(0xFF94A3B8)))),
            )
          else
            // Customer list — capped height with scroll
            SizedBox(
              height: 260,
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final c = _filtered[i];
                  final selected = _selectedIds.contains(c.id);
                  return InkWell(
                    onTap: () => setState(() {
                      selected
                          ? _selectedIds.remove(c.id)
                          : _selectedIds.add(c.id);
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primaryColor
                                    : Colors.grey[400]!,
                                width: 1.5,
                              ),
                              color: selected
                                  ? AppTheme.primaryColor
                                  : Colors.transparent,
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  c.email,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_allCustomers.isNotEmpty) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedIds.addAll(_filtered.map((c) => c.id));
                  }),
                  child: Text('Select all',
                      style: TextStyle(color: AppTheme.primaryColor)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _selectedIds.clear()),
                  child: const Text('Clear',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailFields() {
    return Column(
      children: [
        TextFormField(
          controller: _subjectCtrl,
          decoration: _inputDeco(
            label: 'Subject line',
            hint: 'e.g. 20% off your next order!',
            icon: Icons.title_rounded,
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _messageCtrl,
          maxLines: 5,
          decoration: _inputDeco(
            label: 'Message body',
            hint:
                'Write your message here. It will appear in the email body...',
            icon: Icons.message_rounded,
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Message is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _promoCtrl,
          decoration: _inputDeco(
            label: 'Promo code (optional)',
            hint: 'e.g. SUMMER20',
            icon: Icons.local_offer_rounded,
          ),
          textCapitalization: TextCapitalization.characters,
        ),
      ],
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  Widget _buildSendButton() {
    final recipientLabel = switch (_target) {
      'all' => 'All Customers',
      'active' => 'Active Customers',
      'inactive' => 'Inactive Customers',
      'specific' =>
        '${_selectedIds.length} Customer${_selectedIds.length == 1 ? '' : 's'}',
      _ => 'Customers',
    };

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(
          _sending ? 'Sending...' : 'Send Email to $recipientLabel',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final recipients = result['recipients'] ?? 0;
    final emailSent = result['email_sent'] ?? 0;
    final withEmail = result['profiles_with_email'] ?? emailSent;
    final errors = (result['errors'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Emails Sent',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF166534)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _resultRow('Total recipients targeted', '$recipients'),
          _resultRow('With email address', '$withEmail'),
          _resultRow('Successfully sent', '$emailSent',
              highlight: true),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Errors: ${errors.join(', ')}',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF166534))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  highlight ? FontWeight.w800 : FontWeight.w500,
              color: highlight
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF166534),
            ),
          ),
        ],
      ),
    );
  }
}
