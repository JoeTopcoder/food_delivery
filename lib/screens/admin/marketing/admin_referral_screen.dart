import '../../../utils/est_datetime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_constants.dart';
import '../../../services/referral/member_referral_service.dart';

/// Admin console for HotBite Member Referral Rewards — programme totals,
/// referral economics (payouts vs paying-member revenue), enable/pause, and
/// prospective policy edits. Redesigned to the Overview / Activity / Policy layout.
class AdminReferralScreen extends ConsumerStatefulWidget {
  const AdminReferralScreen({super.key});
  @override
  ConsumerState<AdminReferralScreen> createState() => _AdminReferralScreenState();
}

class _AdminReferralScreenState extends ConsumerState<AdminReferralScreen> {
  final _client = Supabase.instance.client;
  late final MemberReferralService _svc = MemberReferralService(_client);
  DateTimeRange _range = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  int _tab = 0;
  late Future<_AdminData> _future = _load();

  static const _orange = Color(0xFFFF5A1F);
  final _num = NumberFormat('#,##0.00');

  Future<_AdminData> _load() async {
    final from = _range.start.toUtc().toIso8601String();
    final to = _range.end.add(const Duration(days: 1)).toUtc().toIso8601String();
    final overview = await _svc.adminOverview(_range.start, _range.end.add(const Duration(days: 1)));
    final polRes = await _client.rpc('referral_policy_current_json');
    final policy = (polRes is Map) ? Map<String, dynamic>.from(polRes) : <String, dynamic>{};
    final econRes = await _client.rpc('admin_referral_economics', params: {'p_from': from, 'p_to': to});
    final econ = (econRes is Map) ? Map<String, dynamic>.from(econRes) : <String, dynamic>{};
    return _AdminData(overview: overview, policy: policy, econ: econ);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  String _money(dynamic cents) {
    final c = (cents is num) ? cents.toInt() : int.tryParse('${cents ?? 0}') ?? 0;
    return '${AppConstants.currencySymbol}${_num.format(c / 100)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('Referral Rewards', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: _orange.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: _orange), label: 'Overview'),
            NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt_rounded, color: _orange), label: 'Activity'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded, color: _orange), label: 'Policy'),
          ],
        ),
      ),
      body: FutureBuilder<_AdminData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center)));
          }
          final d = snap.data!;
          return IndexedStack(index: _tab, children: [_overview(d), _activity(d), _policyTab(d)]);
        },
      ),
    );
  }

  // ── OVERVIEW ──────────────────────────────────────────────────────────────
  Widget _overview(_AdminData d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _dateBanner(),
        const SizedBox(height: 12),
        _programmeCard(d.policy),
        const SizedBox(height: 12),
        _economicsCard(d.econ),
        const SizedBox(height: 12),
        _statGrid(d.overview),
        const SizedBox(height: 12),
        _policyMiniCard(d.policy),
      ],
    );
  }

  Widget _dateBanner() {
    final label = '${DateFormat('MMM d, yyyy').format(toJamaicaOf(_range.start))} – ${DateFormat('MMM d, yyyy').format(toJamaicaOf(_range.end))}';
    return Material(
      color: const Color(0xFFFFF1EA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDateRangePicker(
            context: context, firstDate: DateTime(2025),
            lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: _range);
          if (picked != null) { setState(() => _range = picked); _reload(); }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, color: _orange, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
            const Text('Change', style: TextStyle(color: _orange, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _programmeCard(Map<String, dynamic> p) {
    final active = p['enabled'] == true;
    return _card(child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: (active ? Colors.green : Colors.orange).withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(active ? Icons.check_rounded : Icons.pause_rounded, color: active ? Colors.green : Colors.orange),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Programme is ${active ? "ACTIVE" : "PAUSED"}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Text(active ? 'New qualifying orders earn referral rewards.' : 'No new rewards are being created.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      ])),
      OutlinedButton(
        onPressed: () => _togglePaused(p, !active),
        style: OutlinedButton.styleFrom(
          foregroundColor: _orange, side: const BorderSide(color: _orange),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(active ? 'Pause' : 'Resume'),
      ),
    ]));
  }

  Widget _economicsCard(Map<String, dynamic> e) {
    final verdict = (e['verdict'] as String?) ?? 'healthy';
    final losing = verdict == 'alert_losing';
    final watch = verdict == 'watch';
    final vColor = losing ? Colors.red.shade600 : (watch ? Colors.orange.shade700 : Colors.green.shade600);
    final vLabel = losing ? 'Losing' : (watch ? 'Watch' : 'Healthy');
    final pct = (e['payout_to_revenue_pct'] as num?)?.toDouble() ?? 0;
    final threshold = (e['alert_threshold_pct'] as num?)?.toDouble() ?? 60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: losing ? const Color(0xFFFDECEC) : (watch ? const Color(0xFFFFF3E6) : const Color(0xFFEAF7EE)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart_rounded, color: vColor, size: 20),
          const SizedBox(width: 8),
          Expanded(child: RichText(text: TextSpan(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87), children: [
            const TextSpan(text: 'Referral economics · '),
            TextSpan(text: vLabel, style: TextStyle(color: vColor)),
          ]))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: vColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: vColor, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${losing || watch ? "Over" : "Below"} ${threshold.toStringAsFixed(0)}% alert',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: vColor)),
            ]),
          ),
        ]),
        const SizedBox(height: 2),
        Text('Referral wallet payouts vs paying-member revenue', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 14),
        Row(children: [
          Text('Revenue less referral payouts', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          const SizedBox(width: 5),
          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
        ]),
        const SizedBox(height: 2),
        Text(_money(e['net_contribution_cents']),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black87)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _econCol('Membership revenue', _money(e['membership_revenue_cents']), null),
          _econDivider(),
          _econCol('Referral payouts (paid)', _money(e['referral_paid_to_wallet_cents']), null),
          _econDivider(),
          _econCol('Payout ratio', '${pct.toStringAsFixed(1)}%', 'of membership revenue'),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (pct / (threshold == 0 ? 60 : threshold)).clamp(0.0, 1.0),
            minHeight: 8, backgroundColor: Colors.black.withValues(alpha: 0.06), color: vColor),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          GestureDetector(
            onTap: () => _editThreshold(threshold),
            child: Text('${threshold.toStringAsFixed(0)}% alert threshold',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.groups_rounded, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('${e['paying_members'] ?? 0} paying members',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
        ]),
      ]),
    );
  }

  Widget _econCol(String label, String value, String? sub) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ]),
      );
  Widget _econDivider() => Container(width: 1, height: 34, color: Colors.black.withValues(alpha: 0.08), margin: const EdgeInsets.symmetric(horizontal: 10));

  Widget _statGrid(Map<String, dynamic> o) {
    final cards = [
      _statCard('Tier 1 orders', '${o['tier1_orders'] ?? 0}', Icons.receipt_long_rounded, const Color(0xFF3B82F6)),
      _statCard('Tier 2 orders', '${o['tier2_orders'] ?? 0}', Icons.description_rounded, const Color(0xFF22C55E)),
      _statCard('Earning accounts', '${o['earning_accounts'] ?? 0}', Icons.groups_rounded, const Color(0xFF8B5CF6)),
      _statCard('Pending', _money(o['pending_cents']), Icons.schedule_rounded, const Color(0xFFF59E0B)),
      _statCard('Tier 1 cost', _money(o['tier1_cents']), Icons.payments_rounded, const Color(0xFF3B82F6)),
      _statCard('Tier 2 cost', _money(o['tier2_cents']), Icons.payments_rounded, const Color(0xFF3B82F6)),
      _statCard('Total referral cost', _money(o['total_referral_cost_cents']), Icons.summarize_rounded, _orange),
      _statCard('Expired', _money(o['expired_cents']), Icons.timer_off_rounded, Colors.grey),
      _statCard('Reversed', _money(o['reversed_cents']), Icons.undo_rounded, Colors.red),
    ];
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5, mainAxisSpacing: 12, crossAxisSpacing: 12, children: cards);
  }

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 19, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ])),
        ]),
      );

  Widget _policyMiniCard(Map<String, dynamic> p) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(color: _orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.verified_rounded, color: _orange, size: 19)),
        const SizedBox(width: 10),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reward policy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text('View and edit your referral rewards policy.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ])),
        GestureDetector(
          onTap: () => _editPolicy(p),
          child: const Row(children: [
            Text('View and edit policy', style: TextStyle(color: _orange, fontWeight: FontWeight.w700, fontSize: 12.5)),
            Icon(Icons.chevron_right, color: _orange, size: 18),
          ]),
        ),
      ]),
      const Divider(height: 22),
      Row(children: [
        _policyStat(Icons.people_alt_rounded, _money(p['direct_reward_cents']), 'Direct (Tier 1)'),
        _policyStat(Icons.card_giftcard_rounded, _money(p['second_tier_reward_cents']), 'Tiers 2–5 each'),
        _policyStat(Icons.lock_outline_rounded, '${p['personal_orders_required'] ?? 3} orders', 'To unlock'),
      ]),
    ]));
  }

  Widget _policyStat(IconData icon, String value, String label) => Expanded(
        child: Column(children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        ]),
      );

  // ── ACTIVITY ──────────────────────────────────────────────────────────────
  Widget _activity(_AdminData d) {
    final top = (d.econ['top_earners'] as List?) ?? const [];
    final o = d.overview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Reward breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _card(child: Column(children: [
          _actRow('Pending', _money(o['pending_cents']), Colors.orange),
          const Divider(height: 16),
          _actRow('Credited to wallets', _money(o['credited_cents']), Colors.green),
          const Divider(height: 16),
          _actRow('Expired', _money(o['expired_cents']), Colors.grey),
          const Divider(height: 16),
          _actRow('Reversed', _money(o['reversed_cents']), Colors.red),
        ])),
        const SizedBox(height: 18),
        const Text('Top earners (fraud watch)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (top.isEmpty)
          _card(child: const Text('No earners in this period.'))
        else
          ...top.map((t) => Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: _orange.withValues(alpha: 0.12),
                  child: Text('${t['orders'] ?? 0}', style: const TextStyle(color: _orange, fontWeight: FontWeight.bold, fontSize: 13))),
              title: Text('${t['earner'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${t['orders'] ?? 0} qualifying orders'),
              trailing: Text(_money(t['cents']), style: const TextStyle(fontWeight: FontWeight.w800, color: _orange)),
            ),
          )),
      ],
    );
  }

  Widget _actRow(String label, String value, Color c) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]);

  // ── POLICY ────────────────────────────────────────────────────────────────
  Widget _policyTab(_AdminData d) {
    final p = d.policy;
    final e = d.econ;
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontSize: 13.5)),
          Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ]));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _programmeCard(p),
        const SizedBox(height: 12),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Reward policy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            TextButton.icon(onPressed: () => _editPolicy(p), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
          ]),
          row('Direct reward (Tier 1)', _money(p['direct_reward_cents'])),
          row('Tiers 2–5 reward (each)', _money(p['second_tier_reward_cents'])),
          row('Earning tiers', '${p['max_tiers'] ?? 5}'),
          row('Min order value', _money(p['min_order_value_cents'])),
          row('Settlement delay', '${p['settlement_delay_hours'] ?? 0} h'),
          row('Carry-forward', '${p['carry_forward_days'] ?? 0} days'),
          row('Monthly cap', _money(p['monthly_cap_cents'])),
          row('Personal orders to unlock', '${p['personal_orders_required'] ?? 3}'),
          const SizedBox(height: 6),
          Text('Edits create a new version applied to FUTURE orders only.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ])),
        const SizedBox(height: 12),
        _card(child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Guardian alert threshold', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('WATCH when payouts pass this % of membership revenue.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          OutlinedButton(
            onPressed: () => _editThreshold(e['alert_threshold_pct']),
            child: Text('${(e['alert_threshold_pct'] as num?)?.toStringAsFixed(0) ?? 60}%')),
        ])),
        const SizedBox(height: 12),
        _card(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Monthly cap & rollover', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('${_money(e['monthly_cap_cents'])} per member / month · '
                'unused rolls over ${(e['cap_rollover_pct'] as num?)?.toStringAsFixed(0) ?? 50}% to next month.',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          OutlinedButton(
            onPressed: () => _editRollover(e['cap_rollover_pct']),
            child: Text('${(e['cap_rollover_pct'] as num?)?.toStringAsFixed(0) ?? 50}%')),
        ])),
      ],
    );
  }

  Future<void> _editRollover(dynamic current) async {
    final ctl = TextEditingController(text: (current as num?)?.toString() ?? '50');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cap rollover'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('When a member doesn\'t use their full monthly cap, this % of the '
              'unused base allowance rolls into next month (bounded — never compounds).',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: ctl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rollover %', suffixText: '%')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final pct = double.tryParse(ctl.text.trim());
    if (pct == null) return;
    try {
      await _client.rpc('admin_set_referral_rollover_pct', params: {'p_pct': pct});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cap rollover set to ${pct.toStringAsFixed(0)}%')));
        _reload();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ── shared ────────────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: child,
      );

  Future<void> _togglePaused(Map<String, dynamic> p, bool enabled) async {
    try {
      await _client.rpc('admin_referral_set_policy', params: {
        'p_enabled': enabled,
        'p_direct_cents': p['direct_reward_cents'],
        'p_second_cents': p['second_tier_reward_cents'],
        'p_min_order_cents': p['min_order_value_cents'],
        'p_settlement_hours': p['settlement_delay_hours'],
        'p_carry_days': p['carry_forward_days'],
        'p_cap_cents': p['monthly_cap_cents'],
        'p_personal_required': p['personal_orders_required'],
        'p_notes': enabled ? 'resumed' : 'paused',
      });
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editThreshold(dynamic current) async {
    final ctl = TextEditingController(text: (current as num?)?.toString() ?? '60');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alert threshold'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Warn (WATCH) when referral payouts exceed this % of paying-member '
              'membership revenue. Going net-negative always triggers ALERT.', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: ctl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Threshold %', suffixText: '%')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final pct = double.tryParse(ctl.text.trim());
    if (pct == null) return;
    try {
      await _client.rpc('admin_set_referral_alert_pct', params: {'p_pct': pct});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Alert threshold set to ${pct.toStringAsFixed(0)}%')));
        _reload();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editPolicy(Map<String, dynamic> p) async {
    final direct = TextEditingController(text: '${((p['direct_reward_cents'] as num?) ?? 0) / 100}');
    final second = TextEditingController(text: '${((p['second_tier_reward_cents'] as num?) ?? 0) / 100}');
    final minv = TextEditingController(text: '${((p['min_order_value_cents'] as num?) ?? 0) / 100}');
    final settle = TextEditingController(text: '${p['settlement_delay_hours'] ?? 72}');
    final carry = TextEditingController(text: '${p['carry_forward_days'] ?? 60}');
    final cap = TextEditingController(text: '${((p['monthly_cap_cents'] as num?) ?? 0) / 100}');
    final personal = TextEditingController(text: '${p['personal_orders_required'] ?? 3}');
    final sym = AppConstants.currencySymbol;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit policy (prospective)'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _f(direct, 'Direct reward ($sym)'),
          _f(second, 'Tiers 2–5 reward ($sym)'),
          _f(minv, 'Min order value ($sym)'),
          _f(settle, 'Settlement delay (hours)'),
          _f(carry, 'Carry-forward (days)'),
          _f(cap, 'Monthly cap ($sym)'),
          _f(personal, 'Personal orders to unlock'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save version')),
        ],
      ),
    );
    if (ok != true) return;
    int cents(TextEditingController c) => ((double.tryParse(c.text.trim()) ?? 0) * 100).round();
    int intv(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    try {
      await _client.rpc('admin_referral_set_policy', params: {
        'p_enabled': p['enabled'] == true,
        'p_direct_cents': cents(direct), 'p_second_cents': cents(second),
        'p_min_order_cents': cents(minv), 'p_settlement_hours': intv(settle),
        'p_carry_days': intv(carry), 'p_cap_cents': cents(cap),
        'p_personal_required': intv(personal), 'p_notes': 'admin edit',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New policy version saved.')));
        _reload();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _f(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(controller: c, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, isDense: true)),
      );
}

class _AdminData {
  final Map<String, dynamic> overview;
  final Map<String, dynamic> policy;
  final Map<String, dynamic> econ;
  _AdminData({required this.overview, required this.policy, required this.econ});
}
