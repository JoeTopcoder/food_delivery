// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/compliance_service.dart';
import '../../utils/app_theme.dart';

class AdminDeletionRequestsScreen extends StatefulWidget {
  const AdminDeletionRequestsScreen({super.key});

  @override
  State<AdminDeletionRequestsScreen> createState() =>
      _AdminDeletionRequestsScreenState();
}

class _AdminDeletionRequestsScreenState
    extends State<AdminDeletionRequestsScreen> {
  late final ComplianceService _service;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'all';

  static const _statuses = ['all', 'pending', 'reviewing', 'processed'];
  static const _statusColors = {
    'pending': Color(0xFFF59E0B),
    'reviewing': Color(0xFF0077C8),
    'processed': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _service = ComplianceService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.fetchDeletionRequests(
        status: _filterStatus == 'all' ? null : _filterStatus,
        limit: 100,
      );
      if (mounted) setState(() { _requests = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _updateStatus(String id, String status, {String? notes}) async {
    try {
      await _service.updateDeletionRequestStatus(id, status, adminNotes: notes);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showDetail(Map<String, dynamic> req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DetailSheet(request: req, onStatusChange: _updateStatus),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deletion Requests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            color: const Color(0xFFFEF3C7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Process these within 30 days of request. Anonymize personal data; retain transaction records for tax compliance.',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
            ),
          ),
          // Status filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _statuses.map((s) {
                final selected = _filterStatus == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filterStatus = s);
                      _load();
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.primaryColor : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                    : _requests.isEmpty
                        ? Center(child: Text('No $_filterStatus deletion requests', style: TextStyle(color: Colors.grey[600])))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _requests.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = _requests[i];
                              final status = r['status'] as String? ?? 'pending';
                              final color = _statusColors[status] ?? const Color(0xFF6B7280);
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () => _showDetail(r),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                    child: const Icon(Icons.person_remove_outlined, color: Color(0xFFEF4444), size: 20),
                                  ),
                                  title: Text(
                                    r['email'] as String? ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: r['requested_at'] != null
                                      ? Text(_fmt(r['requested_at'] as String), style: const TextStyle(fontSize: 12))
                                      : null,
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  String _fmt(String iso) {
    try {
      return DateFormat('MMM d, y – h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final Future<void> Function(String id, String status, {String? notes}) onStatusChange;

  const _DetailSheet({required this.request, required this.onStatusChange});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notesCtrl.text = widget.request['admin_notes'] as String? ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final id = req['id'] as String? ?? '';
    final status = req['status'] as String? ?? 'pending';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Account Deletion Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
          const SizedBox(height: 16),
          _InfoRow(label: 'Email', value: req['email'] ?? ''),
          if (req['user_id'] != null) _InfoRow(label: 'User ID', value: req['user_id']),
          _InfoRow(label: 'Status', value: status),
          if (req['requested_at'] != null) _InfoRow(label: 'Requested', value: req['requested_at']),
          if (req['processed_at'] != null) _InfoRow(label: 'Processed', value: req['processed_at']),
          if (req['reason'] != null) ...[
            const Divider(height: 24),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(req['reason'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          const Divider(height: 24),
          const Text('Admin Notes', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add notes about this request...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['pending', 'reviewing', 'processed'].map((s) {
              return OutlinedButton(
                onPressed: s == status ? null : () async {
                  await widget.onStatusChange(id, s, notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: s == status ? Colors.grey : AppTheme.primaryColor),
                  foregroundColor: s == 'processed' ? const Color(0xFF10B981) : null,
                ),
                child: Text(s[0].toUpperCase() + s.substring(1)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
