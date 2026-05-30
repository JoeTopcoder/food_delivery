import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/promo_model.dart';
import '../../providers/promo_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import 'admin_broadcast_sheet.dart';

class AdminPromosScreen extends ConsumerWidget {
  const AdminPromosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(allPromosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Promo Codes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Broadcast to customers',
            icon: const Icon(Icons.campaign_rounded),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AdminBroadcastSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allPromosProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showCreateSheet(context, ref),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: promosAsync.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => AppErrorState(message: friendlyError(e)),
        data: (promos) => promos.isEmpty
            ? const AppEmptyState(
                icon: Icons.discount_rounded,
                title: 'No promo codes yet',
                subtitle: 'Tap + to create one',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: promos.length,
                itemBuilder: (_, i) => _PromoCard(
                  promo: promos[i],
                  onRefresh: () => ref.invalidate(allPromosProvider),
                ),
              ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CreatePromoSheet(onSaved: () => ref.invalidate(allPromosProvider)),
    );
  }
}

// ─── Promo Card ────────────────────────────────────────────────────────────────

class _PromoCard extends ConsumerWidget {
  final PromoCode promo;
  final VoidCallback onRefresh;
  const _PromoCard({required this.promo, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(promoServiceProvider);
    final isExpired =
        promo.expiresAt != null && DateTime.now().isAfter(promo.expiresAt!);
    final isFull = promo.maxUses != null && promo.usedCount >= promo.maxUses!;
    final active = promo.isActive && !isExpired && !isFull;

    Color statusColor = active
        ? const Color(0xFF10B981)
        : isExpired || isFull
        ? Colors.red
        : const Color(0xFF9CA3AF);
    String statusLabel = active
        ? 'Active'
        : isExpired
        ? 'Expired'
        : isFull
        ? 'Used Up'
        : 'Inactive';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Code chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  promo.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF9CA3AF),
                ),
                onSelected: (v) async {
                  if (v == 'toggle') {
                    await service.toggleActive(promo.id, !promo.isActive);
                    onRefresh();
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Promo?'),
                        content: Text('Delete promo code "${promo.code}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await service.deletePromo(promo.id);
                      onRefresh();
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(promo.isActive ? 'Deactivate' : 'Activate'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Details
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _InfoPill(
                label: promo.discountType == 'percentage'
                    ? '${promo.discountValue.toStringAsFixed(0)}% off'
                    : '${AppConstants.currencySymbol}${promo.discountValue.toStringAsFixed(0)} off',
                icon: Icons.discount_rounded,
                color: const Color(0xFF6366F1),
              ),
              if (promo.minOrderAmount != null)
                _InfoPill(
                  label: 'Min ${AppConstants.currencySymbol}${promo.minOrderAmount!.toStringAsFixed(0)}',
                  icon: Icons.shopping_cart_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              if (promo.maxUses != null)
                _InfoPill(
                  label: '${promo.usedCount}/${promo.maxUses} used',
                  icon: Icons.people_rounded,
                  color: const Color(0xFF10B981),
                ),
              if (promo.expiresAt != null)
                _InfoPill(
                  label: 'Exp ${DateFormat('MMM d').format(promo.expiresAt!)}',
                  icon: Icons.schedule_rounded,
                  color: isExpired ? Colors.red : const Color(0xFF9CA3AF),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _InfoPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Create Promo Sheet ────────────────────────────────────────────────────────

class _CreatePromoSheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  const _CreatePromoSheet({required this.onSaved});

  @override
  ConsumerState<_CreatePromoSheet> createState() => _CreatePromoSheetState();
}

class _CreatePromoSheetState extends ConsumerState<_CreatePromoSheet> {
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
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Create Promo Code',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Code (e.g. SAVE20)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // Type + Value row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        items: [
                          const DropdownMenuItem(
                            value: 'percentage',
                            child: Text('Percentage'),
                          ),
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed ${AppConstants.currencySymbol}'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _type = v!),
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _type == 'percentage'
                              ? '% Value'
                              : '${AppConstants.currencySymbol} Value',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || double.tryParse(v) == null)
                            ? 'Invalid'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Min Order ${AppConstants.currencySymbol} (optional)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _maxUsesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Uses (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Expires at
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _expiresAt = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _expiresAt == null
                              ? 'No expiry date'
                              : 'Expires: ${DateFormat('MMM d, y').format(_expiresAt!)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (_expiresAt != null)
                          GestureDetector(
                            onTap: () => setState(() => _expiresAt = null),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : const Text(
                            'Create Promo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
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
      final service = ref.read(promoServiceProvider);
      await service.createPromo(
        code: _codeCtrl.text.trim(),
        discountType: _type,
        discountValue: double.parse(_valueCtrl.text),
        minOrderAmount: _minCtrl.text.isNotEmpty
            ? double.tryParse(_minCtrl.text)
            : null,
        maxUses: _maxUsesCtrl.text.isNotEmpty
            ? int.tryParse(_maxUsesCtrl.text)
            : null,
        expiresAt: _expiresAt,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
