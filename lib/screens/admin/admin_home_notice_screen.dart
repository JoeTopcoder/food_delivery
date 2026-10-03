import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin control for the home-screen notice banner. Put any message here
/// (e.g. "We're closing early today") and it shows at the top of the customer
/// home screen, above offers.
class AdminHomeNoticeScreen extends ConsumerStatefulWidget {
  const AdminHomeNoticeScreen({super.key});
  @override
  ConsumerState<AdminHomeNoticeScreen> createState() => _S();
}

class _S extends ConsumerState<AdminHomeNoticeScreen> {
  final _client = Supabase.instance.client;
  final _text = TextEditingController();
  bool _active = false;
  String _style = 'notice';
  bool _loading = true;
  bool _saving = false;

  static const _styles = {
    'notice': 'Notice (orange)',
    'warning': 'Warning (red)',
    'info': 'Info (blue)',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.rpc('home_announcement');
      final a = (res is Map) ? Map<String, dynamic>.from(res) : {};
      _text.text = (a['text'] as String?) ?? '';
      _active = a['active'] == true;
      _style = (a['style'] as String?) ?? 'notice';
      if (!_styles.containsKey(_style)) _style = 'notice';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _client.rpc('admin_set_home_announcement', params: {
        'p_text': _text.text.trim(),
        'p_active': _active,
        'p_style': _style,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Home notice saved.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color get _previewColor => switch (_style) {
        'warning' => const Color(0xFFDC2626),
        'info' => const Color(0xFF2563EB),
        _ => const Color(0xFFFF6B35),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Notice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Show notice on home screen', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_active ? 'Customers see the banner now.' : 'Banner is hidden.'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notice message',
                    hintText: 'e.g. We are closing early today at 6pm. Thanks for your patience!',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _style,
                  decoration: const InputDecoration(labelText: 'Style', border: OutlineInputBorder()),
                  items: _styles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => _style = v ?? 'notice'),
                ),
                const SizedBox(height: 20),
                const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_text.text.trim().isEmpty)
                  Text('Type a message to preview it.', style: TextStyle(color: Colors.grey.shade600))
                else
                  Container(
                    decoration: BoxDecoration(color: _previewColor, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.campaign_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_text.text.trim(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.3))),
                    ]),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save notice'),
                  ),
                ),
              ],
            ),
    );
  }
}
