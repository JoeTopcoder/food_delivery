import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';
import '../../../models/finance/driver_pay_tier.dart';
import '../../../providers/admin/driver_pay_provider.dart';

class AdminDriverPayScreen extends ConsumerWidget {
  const AdminDriverPayScreen({super.key});

  String _payLabel(DriverPayTier t) => t.isPercent
      ? '${t.amount.toStringAsFixed(t.amount % 1 == 0 ? 0 : 1)}% of delivery fee'
      : '${AppConstants.currencySymbol}${t.amount.toStringAsFixed(2)} flat';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(driverPayTiersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Pay',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Range', style: TextStyle(color: Colors.white)),
        onPressed: () => _openEditor(context, ref, null),
      ),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (tiers) {
          final ranges = tiers.where((t) => !t.isDefault).toList();
          final def = tiers.where((t) => t.isDefault).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(driverPayTiersProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Drivers are paid by delivery distance. Each range pays a '
                    'flat amount or a percentage of the delivery fee. Deliveries '
                    'whose distance matches no range use the Default below.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Distance Ranges',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                if (ranges.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No ranges yet — tap “Add Range”.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                ...ranges.map((t) => _tierCard(context, ref, t)),
                const SizedBox(height: 20),
                Text('Default (out of range)',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                ...def.map((t) => _tierCard(context, ref, t)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tierCard(BuildContext context, WidgetRef ref, DriverPayTier t) {
    final title = t.isDefault
        ? 'Any other distance'
        : '${(t.minKm ?? 0).toStringAsFixed(t.minKm! % 1 == 0 ? 0 : 1)}'
            ' – ${(t.maxKm ?? 0).toStringAsFixed(t.maxKm! % 1 == 0 ? 0 : 1)} km';
    return Opacity(
      opacity: t.isActive ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: Text(_payLabel(t),
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 13)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!t.isDefault)
                Switch(
                  value: t.isActive,
                  onChanged: (v) async {
                    try {
                      await DriverPayService.updateTier(t.id, isActive: v);
                      ref.invalidate(driverPayTiersProvider);
                    } catch (e) {
                      if (context.mounted) {
                        AppSnackbar.error(context, friendlyError(e));
                      }
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _openEditor(context, ref, t),
              ),
              if (!t.isDefault)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.red),
                  onPressed: () => _confirmDelete(context, ref, t),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, DriverPayTier t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete range?'),
        content: const Text('Deliveries in this range will use the Default.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DriverPayService.deleteTier(t.id);
      ref.invalidate(driverPayTiersProvider);
      if (context.mounted) AppSnackbar.success(context, 'Range deleted');
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _openEditor(BuildContext context, WidgetRef ref, DriverPayTier? tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TierEditor(tier: tier, ref: ref),
    );
  }
}

class _TierEditor extends StatefulWidget {
  final DriverPayTier? tier;
  final WidgetRef ref;
  const _TierEditor({required this.tier, required this.ref});

  @override
  State<_TierEditor> createState() => _TierEditorState();
}

class _TierEditorState extends State<_TierEditor> {
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _amount;
  late String _type; // 'flat' | 'percent'
  bool _saving = false;

  bool get _isDefault => widget.tier?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    final t = widget.tier;
    _min = TextEditingController(text: t?.minKm?.toString() ?? '');
    _max = TextEditingController(text: t?.maxKm?.toString() ?? '');
    _amount = TextEditingController(text: t?.amount.toString() ?? '');
    _type = t?.payType ?? 'flat';
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount < 0) {
      AppSnackbar.error(context, 'Enter a valid amount');
      return;
    }
    if (_type == 'percent' && amount > 100) {
      AppSnackbar.error(context, 'Percent cannot exceed 100');
      return;
    }
    double? minKm, maxKm;
    if (!_isDefault) {
      minKm = double.tryParse(_min.text.trim());
      maxKm = double.tryParse(_max.text.trim());
      if (minKm == null || maxKm == null || maxKm <= minKm) {
        AppSnackbar.error(context, 'Enter a valid range (max greater than min)');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      if (widget.tier == null) {
        await DriverPayService.addTier(
          minKm: minKm!,
          maxKm: maxKm!,
          payType: _type,
          amount: amount,
        );
      } else {
        await DriverPayService.updateTier(
          widget.tier!.id,
          minKm: _isDefault ? null : minKm,
          maxKm: _isDefault ? null : maxKm,
          payType: _type,
          amount: amount,
        );
      }
      widget.ref.invalidate(driverPayTiersProvider);
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.success(context, 'Saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isDefault
                  ? 'Default pay (out of range)'
                  : widget.tier == null
                      ? 'Add distance range'
                      : 'Edit distance range',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (!_isDefault) ...[
              Row(
                children: [
                  Expanded(child: _numField(_min, 'Min km')),
                  const SizedBox(width: 12),
                  Expanded(child: _numField(_max, 'Max km')),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Pay type selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'flat', label: Text('Flat (JMD)')),
                ButtonSegment(value: 'percent', label: Text('Percent')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 14),
            _numField(
              _amount,
              _type == 'flat'
                  ? 'Amount (${AppConstants.currencySymbol})'
                  : 'Percent of delivery fee (0–100)',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
