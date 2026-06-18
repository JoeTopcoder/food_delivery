import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/address_provider.dart';
import '../../../models/address_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerAddressesPage extends ConsumerWidget {
  const WebCustomerAddressesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const AppLoadingIndicator();

    final addrsAsync = ref.watch(userAddressesProvider(userId));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My Addresses', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Manage your saved delivery locations', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog(context, ref, userId),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: addrsAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(userAddressesProvider(userId))),
              data: (addrs) {
                if (addrs.isEmpty) {
                  return const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_off_rounded, size: 64, color: Color(0xFFE2E8F0)),
                      SizedBox(height: 12),
                      Text('No saved addresses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      SizedBox(height: 4),
                      Text('Add your home or work address to speed up checkout', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                    ]),
                  );
                }
                return ListView.separated(
                  itemCount: addrs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _AddressCard(
                    address: addrs[i],
                    onSetDefault: () => _setDefault(context, ref, addrs[i], userId),
                    onEdit: () => _showEditDialog(context, ref, addrs[i], userId),
                    onDelete: () => _confirmDelete(context, ref, addrs[i], userId),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setDefault(BuildContext context, WidgetRef ref, UserAddress addr, String userId) async {
    try {
      await ref.read(addressServiceProvider).setDefault(addr.id, userId);
      ref.invalidate(userAddressesProvider(userId));
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, UserAddress addr, String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Address?'),
        content: Text('Remove "${addr.label}" from your saved addresses?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(addressServiceProvider).deleteAddress(addr.id);
      ref.invalidate(userAddressesProvider(userId));
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, String userId) {
    showDialog(context: context, builder: (_) => _AddressDialog(userId: userId));
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, UserAddress addr, String userId) {
    showDialog(context: context, builder: (_) => _AddressDialog(userId: userId, existing: addr));
  }
}

class _AddressCard extends StatelessWidget {
  final UserAddress address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressCard({required this.address, required this.onSetDefault, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final labelIcon = switch (address.label.toLowerCase()) {
      'home'  => Icons.home_rounded,
      'work'  => Icons.work_rounded,
      _       => Icons.location_on_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: address.isDefault ? Border.all(color: const Color(0xFFFF6B35), width: 1.5) : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: address.isDefault ? const Color(0xFFFF6B35).withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(labelIcon, color: address.isDefault ? const Color(0xFFFF6B35) : const Color(0xFF64748B), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(address.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            if (address.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFF6B35).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Default', style: TextStyle(fontSize: 11, color: Color(0xFFFF6B35), fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
          const SizedBox(height: 3),
          Text(address.address, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        ])),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
          onSelected: (v) {
            if (v == 'default') onSetDefault();
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            if (!address.isDefault)
              const PopupMenuItem(value: 'default', child: Row(children: [Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFFFF6B35)), SizedBox(width: 8), Text('Set as Default', style: TextStyle(color: Color(0xFFFF6B35)))])),
            const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
          ],
        ),
      ]),
    );
  }
}

class _AddressDialog extends ConsumerStatefulWidget {
  final String userId;
  final UserAddress? existing;
  const _AddressDialog({required this.userId, this.existing});

  @override
  ConsumerState<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends ConsumerState<_AddressDialog> {
  final _addrCtrl = TextEditingController();
  String _label = 'Home';
  bool _isDefault = false;
  bool _loading = false;

  static const _labels = ['Home', 'Work', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _addrCtrl.text = widget.existing!.address;
      _label = widget.existing!.label;
      _isDefault = widget.existing!.isDefault;
    }
  }

  @override
  void dispose() { _addrCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_addrCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final service = ref.read(addressServiceProvider);
      if (widget.existing != null) {
        await service.updateAddress(
          addressId: widget.existing!.id,
          label: _label,
          address: _addrCtrl.text.trim(),
        );
        if (_isDefault) {
          await service.setDefault(widget.existing!.id, widget.userId);
        }
      } else {
        await service.addAddress(
          userId: widget.userId,
          label: _label,
          address: _addrCtrl.text.trim(),
          isDefault: _isDefault,
        );
      }
      ref.invalidate(userAddressesProvider(widget.userId));
      if (mounted) { Navigator.pop(context); AppSnackbar.success(context, widget.existing != null ? 'Address updated' : 'Address added'); }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.existing != null ? 'Edit Address' : 'Add Address', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            const Text('Label', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _labels.map((l) => ChoiceChip(
                label: Text(l, style: TextStyle(fontSize: 12, color: _label == l ? Colors.white : const Color(0xFF64748B))),
                selected: _label == l,
                selectedColor: const Color(0xFFFF6B35),
                onSelected: (_) => setState(() => _label = l),
              )).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addrCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Full Address',
                hintText: 'e.g. 123 Main St, City, State',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFFFF6B35)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(
                value: _isDefault,
                activeColor: const Color(0xFFFF6B35),
                onChanged: (v) => setState(() => _isDefault = v ?? false),
              ),
              const Text('Set as default address', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing != null ? 'Save Changes' : 'Add Address', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
