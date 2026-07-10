import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Marketing Content Agent — drafts content from a brief. Nothing is
/// published automatically; no social/CMS channel is wired up. The admin
/// copies the result out manually.
class AdminMarketingContentScreen extends StatefulWidget {
  const AdminMarketingContentScreen({super.key});

  @override
  State<AdminMarketingContentScreen> createState() => _AdminMarketingContentScreenState();
}

class _AdminMarketingContentScreenState extends State<AdminMarketingContentScreen> {
  final _briefCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _content;

  static const _examples = [
    'Instagram caption announcing free delivery this weekend',
    'Driver recruitment flyer text for a new city launch',
    'Email to restaurants inviting them to join 7Dash',
  ];

  Future<void> _generate() async {
    if (_briefCtrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; _content = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ops-report-agent',
        body: {'agent_slug': 'marketing_content', 'brief': _briefCtrl.text.trim()},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() => _content = data['content'] as String?);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _briefCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marketing Content', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _briefCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Describe what you need',
              hintText: 'e.g. Instagram caption for a new restaurant partner launch',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _examples.map((e) => ActionChip(
                  label: Text(e, style: const TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => _briefCtrl.text = e),
                )).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'Drafting…' : 'Generate Draft'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_content != null) ...[
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(_content!, style: const TextStyle(fontSize: 14, height: 1.5)),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _content!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
