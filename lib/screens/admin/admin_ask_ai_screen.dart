import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import 'admin_customer_retention_screen.dart' show friendlyErrorMessage;

class _ChatMessage {
  final bool isUser;
  final String text;
  final List<String> queriesRun;
  _ChatMessage({required this.isUser, required this.text, this.queriesRun = const []});
}

/// Ask AI — free-form Q&A over the real production database for admins.
/// Backed by ops-report-agent's ask_ai action: the model explores the schema
/// and runs its own read-only SQL to ground every answer in real data.
/// Nothing it does can write — enforced at the database level (see
/// migration 20260712000002_ai_readonly_query.sql), not just by instruction.
class AdminAskAiScreen extends StatefulWidget {
  const AdminAskAiScreen({super.key});

  @override
  State<AdminAskAiScreen> createState() => _AdminAskAiScreenState();
}

class _AdminAskAiScreenState extends State<AdminAskAiScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _asking = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _ask() async {
    final question = _inputCtrl.text.trim();
    if (question.isEmpty || _asking) return;
    // Snapshot the history before adding this turn's own question to it —
    // the server treats `question` as the new user turn and `history` as
    // everything before it, so this list must not include it twice.
    final history = _messages.map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text}).toList();
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: question));
      _asking = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'ask_ai',
        'question': question,
        'history': history,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: data['answer'] as String? ?? "I couldn't come up with an answer for that.",
          queriesRun: List<String>.from(data['queries_run'] ?? []),
        ));
      });
    } catch (e) {
      setState(() => _messages.add(_ChatMessage(isUser: false, text: 'Something went wrong: ${friendlyErrorMessage(e)}')));
    } finally {
      if (mounted) setState(() => _asking = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'New conversation',
              onPressed: () => setState(() => _messages.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 40, color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text(
                            'Ask anything about your business — orders, customers, restaurants, drivers, payouts, promos. Every answer is grounded in a real, read-only query against your live data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_asking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      return _MessageBubble(message: _messages[i]);
                    },
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
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      decoration: InputDecoration(
                        hintText: 'e.g. "Which restaurant had the most cancelled orders this month?"',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _asking ? null : _ask,
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
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

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primaryColor : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 14, height: 1.4)),
            if (message.queriesRun.isNotEmpty) ...[
              const SizedBox(height: 8),
              _QueriesDisclosure(queries: message.queriesRun),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueriesDisclosure extends StatefulWidget {
  final List<String> queries;
  const _QueriesDisclosure({required this.queries});

  @override
  State<_QueriesDisclosure> createState() => _QueriesDisclosureState();
}

class _QueriesDisclosureState extends State<_QueriesDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey[600]),
              Text('${widget.queries.length} quer${widget.queries.length == 1 ? 'y' : 'ies'} run', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.queries
                  .map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(q, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
