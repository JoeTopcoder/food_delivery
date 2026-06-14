import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../models/promo_model.dart';
import '../../../providers/promo_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../screens/admin/admin_broadcast_sheet.dart';

class WebAdminPromosPage extends ConsumerWidget {
  const WebAdminPromosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(allPromosProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Promo Codes', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Manage discount codes and promotions', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.campaign_rounded, size: 16),
                label: const Text('Broadcast'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: SizedBox(width: 480, child: SingleChildScrollView(child: const AdminBroadcastSheet())),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(allPromosProvider)),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: const Text('New Promo', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _CreatePromoDialog(onSaved: () => ref.invalidate(allPromosProvider)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Table ─────────────────────────────────────────────────
          promosAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allPromosProvider)),
            data: (promos) {
              if (promos.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.discount_rounded, title: 'No promo codes yet'),
                );
              }
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                      child: const Row(children: [
                        SizedBox(width: 140, child: Text('CODE', style: _hStyle)),
                        SizedBox(width: 120, child: Text('DISCOUNT', style: _hStyle)),
                        SizedBox(width: 120, child: Text('MIN ORDER', style: _hStyle)),
                        SizedBox(width: 100, child: Text('USES', style: _hStyle)),
                        SizedBox(width: 130, child: Text('EXPIRES', style: _hStyle)),
                        SizedBox(width: 90, child: Text('STATUS', style: _hStyle)),
                        Expanded(child: Text('ACTIONS', style: _hStyle, textAlign: TextAlign.right)),
                      ]),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: promos.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (_, i) => _PromoRow(promo: promos[i], onRefresh: () => ref.invalidate(allPromosProvider)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

// ── Promo Row ─────────────────────────────────────────────────────────────────

class _PromoRow extends ConsumerWidget {
  final PromoCode promo;
  final VoidCallback onRefresh;
  const _PromoRow({required this.promo, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(promoServiceProvider);
    final isExpired = promo.expiresAt != null && DateTime.now().isAfter(promo.expiresAt!);
    final isFull = promo.maxUses != null && promo.usedCount >= promo.maxUses!;
    final active = promo.isActive && !isExpired && !isFull;
    final statusColor = active ? const Color(0xFF10B981) : isExpired || isFull ? Colors.red : const Color(0xFF9CA3AF);
    final statusLabel = active ? 'Active' : isExpired ? 'Expired' : isFull ? 'Used Up' : 'Inactive';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(6)),
              child: Text(promo.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              promo.discountType == 'percentage'
                  ? '${promo.discountValue.toStringAsFixed(0)}% off'
                  : '${AppConstants.currencySymbol}${promo.discountValue.toStringAsFixed(2)} off',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              promo.minOrderAmount != null ? '${AppConstants.currencySymbol}${promo.minOrderAmount!.toStringAsFixed(0)}' : 'None',
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              promo.maxUses != null ? '${promo.usedCount}/${promo.maxUses}' : '${promo.usedCount} used',
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              promo.expiresAt != null ? DateFormat('MMM d, y').format(promo.expiresAt!) : 'No expiry',
              style: TextStyle(fontSize: 13, color: isExpired ? Colors.red : const Color(0xFF374151)),
            ),
          ),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Tooltip(
                  message: promo.isActive ? 'Deactivate' : 'Activate',
                  child: Switch.adaptive(
                    value: promo.isActive,
                    onChanged: (_) async {
                      await svc.toggleActive(promo.id, !promo.isActive);
                      onRefresh();
                    },
                    activeTrackColor: const Color(0xFF10B981),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Delete Promo?'),
                        content: Text('Delete "${promo.code}"?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await svc.deletePromo(promo.id);
                      onRefresh();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Promo Dialog ───────────────────────────────────────────────────────

class _CreatePromoDialog extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  const _CreatePromoDialog({required this.onSaved});

  @override
  ConsumerState<_CreatePromoDialog> createState() => _CreatePromoDialogState();
}

class _CreatePromoDialogState extends ConsumerState<_CreatePromoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  String _type = 'percentage';
  DateTime? _expiresAt;
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose(); _valueCtrl.dispose(); _minCtrl.dispose(); _maxUsesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('Create Promo Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code (e.g. SAVE20)', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed ${AppConstants.currencySymbol}')),
                      ],
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _valueCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _type == 'percentage' ? '% Value' : '${AppConstants.currencySymbol} Value',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min Order (optional)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxUsesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max Uses (optional)', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setState(() => _expiresAt = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_expiresAt == null ? 'No expiry date' : 'Expires: ${DateFormat('MMM d, y').format(_expiresAt!)}', style: const TextStyle(fontSize: 14))),
                      if (_expiresAt != null)
                        GestureDetector(onTap: () => setState(() => _expiresAt = null), child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF9CA3AF))),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                      child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Promo'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(promoServiceProvider);
      await svc.createPromo(
        code: _codeCtrl.text.trim().toUpperCase(),
        discountType: _type,
        discountValue: double.parse(_valueCtrl.text),
        minOrderAmount: _minCtrl.text.isNotEmpty ? double.tryParse(_minCtrl.text) : null,
        maxUses: _maxUsesCtrl.text.isNotEmpty ? int.tryParse(_maxUsesCtrl.text) : null,
        expiresAt: _expiresAt,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
