import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../utils/app_theme.dart';
import '../../services/referral/member_referral_service.dart';
import 'referral_tree_diagram_screen.dart';

/// "Earn with HotBite" — the HotBite Member Referral Rewards hub.
/// Earnings come only from completed member orders; nothing here is guaranteed.
class EarnWithHotBiteScreen extends ConsumerStatefulWidget {
  const EarnWithHotBiteScreen({super.key});

  @override
  ConsumerState<EarnWithHotBiteScreen> createState() => _EarnWithHotBiteScreenState();
}

class _EarnWithHotBiteScreenState extends ConsumerState<EarnWithHotBiteScreen> {
  late final MemberReferralService _svc =
      MemberReferralService(Supabase.instance.client);
  late Future<_Data> _future = _load();

  Future<_Data> _load() async {
    final summary = await _svc.mySummary();
    final rewards = await _svc.myRewards(limit: 50);
    return _Data(summary: summary, rewards: rewards);
  }

  void _reload() => setState(() => _future = _load());

  String _money(dynamic cents) {
    final c = (cents is num) ? cents.toInt() : int.tryParse('${cents ?? 0}') ?? 0;
    return '${AppConstants.currencySymbol}${(c / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earn with HotBite'),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load your rewards:\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final s = snap.data!.summary;
          final rewards = snap.data!.rewards;
          final code = (s['referral_code'] as String?) ?? '—';
          final personal = (s['personal_orders_this_month'] as num?)?.toInt() ?? 0;
          final required = (s['personal_orders_required'] as num?)?.toInt() ?? 3;
          final capUsed = (s['cap_used_cents'] as num?)?.toInt() ?? 0;
          final cap = (s['monthly_cap_cents'] as num?)?.toInt() ?? 1000000;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _hero(code, s),
              const SizedBox(height: 16),
              _rateExplainer(s),
              const SizedBox(height: 16),
              _statsGrid(s),
              const SizedBox(height: 16),
              _unlockProgress(personal, required),
              const SizedBox(height: 12),
              _capProgress(capUsed, cap),
              const SizedBox(height: 12),
              _balances(s),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ReferralTreeDiagramScreen())),
                icon: const Icon(Icons.account_tree_rounded),
                label: const Text('View my referral tree'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _changeReferrer,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Enter a referral code'),
              ),
              const SizedBox(height: 20),
              const Text('Reward history',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (rewards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No referral rewards yet. Share your code to start earning.'),
                )
              else
                ...rewards.map(_rewardTile),
              const SizedBox(height: 20),
              Text(
                'Rewards require completed orders from your active-member referrals and '
                'are not guaranteed. Rewards are credited to your HotBite wallet for use '
                'on HotBite purchases. Refunded or cancelled orders reverse their rewards.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(String code, Map<String, dynamic> s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFF5A1F), Color(0xFFFF8C42)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 42),
          const SizedBox(height: 8),
          const Text('Share HotBite, earn cashback',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(code,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(width: 10),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: AppTheme.primaryColor),
              onPressed: () => SharePlus.instance.share(ShareParams(
                  text:
                      'Join me on HotBite Delivery! Use my referral code $code when you sign up. '
                      'Order great food and I earn HotBite cashback when you do.')),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share my code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateExplainer(Map<String, dynamic> s) {
    final direct = _money(s['direct_reward_cents']);
    final second = _money(s['second_tier_reward_cents']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD3BE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You earn $direct for a qualifying order from a member you directly referred '
              '(Tier 1), plus $second for each qualifying order from members across the next '
              'four tiers of your network (Tiers 2–5).',
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _statsGrid(Map<String, dynamic> s) {
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    final cards = [
      _stat('Direct (Tier 1)', '${n('direct_count')}',
          '${n('direct_active_members')} active members', Icons.people_rounded, Colors.indigo),
      _stat('Network (Tiers 2–5)', '${n('second_tier_count')}',
          '${n('second_tier_active_members')} active members', Icons.groups_rounded, Colors.teal),
      _stat('Tier 1 earned', _money(s['tier1_credited_cents']),
          '${_money(s['tier1_pending_cents'])} pending', Icons.looks_one_rounded, AppTheme.primaryColor),
      _stat('Tiers 2–5 earned', _money(s['tier2_credited_cents']),
          '${_money(s['tier2_pending_cents'])} pending', Icons.groups_2_rounded, Colors.purple),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.55,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: cards,
    );
  }

  Widget _stat(String label, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _unlockProgress(int personal, int required) {
    final done = personal >= required;
    final left = (required - personal).clamp(0, required);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(done ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                  color: done ? Colors.green : Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  done
                      ? 'Unlocked! Your cleared rewards move to your wallet.'
                      : '$personal of $required personal orders completed. '
                        '${left == 1 ? "One more order" : "$left more orders"} to unlock your rewards.',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (personal / required).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: done ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _capProgress(int used, int cap) {
    final pct = (used / cap).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Monthly earning cap', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${_money(used)} / ${_money(cap)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct, minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: pct >= 1.0 ? Colors.red : AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balances(Map<String, dynamic> s) {
    final expiring = (s['expiring_soon_cents'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        Expanded(child: _balanceCard('Pending', _money(s['pending_cents']), Colors.orange)),
        const SizedBox(width: 10),
        Expanded(child: _balanceCard('In wallet', _money(s['credited_cents']), Colors.green)),
        if (expiring > 0) ...[
          const SizedBox(width: 10),
          Expanded(child: _balanceCard('Expiring soon', _money(expiring), Colors.red)),
        ],
      ],
    );
  }

  Widget _balanceCard(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          ],
        ),
      );

  Widget _rewardTile(Map<String, dynamic> r) {
    final status = (r['status'] as String?) ?? 'pending';
    final tier = (r['tier'] as num?)?.toInt() ?? 1;
    final color = switch (status) {
      'credited' => Colors.green,
      'reversed' => Colors.red,
      'expired' => Colors.grey,
      _ => Colors.orange,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('T$tier', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Text('${_money(r['reward_cents'])} · ${(r['purchaser_name'] as String?) ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${status[0].toUpperCase()}${status.substring(1)} · '
            'earned ${(r['earning_month'] as String?)?.substring(0, 7) ?? ''}'),
        trailing: status == 'pending' && r['expires_at'] != null
            ? Text('exp ${(r['expires_at'] as String).substring(0, 10)}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600))
            : null,
      ),
    );
  }

  Future<void> _changeReferrer() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter a referral code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Applies to your FUTURE orders only. Your past rewards are unaffected.',
                style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Referral code',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || ctl.text.trim().isEmpty) return;
    try {
      await _svc.setReferrer(ctl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Referral code applied for future orders.')));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not apply code: ${e.toString().replaceAll('Exception:', '').trim()}')));
      }
    }
  }
}

class _Data {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> rewards;
  _Data({required this.summary, required this.rewards});
}
