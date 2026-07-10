import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Menu Intelligence Agent — every issue count here is a concrete, objective
/// check (missing image/description, invalid price, duplicate name); the AI
/// only narrates which restaurants need attention. No menu item is ever
/// modified automatically.
class AdminMenuIntelligenceScreen extends StatefulWidget {
  const AdminMenuIntelligenceScreen({super.key});

  @override
  State<AdminMenuIntelligenceScreen> createState() => _AdminMenuIntelligenceScreenState();
}

class _AdminMenuIntelligenceScreenState extends State<AdminMenuIntelligenceScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>>? _summaries;
  String? _narrative;

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('menu-intelligence-agent');
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _summaries = List<Map<String, dynamic>>.from(data['summaries'] as List);
        _narrative = data['narrative'] as String?;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'Scanning menus…' : 'Scan Menus'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_narrative != null && _narrative!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFEDE9FE))),
              child: Padding(padding: const EdgeInsets.all(16), child: Text(_narrative!, style: const TextStyle(fontSize: 14, height: 1.5))),
            ),
          ],
          if (_summaries != null) ...[
            const SizedBox(height: 20),
            const Text('Menu Quality by Restaurant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            if (_summaries!.every((s) => (s['issue_score'] as num) == 0))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No menu quality issues found.', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._summaries!.where((s) => (s['issue_score'] as num) > 0).map((s) {
                final issues = <String>[
                  if ((s['missing_image'] as num) > 0) '${s['missing_image']} missing images',
                  if ((s['missing_description'] as num) > 0) '${s['missing_description']} missing descriptions',
                  if ((s['invalid_price'] as num) > 0) '${s['invalid_price']} invalid prices',
                  if ((s['duplicate_names'] as List).isNotEmpty) '${(s['duplicate_names'] as List).length} duplicate names',
                ];
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(s['restaurant_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            Text('${s['item_count']} items', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(issues.join(' · '), style: const TextStyle(fontSize: 11, color: Color(0xFFB45309))),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}
