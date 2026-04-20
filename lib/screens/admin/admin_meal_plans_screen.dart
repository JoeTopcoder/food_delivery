import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/subscription_model.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class AdminMealPlansScreen extends ConsumerWidget {
  const AdminMealPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allMealPlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Meal Plans',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allMealPlansProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showCreateSheet(context, ref),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: plansAsync.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => AppErrorState(message: friendlyError(e)),
        data: (plans) => plans.isEmpty
            ? const AppEmptyState(
                icon: Icons.restaurant_menu_rounded,
                title: 'No meal plans yet',
                subtitle: 'Tap + to create one',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: plans.length,
                itemBuilder: (_, i) => _MealPlanCard(plan: plans[i]),
              ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MealPlanFormSheet(),
    );
  }
}

// ─── Meal Plan Card ────────────────────────────────────────────────────────────

class _MealPlanCard extends ConsumerWidget {
  final MealPlan plan;
  const _MealPlanCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(subscriptionServiceProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: plan.isActive
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.restaurant_menu_rounded,
                    color: plan.isActive
                        ? const Color(0xFF10B981)
                        : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (plan.description != null &&
                          plan.description!.isNotEmpty)
                        Text(
                          plan.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Active toggle
                Switch(
                  value: plan.isActive,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (v) async {
                    await service.togglePlanActive(plan.id, v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Info chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.attach_money_rounded,
                  label:
                      '${AppConstants.currencySymbol}${plan.price.toStringAsFixed(2)}',
                ),
                _Chip(
                  icon: Icons.calendar_today_rounded,
                  label: plan.frequencyLabel,
                ),
                _Chip(
                  icon: Icons.fastfood_rounded,
                  label: '${plan.mealsPerPeriod} meals',
                ),
                _Chip(
                  icon: plan.isActive
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  label: plan.isActive ? 'Active' : 'Inactive',
                  color: plan.isActive
                      ? const Color(0xFF10B981)
                      : Colors.red.shade400,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Action row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _MealPlanFormSheet(plan: plan),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Meal Plan?'),
                        content: Text(
                          'Delete "${plan.name}"? This cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await service.deletePlan(plan.id);
                    }
                  },
                  icon: const Icon(Icons.delete_rounded, size: 16),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }
}

// ─── Create / Edit Form Sheet ──────────────────────────────────────────────────

class _MealPlanFormSheet extends ConsumerStatefulWidget {
  final MealPlan? plan;
  const _MealPlanFormSheet({this.plan});

  @override
  ConsumerState<_MealPlanFormSheet> createState() => _MealPlanFormSheetState();
}

class _MealPlanFormSheetState extends ConsumerState<_MealPlanFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _mealsCtrl;
  late String _frequency;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.plan?.name ?? '');
    _descCtrl = TextEditingController(text: widget.plan?.description ?? '');
    _priceCtrl = TextEditingController(
      text: widget.plan?.price.toStringAsFixed(2) ?? '',
    );
    _mealsCtrl = TextEditingController(
      text: widget.plan?.mealsPerPeriod.toString() ?? '1',
    );
    _frequency = widget.plan?.frequency ?? 'weekly';
    _isActive = widget.plan?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _mealsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final service = ref.read(subscriptionServiceProvider);
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final meals = int.tryParse(_mealsCtrl.text.trim()) ?? 1;

    bool ok;
    if (_isEdit) {
      ok = await service.updatePlan(widget.plan!.id, {
        'name': name,
        'description': desc.isEmpty ? null : desc,
        'price': price,
        'frequency': _frequency,
        'meals_per_period': meals,
        'is_active': _isActive,
      });
    } else {
      final result = await service.createPlan(
        name: name,
        description: desc.isEmpty ? null : desc,
        price: price,
        frequency: _frequency,
        mealsPerPeriod: meals,
      );
      ok = result != null;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.pop(context);
      AppSnackbar.success(context, _isEdit ? 'Plan updated' : 'Plan created');
    } else {
      AppSnackbar.error(context, 'Failed to save plan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Edit Meal Plan' : 'Create Meal Plan',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Plan Name',
                  hintText: 'e.g. Family Weekly Box',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Description
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What does this plan include?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Price + Meals row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      decoration: InputDecoration(
                        labelText: 'Price (${AppConstants.currencySymbol})',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _mealsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Meals / Period',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (int.tryParse(v.trim()) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Frequency dropdown
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _frequency = v);
                },
              ),
              const SizedBox(height: 12),

              // Active toggle
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Visible to customers'),
                value: _isActive,
                activeThumbColor: const Color(0xFF10B981),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEdit ? 'Update Plan' : 'Create Plan',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
