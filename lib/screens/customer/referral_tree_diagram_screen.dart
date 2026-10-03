import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../services/referral/member_referral_service.dart';
import 'referral_tree_screen.dart';

/// Visual "pyramid" referral tree: you at the top, your direct (Level 1)
/// referrals connected below, and their referrals (Level 2) below them —
/// connected by lines like an org chart. Pan and pinch-zoom to explore.
/// Two earning levels only (no Level 3 is drawn as an earning level).
class ReferralTreeDiagramScreen extends ConsumerStatefulWidget {
  const ReferralTreeDiagramScreen({super.key});
  @override
  ConsumerState<ReferralTreeDiagramScreen> createState() => _S();
}

class _S extends ConsumerState<ReferralTreeDiagramScreen> {
  late final MemberReferralService _svc = MemberReferralService(Supabase.instance.client);
  int _limit = 12;
  late Future<List<Map<String, dynamic>>> _future = _svc.treeGraph(l1Limit: _limit);

  void _reload() => setState(() => _future = _svc.treeGraph(l1Limit: _limit));

  static const _node = 46.0;
  static const _slot = 64.0;
  static const _rowH = 132.0;
  static const _hPad = 40.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Referral Tree'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_list_rounded),
            tooltip: 'List view (search & filter)',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReferralTreeScreen())),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            tooltip: 'Branches shown',
            onSelected: (v) { setState(() => _limit = v); _reload(); },
            itemBuilder: (_) => [6, 12, 20, 40]
                .map((n) => PopupMenuItem(value: n, child: Text('Show $n branches'))).toList(),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center)));
          }
          final rows = snap.data ?? [];
          if (rows.where((r) => (r['level'] as num?)?.toInt() == 1).isEmpty) {
            return const Center(child: Text('No referrals yet. Share your code to grow your tree.'));
          }
          return _buildDiagram(context, rows);
        },
      ),
    );
  }

  static const String _root = '__ROOT__';

  Widget _buildDiagram(BuildContext context, List<Map<String, dynamic>> rows) {
    // Index nodes and group children by parent. Any parent not in the node set
    // (i.e. the viewer) is treated as the ROOT. Works for any depth (up to 5).
    final byId = <String, Map<String, dynamic>>{};
    final levelOf = <String, int>{};
    for (final r in rows) {
      final id = r['node_id'] as String;
      byId[id] = r;
      levelOf[id] = (r['level'] as num?)?.toInt() ?? 1;
    }
    final childrenOf = <String, List<String>>{};
    for (final r in rows) {
      final id = r['node_id'] as String;
      final rawParent = r['parent_id'] as String?;
      final parent = (rawParent != null && byId.containsKey(rawParent)) ? rawParent : _root;
      (childrenOf[parent] ??= []).add(id);
    }
    levelOf[_root] = 0;
    int maxLevel = 0;
    for (final l in levelOf.values) { if (l > maxLevel) maxLevel = l; }

    // Post-order x assignment: leaves get sequential slots; parents centre over
    // their children. Recursion depth is bounded by the 5-tier cap.
    final x = <String, double>{};
    double cursor = _hPad;
    void assign(String id) {
      final kids = childrenOf[id] ?? const [];
      if (kids.isEmpty) {
        x[id] = cursor; cursor += _slot;
      } else {
        for (final k in kids) { assign(k); }
        x[id] = (x[kids.first]! + x[kids.last]!) / 2;
      }
    }
    assign(_root);

    final totalWidth = cursor + _hPad;
    final totalHeight = _rowH * (maxLevel + 1);
    double yOf(String id) => _rowH * (levelOf[id]! + 0.5);

    final edges = <_Edge>[];
    childrenOf.forEach((parent, kids) {
      for (final k in kids) {
        edges.add(_Edge(Offset(x[parent]!, yOf(parent)), Offset(x[k]!, yOf(k))));
      }
    });

    final nodes = <Widget>[
      _node4(x[_root]!, yOf(_root), const {'display_name': 'You', 'is_member': true}, isRoot: true),
      for (final r in rows)
        _node4(x[r['node_id'] as String]!, yOf(r['node_id'] as String), r,
            level: (r['level'] as num?)?.toInt() ?? 1),
    ];

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFFFF3EC),
          child: Row(children: [
            _legendDot(const Color(0xFFFF5A1F), 'Active member'),
            const SizedBox(width: 14),
            _legendDot(Colors.grey.shade400, 'Not a member'),
            const Spacer(),
            const Text('Pinch to zoom · drag to pan', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.15,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(200),
            child: SizedBox(
              width: totalWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  CustomPaint(size: Size(totalWidth, totalHeight), painter: _EdgePainter(edges)),
                  ...nodes,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _node4(double cx, double cy, Map<String, dynamic> n, {bool isRoot = false, int level = 0}) {
    final isMember = n['is_member'] == true;
    final color = isRoot ? const Color(0xFF1F2937) : (isMember ? const Color(0xFFFF5A1F) : Colors.grey.shade400);
    final earned = (n['earned_cents'] as num?)?.toInt() ?? 0;
    return Positioned(
      left: cx - _slot / 2,
      top: cy - _node / 2 - 4,
      width: _slot,
      child: GestureDetector(
        onTap: isRoot ? null : () => _showNode(n, level),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _node, height: _node,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 4)]),
              child: Icon(isRoot ? Icons.star_rounded : Icons.person, color: Colors.white, size: isRoot ? 26 : 24),
            ),
            const SizedBox(height: 3),
            Text(isRoot ? 'You' : ((n['display_name'] as String?) ?? ''),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
            if (!isRoot && earned > 0)
              Text('${AppConstants.currencySymbol}${(earned / 100).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFFF5A1F))),
          ],
        ),
      ),
    );
  }

  void _showNode(Map<String, dynamic> n, int level) {
    final earned = (n['earned_cents'] as num?)?.toInt() ?? 0;
    final orders = (n['qualifying_orders'] as num?)?.toInt() ?? 0;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((n['display_name'] as String?) ?? 'HotBite Member',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Level $level ${level == 1 ? "(direct)" : "(second tier)"} · '
                '${n['is_member'] == true ? "Active member" : "Not yet a member"}'),
            const SizedBox(height: 10),
            Text('Qualifying orders: $orders'),
            Text('You earned from them: ${AppConstants.currencySymbol}${(earned / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Order contents and personal details are kept private.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _Edge {
  final Offset a, b;
  _Edge(this.a, this.b);
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.edges);
  final List<_Edge> edges;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      // Elbow connector: down from parent, across, down to child — org-chart style.
      final midY = (e.a.dy + e.b.dy) / 2;
      final path = Path()
        ..moveTo(e.a.dx, e.a.dy + 20)
        ..lineTo(e.a.dx, midY)
        ..lineTo(e.b.dx, midY)
        ..lineTo(e.b.dx, e.b.dy - 24);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => old.edges != edges;
}
