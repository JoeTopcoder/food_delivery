import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/platform/feature_providers.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

/// Admin screen to manage the customer-facing menu word filter. Any menu item
/// whose name/category/description contains one of these words (whole-word,
/// case-insensitive) is hidden from customers — e.g. "cocktail" hides a whole
/// "Signature Cocktails" section. Restaurant owners and admins still see them.
class AdminMenuFiltersScreen extends ConsumerStatefulWidget {
  const AdminMenuFiltersScreen({super.key});

  @override
  ConsumerState<AdminMenuFiltersScreen> createState() =>
      _AdminMenuFiltersScreenState();
}

class _AdminMenuFiltersScreenState
    extends ConsumerState<AdminMenuFiltersScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'menu_filter_words')
          .maybeSingle();
      _controller.text = (row?['value'] as String?) ?? '';
    } catch (_) {
      // leave empty; save will upsert
    }
    if (mounted) setState(() => _loading = false);
  }

  List<String> get _words => _controller.text
      .split(',')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    final normalized = _words.map((w) => w.toLowerCase()).join(',');
    try {
      await Supabase.instance.client.from('app_config').upsert({
        'key': 'menu_filter_words',
        'value': normalized,
        'value_type': 'string',
        'category': 'menu',
      }, onConflict: 'key');
      // Refresh so customer menus pick up the change immediately.
      ref.read(configVersionProvider.notifier).state++;
      ref.invalidate(menuFilterWordsProvider);
      if (mounted) {
        AppSnackbar.success(context, 'Menu filter updated');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Word Filter')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Menu items whose name, category or description contains any '
                    'of these words are hidden from customers (restaurant owners '
                    'and admins still see them). Separate words with commas. '
                    'Whole-word, case-insensitive — e.g. "cocktail" hides a whole '
                    '"Signature Cocktails" section.',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  minLines: 4,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Filter words (comma-separated)',
                    hintText: 'cocktail, vodka, beer, rum, wine…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_words.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _words
                        .map((w) => Chip(
                              label: Text(w),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: cs.errorContainer
                                  .withValues(alpha: 0.4),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Text('${_words.length} word${_words.length == 1 ? '' : 's'}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save filter'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
    );
  }
}
