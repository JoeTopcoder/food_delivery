import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Business Intelligence Agent — ask a business question, get an answer
/// grounded in real queried data. The model can only call fixed, bounded
/// query tools server-side; it never writes or runs its own SQL.
class AdminBusinessIntelligenceScreen extends StatefulWidget {
  const AdminBusinessIntelligenceScreen({super.key});

  @override
  State<AdminBusinessIntelligenceScreen> createState() => _AdminBusinessIntelligenceScreenState();
}

class _ChatEntry {
  final String question;
  String? answer;
  bool loading = true;
  String? error;
  _ChatEntry({required this.question});
}

class _AdminBusinessIntelligenceScreenState extends State<AdminBusinessIntelligenceScreen> {
  final _questionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatEntry> _entries = [];

  static const _suggestions = [
    'What was our revenue in the last 7 days?',
    'Which restaurants generated the most revenue this month?',
    'What is our cancellation and refund rate this week?',
    'How many support tickets were escalated recently?',
  ];

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    final entry = _ChatEntry(question: question.trim());
    setState(() {
      _entries.add(entry);
      _questionCtrl.clear();
    });
    _scrollToBottom();
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'business-intelligence-agent',
        body: {'question': entry.question},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        entry.answer = data['answer'] as String? ?? '(no answer)';
        entry.loading = false;
      });
    } catch (e) {
      setState(() {
        entry.error = e.toString();
        entry.loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _EmptyState(onSuggestionTap: _ask, suggestions: _suggestions)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => _ChatBubble(entry: _entries[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ask a business question…',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: _ask,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _ask(_questionCtrl.text),
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onSuggestionTap;
  const _EmptyState({required this.suggestions, required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.query_stats_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('Ask anything about your business', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ...suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => onSuggestionTap(s),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                    child: Text(s, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatEntry entry;
  const _ChatBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(16)),
              child: Text(entry.question, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
              child: entry.loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      entry.error != null ? 'Error: ${entry.error}' : (entry.answer ?? ''),
                      style: TextStyle(fontSize: 14, height: 1.4, color: entry.error != null ? Colors.red : null),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
