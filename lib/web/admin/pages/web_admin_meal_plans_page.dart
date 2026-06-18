import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../models/subscription_model.dart';
import '../../../providers/feature_providers.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminMealPlansPage extends ConsumerWidget {
  const WebAdminMealPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allMealPlansProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Meal Plans', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Curated meal subscriptions for customers', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(allMealPlansProvider)),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text('New Plan', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0891B2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => showDialog(context: context, builder: (_) => _MealPlanDialog(onSaved: () => ref.invalidate(allMealPlansProvider))),
            ),
          ]),
          const SizedBox(height: 28),

          plansAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allMealPlansProvider)),
            data: (plans) {
              if (plans.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.restaurant_menu_rounded, title: 'No meal plans yet', subtitle: 'Tap New Plan to create one'),
                );
              }
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: plans.map((p) => SizedBox(width: 340,
                  child: _PlanCard(plan: p, onChanged: () => ref.invalidate(allMealPlansProvider)))).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

class _PlanCard extends ConsumerWidget {
  final MealPlan plan;
  final VoidCallback onChanged;
  const _PlanCard({required this.plan, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(subscriptionServiceProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        border: Border.all(color: plan.isActive ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (plan.isActive ? const Color(0xFF10B981) : Colors.grey).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.restaurant_menu_rounded, color: plan.isActive ? const Color(0xFF10B981) : Colors.grey, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B))),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: plan.isActive ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(plan.isActive ? 'Active' : 'Inactive',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: plan.isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8))),
            ),
          ])),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                showDialog(context: context, builder: (_) => _MealPlanDialog(existing: plan, onSaved: onChanged));
              } else if (v == 'toggle') {
                await service.togglePlanActive(plan.id, !plan.isActive);
                onChanged();
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: const Text('Delete Plan'),
                  content: Text('Delete "${plan.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Delete')),
                  ],
                ));
                if (ok == true) { await service.deletePlan(plan.id); onChanged(); }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Edit')])),
              PopupMenuItem(value: 'toggle', child: Row(children: [
                Icon(plan.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16),
                const SizedBox(width: 8),
                Text(plan.isActive ? 'Deactivate' : 'Activate'),
              ])),
              const PopupMenuItem(value: 'delete', child: Row(children: [
                Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
        ]),
        const SizedBox(height: 14),
        if (plan.description != null && plan.description!.isNotEmpty)
          Text(plan.description!, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _chip(Icons.attach_money_rounded, '${AppConstants.currencySymbol}${plan.price.toStringAsFixed(2)}'),
          _chip(Icons.restaurant_menu_rounded, '${plan.mealsPerPeriod} meals'),
          _chip(Icons.repeat_rounded, plan.frequencyLabel),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: const Color(0xFF64748B)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
    ]),
  );
}

// ── Create / Edit Dialog ──────────────────────────────────────────────────────

class _MealPlanDialog extends ConsumerStatefulWidget {
  final MealPlan? existing;
  final VoidCallback onSaved;
  const _MealPlanDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_MealPlanDialog> createState() => _MealPlanDialogState();
}

class _MealPlanDialogState extends ConsumerState<_MealPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _mealsPerPeriod;
  String _frequency = 'weekly';
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(text: e?.price.toStringAsFixed(2) ?? '');
    _mealsPerPeriod = TextEditingController(text: e?.mealsPerPeriod.toString() ?? '7');
    _frequency = e?.frequency ?? 'weekly';
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _description.dispose(); _price.dispose(); _mealsPerPeriod.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      if (widget.existing != null) {
        await service.updatePlan(widget.existing!.id, {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'price': double.parse(_price.text.trim()),
          'frequency': _frequency,
          'meals_per_period': int.parse(_mealsPerPeriod.text.trim()),
          'is_active': _active,
        });
      } else {
        await service.createPlan(
          name: _name.text.trim(),
          description: _description.text.trim(),
          price: double.parse(_price.text.trim()),
          frequency: _frequency,
          mealsPerPeriod: int.parse(_mealsPerPeriod.text.trim()),
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existing != null ? 'Edit Meal Plan' : 'New Meal Plan',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const SizedBox(height: 20),
            _field(_name, 'Plan Name', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
            const SizedBox(height: 12),
            _field(_description, 'Description', maxLines: 2),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_price, 'Price (${AppConstants.currencySymbol})', type: TextInputType.number,
                validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a number' : null)),
              const SizedBox(width: 12),
              Expanded(child: _field(_mealsPerPeriod, 'Meals per period', type: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a number' : null)),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _frequency,
              decoration: _dec('Frequency'),
              items: ['daily', 'weekly', 'monthly'].map((f) => DropdownMenuItem(value: f, child: Text(f[0].toUpperCase() + f.substring(1)))).toList(),
              onChanged: (v) => setState(() => _frequency = v ?? 'weekly'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Switch(value: _active, onChanged: (v) => setState(() => _active = v), activeThumbColor: const Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(_active ? 'Active' : 'Inactive',
                style: TextStyle(fontWeight: FontWeight.w600, color: _active ? const Color(0xFF10B981) : const Color(0xFF94A3B8))),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ]),
          ])),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1, TextInputType? type, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl, maxLines: maxLines, keyboardType: type, validator: validator,
      decoration: _dec(label),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    filled: true, fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
  );
}
