import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_feedback_widgets.dart';

/// AI Banner Studio — describe a banner in plain words ("a banner for KFC, 25%
/// off delivery") and the banner-designer AI drafts it: it matches the real
/// restaurant, writes the copy, and creates a DRAFT banner. You preview it and
/// tap Publish to put it live (or Discard). The AI only drafts — you publish.
class AdminAiBannerStudioScreen extends ConsumerStatefulWidget {
  const AdminAiBannerStudioScreen({super.key});
  @override
  ConsumerState<AdminAiBannerStudioScreen> createState() => _State();
}

class _State extends ConsumerState<AdminAiBannerStudioScreen> {
  final _promptCtl = TextEditingController();
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _fetchDrafts() async {
    final rows = await SupabaseConfig.client
        .from('banners').select().eq('is_active', false)
        .order('created_at', ascending: false).limit(20);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _generate() async {
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty) { AppSnackbar.warning(context, 'Describe the banner you want'); return; }
    setState(() => _busy = true);
    try {
      final res = await SupabaseConfig.client.functions
          .invoke('ai-banner-designer', body: {'prompt': prompt});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        AppSnackbar.success(context, 'Draft created — preview it below, then Publish.');
        _promptCtl.clear();
        setState(() {});
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(Map<String, dynamic> b) async {
    try {
      await SupabaseConfig.client.from('banners').update({'is_active': true}).eq('id', b['id']);
      if (mounted) { AppSnackbar.success(context, 'Banner published — it will show on the home carousel.'); setState(() {}); }
    } catch (e) { if (mounted) AppSnackbar.error(context, e.toString()); }
  }

  Future<void> _discard(Map<String, dynamic> b) async {
    try {
      await SupabaseConfig.client.from('banners').delete().eq('id', b['id']);
      if (mounted) { AppSnackbar.success(context, 'Draft discarded.'); setState(() {}); }
    } catch (e) { if (mounted) AppSnackbar.error(context, e.toString()); }
  }

  @override
  void dispose() { _promptCtl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Banner Studio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED)),
            const SizedBox(width: 10),
            Expanded(child: Text('Tell the AI what banner you want. It matches the restaurant, writes the copy and drafts it. You publish.',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]))),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _promptCtl,
          minLines: 2, maxLines: 4,
          decoration: InputDecoration(
            hintText: 'e.g. "a banner for KFC, 25% off delivery today"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _generate,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.brush_rounded),
            label: Text(_busy ? 'Designing…' : 'Design banner'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Drafts (preview & publish)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchDrafts(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
            }
            final drafts = snap.data ?? [];
            if (drafts.isEmpty) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No drafts yet. Design one above.', style: TextStyle(color: Colors.grey[600]))));
            }
            return Column(children: [for (final b in drafts) _draftCard(b)]);
          },
        ),
      ]),
    );
  }

  Widget _draftCard(Map<String, dynamic> b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Preview — mirrors the home banner style.
        _BannerPreview(banner: b),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _publish(b),
            icon: const Icon(Icons.publish_rounded, size: 18),
            label: const Text('Publish'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
          )),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => _discard(b),
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
            label: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ]),
      ]),
    );
  }
}

class _BannerPreview extends StatelessWidget {
  final Map<String, dynamic> banner;
  const _BannerPreview({required this.banner});
  @override
  Widget build(BuildContext context) {
    final title = (banner['title'] ?? '').toString();
    final subtitle = (banner['subtitle'] ?? '').toString();
    final img = banner['image_url']?.toString();
    return Container(
      height: 130,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.75)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Row(children: [
        Expanded(flex: 5, child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text('Order now', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 12))),
          ]),
        )),
        if (img != null && img.isNotEmpty)
          Expanded(flex: 4, child: Image.network(img, fit: BoxFit.cover, height: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.shrink())),
      ]),
    );
  }
}
