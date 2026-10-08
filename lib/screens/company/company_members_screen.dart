import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/company/company_service.dart';

/// Company admin: approve / reject / suspend employee applications.
class CompanyMembersScreen extends ConsumerStatefulWidget {
  const CompanyMembersScreen({super.key, required this.companyId});
  final String companyId;
  @override
  ConsumerState<CompanyMembersScreen> createState() => _CompanyMembersScreenState();
}

class _CompanyMembersScreenState extends ConsumerState<CompanyMembersScreen> {
  List<CompanyMembership> _members = [];
  bool _loading = true;
  final _busy = <String>{};

  CompanyService get _svc => ref.read(companyServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _members = await _svc.companyMembers(widget.companyId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(CompanyMembership m, String status) async {
    setState(() => _busy.add(m.id));
    try {
      await _svc.decideMember(m.id, status);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  Color _statusColor(String s) => switch (s) {
        'approved' => const Color(0xFF16A34A),
        'pending' => const Color(0xFFD97706),
        'rejected' => const Color(0xFFDC2626),
        'suspended' => const Color(0xFF6B7280),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final pending = _members.where((m) => m.status == 'pending').toList();
    final others = _members.where((m) => m.status != 'pending').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Employees')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No applications yet.', style: TextStyle(color: Colors.grey)))),
                  if (pending.isNotEmpty) ...[
                    const Text('Pending applications', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ...pending.map(_pendingCard),
                    const SizedBox(height: 16),
                  ],
                  if (others.isNotEmpty) ...[
                    const Text('Members', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ...others.map(_memberCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _pendingCard(CompanyMembership m) {
    final busy = _busy.contains(m.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.displayName ?? 'Employee', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (m.displayEmail != null) Text(m.displayEmail!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => _decide(m, 'approved'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                child: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => _decide(m, 'rejected'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                child: const Text('Reject'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _memberCard(CompanyMembership m) {
    final busy = _busy.contains(m.id);
    return Card(
      child: ListTile(
        title: Text(m.displayName ?? 'Employee'),
        subtitle: Text(m.displayEmail ?? ''),
        trailing: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : PopupMenuButton<String>(
                onSelected: (v) => _decide(m, v),
                itemBuilder: (_) => [
                  if (m.status != 'approved') const PopupMenuItem(value: 'approved', child: Text('Approve')),
                  if (m.status != 'suspended') const PopupMenuItem(value: 'suspended', child: Text('Suspend')),
                  if (m.status != 'rejected') const PopupMenuItem(value: 'rejected', child: Text('Reject')),
                ],
                child: Chip(
                  label: Text(m.status, style: TextStyle(color: _statusColor(m.status), fontSize: 12)),
                  backgroundColor: _statusColor(m.status).withValues(alpha: 0.12),
                  side: BorderSide.none,
                ),
              ),
      ),
    );
  }
}
