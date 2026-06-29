// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/compliance_service.dart';
import '../../utils/app_theme.dart';

class AdminChatReportsScreen extends StatefulWidget {
  const AdminChatReportsScreen({super.key});

  @override
  State<AdminChatReportsScreen> createState() => _AdminChatReportsScreenState();
}

class _AdminChatReportsScreenState extends State<AdminChatReportsScreen> {
  late final ComplianceService _service;
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'all';

  static const _statuses = ['all', 'open', 'reviewing', 'resolved'];
  static const _statusColors = {
    'open': Color(0xFFEF4444),
    'reviewing': Color(0xFF0077C8),
    'resolved': Color(0xFF10B981),
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
      final data = await _service.fetchChatReports(
        status: _filterStatus == 'all' ? null : _filterStatus,
        limit: 100,
      );
      if (mounted) setState(() { _reports = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _service.updateChatReportStatus(id, status);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showDetail(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DetailSheet(report: report, onStatusChange: _updateStatus),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat & User Reports', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
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
                    : _reports.isEmpty
                        ? Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, size: 56, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No $_filterStatus reports', style: TextStyle(color: Colors.grey[600])),
                            ],
                          ))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _reports.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = _reports[i];
                              final status = r['status'] as String? ?? 'open';
                              final color = _statusColors[status] ?? const Color(0xFF6B7280);
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () => _showDetail(r),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.12),
                                    child: Icon(Icons.flag_outlined, color: color, size: 20),
                                  ),
                                  title: Text(
                                    r['reason'] as String? ?? 'Unknown reason',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (r['order_id'] != null)
                                        Text('Order: ${r['order_id']}', style: const TextStyle(fontSize: 12)),
                                      if (r['created_at'] != null)
                                        Text(_fmt(r['created_at'] as String), style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                  ),
                                  isThreeLine: r['order_id'] != null,
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

class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> report;
  final Future<void> Function(String id, String status) onStatusChange;

  const _DetailSheet({required this.report, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final id = report['id'] as String? ?? '';
    final status = report['status'] as String? ?? 'open';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('User Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          const SizedBox(height: 16),
          _Row(label: 'Reason', value: report['reason'] ?? ''),
          if (report['reporter_id'] != null) _Row(label: 'Reporter', value: report['reporter_id']),
          if (report['reported_user_id'] != null) _Row(label: 'Reported', value: report['reported_user_id']),
          if (report['order_id'] != null) _Row(label: 'Order ID', value: report['order_id']),
          if (report['message_id'] != null) _Row(label: 'Message ID', value: report['message_id']),
          _Row(label: 'Status', value: status),
          if (report['details'] != null) ...[
            const Divider(height: 24),
            const Text('Details', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(report['details'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          const Divider(height: 24),
          const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['open', 'reviewing', 'resolved'].map((s) {
              return OutlinedButton(
                onPressed: s == status ? null : () async {
                  await onStatusChange(id, s);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: s == status ? Colors.grey : AppTheme.primaryColor),
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

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
