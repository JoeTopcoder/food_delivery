import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../models/earning_model.dart';
import '../../../providers/earning_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminEarningsPage extends ConsumerStatefulWidget {
  const WebAdminEarningsPage({super.key});

  @override
  ConsumerState<WebAdminEarningsPage> createState() => _WebAdminEarningsPageState();
}

class _WebAdminEarningsPageState extends ConsumerState<WebAdminEarningsPage> {
  String _search = '';
  String _tierFilter = 'all';

  static const _tierFilters = [
    ('all', 'All Tiers'),
    ('customer', 'Customer'),
    ('builder', 'Builder'),
    ('leader', 'Leader'),
  ];

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(allEarningAccountsProvider);
    final sym = AppConstants.currencySymbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Earnings & Credits', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Referral earning accounts and credit balances', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () => ref.invalidate(allEarningAccountsProvider),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Tier Config summary card ───────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primaryColor, const Color(0xFFFF8C5A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Expanded(child: _StatPill(label: 'Direct Ref Rate', value: '${(EarningConfig.directOrderRate * 100).toStringAsFixed(0)}¢/order')),
              const SizedBox(width: 12),
              Expanded(child: _StatPill(label: 'Builder at', value: '${EarningConfig.builderMinRefs} refs')),
              const SizedBox(width: 12),
              Expanded(child: _StatPill(label: 'Leader at', value: '${EarningConfig.leaderMinRefs} refs')),
              const SizedBox(width: 12),
              Expanded(child: _StatPill(label: 'Monthly Cap', value: '$sym${EarningConfig.monthlyCap.toStringAsFixed(0)}')),
            ]),
          ),

          // ── Filters ────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search by name…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _tierFilters.map((f) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: _tierFilter == f.$1,
                onSelected: (_) => setState(() => _tierFilter = f.$1),
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: _tierFilter == f.$1 ? AppTheme.primaryColor : const Color(0xFF64748B)),
              ),
            )).toList()),
          ),
          const SizedBox(height: 16),

          // ── Table ──────────────────────────────────────────────────────
          accountsAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allEarningAccountsProvider)),
            data: (all) {
              var list = all;
              if (_tierFilter != 'all') list = list.where((a) => a.tier == _tierFilter).toList();
              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                list = list.where((a) => (a.userName ?? '').toLowerCase().contains(q) || a.userId.contains(q)).toList();
              }

              if (list.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.monetization_on_rounded, title: 'No earning accounts found'),
                );
              }

              // Summary row
              final totalPaid = list.fold<double>(0, (s, a) => s + a.totalEarned);
              final leaders = list.where((a) => a.tier == 'leader').length;
              final builders = list.where((a) => a.tier == 'builder').length;

              return Column(children: [
                Row(children: [
                  _KpiTile(label: 'Accounts', value: '${list.length}', color: const Color(0xFF6366F1)),
                  const SizedBox(width: 16),
                  _KpiTile(label: 'Leaders', value: '$leaders', color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 16),
                  _KpiTile(label: 'Builders', value: '$builders', color: const Color(0xFF10B981)),
                  const SizedBox(width: 16),
                  _KpiTile(label: 'Total Paid Out', value: '$sym${totalPaid.toStringAsFixed(2)}', color: AppTheme.primaryColor),
                ]),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                      child: const Row(children: [
                        Expanded(flex: 3, child: Text('User', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Tier', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Total Earned', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('This Month', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Refs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Orders Gen.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        SizedBox(width: 60),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...list.asMap().entries.map((e) => _AccountRow(
                      account: e.value,
                      isLast: e.key == list.length - 1,
                      sym: sym,
                      onChanged: () => ref.invalidate(allEarningAccountsProvider),
                    )),
                  ]),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  ]);
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ]),
    ),
  );
}

// ── Account Row ───────────────────────────────────────────────────────────────

class _AccountRow extends ConsumerWidget {
  final EarningAccount account;
  final bool isLast;
  final String sym;
  final VoidCallback onChanged;
  const _AccountRow({required this.account, required this.isLast, required this.sym, required this.onChanged});

  static const _tierColors = <String, (Color, Color)>{
    'customer': (Color(0xFF6366F1), Color(0xFFEEF2FF)),
    'builder':  (Color(0xFF10B981), Color(0xFFECFDF5)),
    'leader':   (Color(0xFFF59E0B), Color(0xFFFFFBEB)),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (fg, bg) = _tierColors[account.tier] ?? (const Color(0xFF94A3B8), const Color(0xFFF1F5F9));
    return Container(
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(children: [
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.userName ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
            Text('${account.userId.substring(0, 8)}…', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          ])),
          Expanded(flex: 1, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(account.tierDisplayName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          )),
          Expanded(flex: 2, child: Text('$sym${account.totalEarned.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)))),
          Expanded(flex: 2, child: Text('$sym${account.monthlyEarned.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
          Expanded(flex: 1, child: Text('${account.totalDirectRefs}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
          Expanded(flex: 2, child: Text('${account.totalOrdersGenerated}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
          SizedBox(width: 60, child: IconButton(
            icon: const Icon(Icons.add_card_rounded, size: 17, color: Color(0xFF6366F1)),
            tooltip: 'Adjust Credits',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _AdjustDialog(account: account, onSaved: onChanged),
            ),
          )),
        ]),
      ),
    );
  }
}

// ── Credit Adjustment Dialog ──────────────────────────────────────────────────

class _AdjustDialog extends ConsumerStatefulWidget {
  final EarningAccount account;
  final VoidCallback onSaved;
  const _AdjustDialog({required this.account, required this.onSaved});

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount == 0) {
      AppSnackbar.error(context, 'Enter a valid amount (positive = credit, negative = debit)');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      AppSnackbar.error(context, 'Please enter a description');
      return;
    }
    setState(() => _saving = true);
    try {
      final service = ref.read(earningServiceProvider);
      await service.adminAdjustCredit(userId: widget.account.userId, amount: amount, description: desc);
      widget.onSaved();
      if (mounted) {
        AppSnackbar.success(context, 'Credit adjusted successfully');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Adjust Credits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text('For: ${widget.account.userName ?? widget.account.userId}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount ($sym) — negative to debit',
                labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.attach_money_rounded, size: 18),
                filled: true, fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Reason / Description',
                labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                filled: true, fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Apply Adjustment'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
