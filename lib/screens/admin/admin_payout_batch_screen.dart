import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/supabase_config.dart';
import '../../config/app_constants.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Admin "billing run": lists every active restaurant/driver that is owed money
/// with their on-file bank details, exports it as CSV (openable in Excel) to pay
/// from the business bank account, and — when run — records a settling payout
/// for each and zeroes their balance so the next run only bills new earnings.
class AdminPayoutBatchScreen extends ConsumerStatefulWidget {
  const AdminPayoutBatchScreen({super.key});

  @override
  ConsumerState<AdminPayoutBatchScreen> createState() =>
      _AdminPayoutBatchScreenState();
}

class _AdminPayoutBatchScreenState
    extends ConsumerState<AdminPayoutBatchScreen> {
  List<Map<String, dynamic>> _preview = [];
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await SupabaseConfig.client.rpc('preview_payout_batch');
      _preview =
          (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  final String _sym = AppConstants.currencySymbol;

  double _sum(Iterable<Map<String, dynamic>> rows) => rows.fold(
      0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

  String _csv(List<Map<String, dynamic>> rows) {
    String esc(dynamic v) {
      final s = (v ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }

    final b = StringBuffer();
    b.writeln(
        'Type,Name,Account Holder,Bank,Branch,Account Number,Account Type,Amount');
    for (final r in rows) {
      b.writeln([
        esc(r['entity_type']),
        esc(r['entity_name']),
        esc(r['bank_account_holder']),
        esc(r['bank_name']),
        esc(r['bank_branch']),
        esc(r['bank_account_number']),
        esc(r['bank_account_type']),
        esc(((r['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)),
      ].join(','));
    }
    return b.toString();
  }

  Future<void> _share(List<Map<String, dynamic>> rows, String name) async {
    if (rows.isEmpty) {
      AppSnackbar.info(context, 'Nothing to export.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(':', '')
          .replaceAll('T', '_');
      final file = File('${dir.path}/$name-$stamp.csv');
      await file.writeAsString(_csv(rows));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'QuickDash Payout Run',
          text: 'QuickDash payout run — ${rows.length} payees, '
              'total $_sym${_sum(rows).toStringAsFixed(2)}',
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  bool _isPayable(Map<String, dynamic> r) =>
      r['has_bank'] == true && ((r['amount'] as num?)?.toDouble() ?? 0) > 0.005;

  Future<void> _runBatch() async {
    final payable = _preview.where(_isPayable).toList();
    if (payable.isEmpty) {
      AppSnackbar.info(context, 'No payees with bank details to bill.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run payout batch?'),
        content: Text(
          'This will record a settling payout for ${payable.length} payee(s) '
          'totalling $_sym${_sum(payable).toStringAsFixed(2)} and reset their '
          'balances to zero for the next run.\n\n'
          'Export the CSV and pay these amounts from your business account. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white),
            child: const Text('Run & Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _running = true);
    try {
      final res = await SupabaseConfig.client.rpc('create_payout_batch');
      final billed =
          (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
      await _share(billed, 'quickdash-payouts');
      if (mounted) {
        AppSnackbar.success(context,
            'Billed ${billed.length} payee(s). Balances reset for next run.');
      }
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _undoLast() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo last payout run?'),
        content: const Text(
          'This reverses the most recent payout run — restoring every payee\'s '
          'balance and float to before the run and deleting its records. '
          'Only do this if you did NOT actually send the bank payments.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _running = true);
    try {
      final res = await SupabaseConfig.client.rpc('reverse_payout_batch');
      final n = (res is Map ? res['reversed'] : null) ?? 0;
      if (mounted) {
        if ((n as num) > 0) {
          AppSnackbar.success(context, 'Last run reversed ($n payee(s)).');
        } else {
          AppSnackbar.info(context, 'No payout run to undo.');
        }
      }
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double amt(Map<String, dynamic> r) => (r['amount'] as num?)?.toDouble() ?? 0;
    final payable = _preview.where(_isPayable).toList();
    final missing = _preview
        .where((r) => amt(r) > 0.005 && r['has_bank'] != true)
        .toList();
    final drivers =
        _preview.where((r) => r['entity_type'] == 'driver').toList();
    final restaurants =
        _preview.where((r) => r['entity_type'] == 'restaurant').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payout Run'),
        actions: [
          IconButton(
            tooltip: 'Undo last run',
            onPressed: _running ? null : _undoLast,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summary(payable, missing),
                  const SizedBox(height: 16),
                  if (drivers.isNotEmpty) ...[
                    _sectionTitle('Drivers (${drivers.length})'),
                    ...drivers.map(_autoRow),
                    const SizedBox(height: 16),
                  ],
                  if (restaurants.isNotEmpty) ...[
                    _sectionTitle('Restaurants (${restaurants.length})'),
                    ...restaurants.map(_autoRow),
                    const SizedBox(height: 16),
                  ],
                  if (_preview.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No outstanding balances.')),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: payable.isEmpty
                            ? null
                            : () => _share(payable, 'quickdash-payouts-preview'),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Export CSV'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed:
                            _running || payable.isEmpty ? null : _runBatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.account_balance_rounded),
                        label: const Text('Run & Export'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _summary(
      List<Map<String, dynamic>> payable, List<Map<String, dynamic>> missing) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payable now',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            '$_sym${_sum(payable).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${payable.length} payee(s) with bank info'
            '${missing.isNotEmpty ? '  ·  ${missing.length} missing bank info' : ''}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  /// Picks the row style from the entity's amount + bank status.
  Widget _autoRow(Map<String, dynamic> r) {
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0.005) return _row(r, payable: false, owes: true);
    return _row(r, payable: r['has_bank'] == true);
  }

  Widget _row(Map<String, dynamic> r, {required bool payable, bool owes = false}) {
    final scheme = Theme.of(context).colorScheme;
    final isDriver = r['entity_type'] == 'driver';
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isDriver ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
            color: isDriver ? const Color(0xFF6366F1) : const Color(0xFF059669),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((r['entity_name'] ?? '—').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  owes
                      ? 'Balance applied to float — still owes $_sym${amount.abs().toStringAsFixed(2)}'
                      : payable
                          ? '${r['bank_name'] ?? ''} · ${r['bank_account_number'] ?? ''}'
                          : 'No bank account on file',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: payable ? scheme.onSurfaceVariant : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          Text(
            owes
                ? '−$_sym${amount.abs().toStringAsFixed(2)}'
                : '$_sym${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: owes ? const Color(0xFFEF4444) : null,
            ),
          ),
        ],
      ),
    );
  }
}
