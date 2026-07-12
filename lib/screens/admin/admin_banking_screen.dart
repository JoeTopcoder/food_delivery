import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/payout_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

/// Banking — a directory of every restaurant/driver's on-file bank details,
/// for admins to look up an account and originate a payout directly (rather
/// than waiting for the restaurant/driver to request one themselves from
/// their own app). Creating a payout here uses the exact same
/// requestRestaurantPayout/requestDriverPayout + payout_requests pipeline as
/// the self-service flow, so it shows up in Payout Management for the normal
/// approve → pay via Stripe / mark-as-paid steps — nothing new is invented,
/// this just gives admins a second, faster way in.
class AdminBankingScreen extends ConsumerStatefulWidget {
  const AdminBankingScreen({super.key});

  @override
  ConsumerState<AdminBankingScreen> createState() => _AdminBankingScreenState();
}

class _AdminBankingScreenState extends ConsumerState<AdminBankingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _restaurants = [];
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client
            .from(AppConstants.tableRestaurants)
            .select('id, name, status, owner_id, bank_name, bank_branch, bank_account_number, bank_account_holder, bank_account_type, bank_country_code')
            .order('name'),
        client
            .from(AppConstants.tableDrivers)
            .select('id, full_name, status, user_id, bank_name, bank_branch, bank_account_number, bank_account_holder, bank_account_type, bank_country_code, total_earnings, total_paid_out')
            .order('full_name'),
      ]);
      if (mounted) {
        setState(() {
          _restaurants = List<Map<String, dynamic>>.from(results[0]);
          _drivers = List<Map<String, dynamic>>.from(results[1]);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  bool _hasBankInfo(Map<String, dynamic> row) => (row['bank_account_number'] as String?)?.trim().isNotEmpty == true;

  List<Map<String, dynamic>> get _filteredRestaurants => _search.isEmpty
      ? _restaurants
      : _restaurants.where((r) => (r['name'] as String? ?? '').toLowerCase().contains(_search)).toList();

  List<Map<String, dynamic>> get _filteredDrivers => _search.isEmpty
      ? _drivers
      : _drivers.where((d) => (d['full_name'] as String? ?? '').toLowerCase().contains(_search)).toList();

  void _openDetail({required bool isDriver, required Map<String, dynamic> entity}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BankDetailSheet(isDriver: isDriver, entity: entity, onPayoutCreated: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          tabs: [
            Tab(text: 'Restaurants (${_restaurants.length})'),
            Tab(text: 'Drivers (${_drivers.length})'),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by name',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _EntityList(
                            entities: _filteredRestaurants,
                            nameKey: 'name',
                            hasBankInfo: _hasBankInfo,
                            onTap: (e) => _openDetail(isDriver: false, entity: e),
                          ),
                          _EntityList(
                            entities: _filteredDrivers,
                            nameKey: 'full_name',
                            hasBankInfo: _hasBankInfo,
                            onTap: (e) => _openDetail(isDriver: true, entity: e),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _EntityList extends StatelessWidget {
  final List<Map<String, dynamic>> entities;
  final String nameKey;
  final bool Function(Map<String, dynamic>) hasBankInfo;
  final void Function(Map<String, dynamic>) onTap;

  const _EntityList({required this.entities, required this.nameKey, required this.hasBankInfo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entities.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nothing found.', style: TextStyle(color: Colors.grey))));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entities.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final e = entities[i];
        final onFile = hasBankInfo(e);
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            onTap: () => onTap(e),
            title: Text(e[nameKey] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(e['status'] ?? '', style: const TextStyle(fontSize: 12)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: onFile ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                onFile ? 'Bank on file' : 'No bank info',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onFile ? const Color(0xFF16A34A) : Colors.grey[600]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BankDetailSheet extends ConsumerStatefulWidget {
  final bool isDriver;
  final Map<String, dynamic> entity;
  final VoidCallback onPayoutCreated;

  const _BankDetailSheet({required this.isDriver, required this.entity, required this.onPayoutCreated});

  @override
  ConsumerState<_BankDetailSheet> createState() => _BankDetailSheetState();
}

class _BankDetailSheetState extends ConsumerState<_BankDetailSheet> {
  bool _loadingBalance = true;
  double _availableBalance = 0;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      if (widget.isDriver) {
        final earnings = (widget.entity['total_earnings'] as num?)?.toDouble() ?? 0;
        final paidOut = (widget.entity['total_paid_out'] as num?)?.toDouble() ?? 0;
        _availableBalance = (earnings - paidOut).clamp(0, double.infinity);
      } else {
        _availableBalance = await ref.read(payoutServiceProvider).getRestaurantAvailableBalance(widget.entity['id'] as String);
      }
    } catch (_) {
      _availableBalance = 0;
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _createPayout() async {
    final bankName = widget.entity['bank_name'] as String? ?? '';
    final bankBranch = widget.entity['bank_branch'] as String? ?? '';
    final accountNumber = widget.entity['bank_account_number'] as String? ?? '';
    final accountHolder = widget.entity['bank_account_holder'] as String? ?? '';
    final accountType = widget.entity['bank_account_type'] as String? ?? '';
    final userId = widget.isDriver ? widget.entity['user_id'] as String? : widget.entity['owner_id'] as String?;

    if (accountNumber.isEmpty) {
      AppSnackbar.error(context, 'No bank account on file — cannot create a payout.');
      return;
    }
    if (userId == null) {
      AppSnackbar.error(context, 'No linked user account found for this ${widget.isDriver ? 'driver' : 'restaurant'}.');
      return;
    }

    final amountCtrl = TextEditingController(text: _availableBalance > 0 ? _availableBalance.toStringAsFixed(2) : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Payout Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To: $accountHolder ($bankName)', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${AppConstants.currencySymbol})',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This creates a pending payout request using the bank details on file — approve and pay it from Payout Management afterward.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackbar.error(context, 'Enter a valid amount.');
      return;
    }

    setState(() => _creating = true);
    try {
      final service = ref.read(payoutServiceProvider);
      if (widget.isDriver) {
        await service.requestDriverPayout(
          userId: userId,
          driverId: widget.entity['id'] as String,
          amount: amount,
          bankName: bankName,
          bankBranch: bankBranch,
          accountNumber: accountNumber,
          accountHolder: accountHolder,
          accountType: accountType,
        );
      } else {
        await service.requestRestaurantPayout(
          userId: userId,
          restaurantId: widget.entity['id'] as String,
          amount: amount,
          bankName: bankName,
          bankBranch: bankBranch,
          accountNumber: accountNumber,
          accountHolder: accountHolder,
          accountType: accountType,
        );
      }
      widget.onPayoutCreated();
      if (mounted) {
        AppSnackbar.success(context, 'Payout request created — approve it in Payout Management.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _row(String label, String? value) {
    final display = (value == null || value.trim().isEmpty) ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500))),
          Expanded(child: SelectableText(display, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entity;
    final name = widget.isDriver ? (e['full_name'] ?? 'Unnamed') : (e['name'] ?? 'Unnamed');
    final fmt = NumberFormat.currency(symbol: '${AppConstants.currencySymbol} ', decimalDigits: 2);
    final hasBankInfo = (e['bank_account_number'] as String?)?.trim().isNotEmpty == true;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(e['status'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            if (!hasBankInfo)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                child: const Text('No bank details on file yet.', style: TextStyle(fontSize: 13, color: Color(0xFFB45309))),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Bank', e['bank_name']),
                    _row('Branch', e['bank_branch']),
                    _row('Account Holder', e['bank_account_holder']),
                    _row('Account Number', e['bank_account_number']),
                    _row('Account Type', e['bank_account_type']),
                    _row('Country', e['bank_country_code']),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded, size: 16, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 6),
                Text(
                  _loadingBalance ? 'Loading balance…' : 'Available balance: ${fmt.format(_availableBalance)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0EA5E9)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (!hasBankInfo || _creating) ? null : _createPayout,
                icon: _creating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_creating ? 'Creating…' : 'Create Payout Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
