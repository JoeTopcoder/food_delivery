import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Reputation Management Agent — lists in-app customer reviews without a
/// public response yet. Drafting never posts anything; only Approve & Post
/// writes to reviews.response_text, and only after admin review/edit.
class AdminReputationManagementScreen extends StatefulWidget {
  const AdminReputationManagementScreen({super.key});

  @override
  State<AdminReputationManagementScreen> createState() => _AdminReputationManagementScreenState();
}

class _AdminReputationManagementScreenState extends State<AdminReputationManagementScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _client
          .from('reviews')
          .select('*, restaurants(name)')
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() { _reviews = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _reviews.where((r) => r['response_text'] == null).toList();
    final responded = _reviews.where((r) => r['response_text'] != null).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reputation Management', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _reviews.isEmpty
                  ? const Center(child: Text('No reviews yet.', style: TextStyle(color: Colors.grey)))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('Needs Response (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 8),
                        ...pending.map((r) => _ReviewCard(review: r, onChanged: _load)),
                        if (responded.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('Responded (${responded.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 8),
                          ...responded.map((r) => _ReviewCard(review: r, onChanged: _load)),
                        ],
                      ],
                    ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final Map<String, dynamic> review;
  final VoidCallback onChanged;
  const _ReviewCard({required this.review, required this.onChanged});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _drafting = false;
  bool _submitting = false;
  String? _draftResponse;
  String? _sentiment;
  String? _urgency;
  bool _needsEscalation = false;
  final _replyCtrl = TextEditingController();

  Future<void> _generateDraft() async {
    setState(() => _drafting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'reputation-agent-draft',
        body: {'review_id': widget.review['id']},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _draftResponse = data['draft_response'] as String?;
        _sentiment = data['sentiment'] as String?;
        _urgency = data['urgency'] as String?;
        _needsEscalation = data['needs_escalation'] == true;
        _replyCtrl.text = _draftResponse ?? '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Draft failed: $e'), backgroundColor: AppTheme.errorColor));
      }
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.functions.invoke('reputation-agent-approve', body: {
        'review_id': widget.review['id'],
        'decision': decision,
        if (decision == 'approve') 'final_response': _replyCtrl.text.trim(),
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.errorColor));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final restaurantName = (r['restaurants'] as Map?)?['name'] as String? ?? 'Unknown';
    final hasResponse = r['response_text'] != null;
    final rating = (r['rating'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
                const SizedBox(width: 8),
                Expanded(child: Text(restaurantName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                if (r['created_at'] != null)
                  Text(DateFormat('MMM d').format(DateTime.parse(r['created_at']).toLocal()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            if (r['review_text'] != null) ...[
              const SizedBox(height: 6),
              Text(r['review_text'], style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            if (hasResponse) ...[
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(r['response_text'], style: const TextStyle(fontSize: 12, height: 1.4)),
              ),
            ] else ...[
              const SizedBox(height: 10),
              if (_draftResponse == null)
                OutlinedButton.icon(
                  onPressed: _drafting ? null : _generateDraft,
                  icon: _drafting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_drafting ? 'Drafting…' : 'Generate AI Draft Reply'),
                )
              else ...[
                Wrap(
                  spacing: 6,
                  children: [
                    Chip(label: Text('Sentiment: $_sentiment'), visualDensity: VisualDensity.compact),
                    Chip(label: Text('Urgency: $_urgency'), visualDensity: VisualDensity.compact,
                        backgroundColor: _urgency == 'high' ? const Color(0xFFFEE2E2) : null),
                    if (_needsEscalation)
                      const Chip(label: Text('Needs human review'), visualDensity: VisualDensity.compact, backgroundColor: Color(0xFFFEF3C7)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _replyCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Public reply (edit before posting)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () => _decide('approve'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                        child: _submitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Approve & Post'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _submitting ? null : () => _decide('reject'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
