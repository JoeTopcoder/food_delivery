import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../services/referral/member_referral_service.dart';

/// "My Referral Tree" — two earning levels only. Level 1 = accounts I referred;
/// Level 2 = active members my Level-1 accounts referred. Level 3+ is never
/// shown as an earning level. Paginated; no private customer data exposed.
class ReferralTreeScreen extends ConsumerStatefulWidget {
  const ReferralTreeScreen({super.key});

  @override
  ConsumerState<ReferralTreeScreen> createState() => _ReferralTreeScreenState();
}

class _ReferralTreeScreenState extends ConsumerState<ReferralTreeScreen> {
  late final MemberReferralService _svc = MemberReferralService(Supabase.instance.client);
  String _filter = 'all';
  String _search = '';
  bool _listView = false;

  final List<Map<String, dynamic>> _level1 = [];
  final Map<String, List<Map<String, dynamic>>> _children = {};
  final Set<String> _expanded = {};
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 25;

  @override
  void initState() {
    super.initState();
    _loadLevel1(reset: true);
  }

  Future<void> _loadLevel1({bool reset = false}) async {
    if (reset) {
      _level1.clear();
      _offset = 0;
      _hasMore = true;
    }
    setState(() => _loading = true);
    try {
      final rows = await _svc.myTree(filter: _filter, limit: _page, offset: _offset);
      setState(() {
        _level1.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == _page;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(String id) async {
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    setState(() => _expanded.add(id));
    if (!_children.containsKey(id)) {
      final rows = await _svc.myTree(parent: id, filter: 'all', limit: 100);
      if (mounted) setState(() => _children[id] = rows);
    }
  }

  String _money(dynamic cents) {
    final c = (cents is num) ? cents.toInt() : int.tryParse('${cents ?? 0}') ?? 0;
    return '${AppConstants.currencySymbol}${(c / 100).toStringAsFixed(2)}';
  }

  List<Map<String, dynamic>> get _visibleLevel1 {
    if (_search.trim().isEmpty) return _level1;
    final q = _search.toLowerCase();
    return _level1
        .where((n) => (n['display_name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Referral Tree'),
        actions: [
          IconButton(
            tooltip: _listView ? 'Tree view' : 'List view',
            icon: Icon(_listView ? Icons.account_tree_rounded : Icons.view_list_rounded),
            onPressed: () => setState(() => _listView = !_listView),
          ),
        ],
      ),
      body: Column(
        children: [
          _controls(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadLevel1(reset: true),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _meHeader(),
                  const SizedBox(height: 8),
                  if (_visibleLevel1.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('No referrals yet. Share your code to grow your tree.')),
                    ),
                  ..._visibleLevel1.map(_listView ? _flatTile : _treeCard),
                  if (_loading) const Padding(
                    padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                  if (_hasMore && !_loading && _search.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton(
                          onPressed: _loadLevel1, child: const Text('Load more')),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search my direct referrals',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', 'all'),
                _filterChip('Active member', 'active'),
                _filterChip('Not yet a member', 'not_member'),
                _filterChip('Has qualifying orders', 'has_orders'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final sel = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) {
          setState(() => _filter = value);
          _loadLevel1(reset: true);
        },
      ),
    );
  }

  Widget _meHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFF5A1F), Color(0xFFFF8C42)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.person, color: Color(0xFFFF5A1F)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('You',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Text('${_level1.length}${_hasMore ? "+" : ""} direct',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _membershipBadge(bool isMember) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (isMember ? Colors.green : Colors.grey).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(isMember ? 'Member' : 'Not member',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isMember ? Colors.green.shade800 : Colors.grey.shade700)),
      );

  Widget _nodeRow(Map<String, dynamic> n, {required int level}) {
    final isMember = n['is_member'] == true;
    final orders = (n['qualifying_orders'] as num?)?.toInt() ?? 0;
    final earned = n['earned_cents'];
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: level == 1 ? const Color(0xFFFFE0CC) : Colors.blueGrey.shade50,
          child: Text('L$level',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: level == 1 ? const Color(0xFFFF5A1F) : Colors.blueGrey)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((n['display_name'] as String?) ?? 'HotBite Member',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                _membershipBadge(isMember),
                const SizedBox(width: 8),
                Text('$orders qualifying', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ]),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(earned),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFFF5A1F))),
            Text(_joined(n['joined_at']), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }

  String _joined(dynamic ts) {
    if (ts is String && ts.length >= 10) return 'since ${ts.substring(0, 10)}';
    return '';
  }

  // Tree view: expandable Level-1 cards, nested Level-2.
  Widget _treeCard(Map<String, dynamic> n) {
    final id = n['referred_id'] as String;
    final childCount = (n['child_count'] as num?)?.toInt() ?? 0;
    final expanded = _expanded.contains(id);
    final kids = _children[id] ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: childCount > 0 ? () => _toggleExpand(id) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: _nodeRow(n, level: 1)),
                  if (childCount > 0)
                    Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                ],
              ),
            ),
          ),
          if (childCount > 0 && expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (kids.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('No second-tier members yet.', style: TextStyle(fontSize: 12)),
                    )
                  else
                    ...kids.map((k) => Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: _nodeRow(k, level: 2),
                        )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // List view: flat compact rows (Level-1 only), for hundreds of referrals.
  Widget _flatTile(Map<String, dynamic> n) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(padding: const EdgeInsets.all(12), child: _nodeRow(n, level: 1)),
    );
  }
}
