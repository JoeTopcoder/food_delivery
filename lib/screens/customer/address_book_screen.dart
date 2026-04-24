import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/address_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import 'map_location_picker_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/context_extensions.dart';

class AddressBookScreen extends ConsumerWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }
    final addressAsync = ref.watch(userAddressesProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.addressBook,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showAddressSheet(context, ref, userId),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: addressAsync.when(
        loading: () =>
            const AppLoadingIndicator(message: 'Loading addresses...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(userAddressesProvider(userId)),
        ),
        data: (addresses) => addresses.isEmpty
            ? const AppEmptyState(
                icon: Icons.location_off_rounded,
                title: 'No saved addresses',
                subtitle: 'Tap + to add your first address',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: addresses.length,
                itemBuilder: (context, i) => _AddressCard(
                  address: addresses[i],
                  userId: userId,
                  onRefresh: () =>
                      ref.invalidate(userAddressesProvider(userId)),
                ),
              ),
      ),
    );
  }

  void _showAddressSheet(BuildContext context, WidgetRef ref, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressSheet(
        userId: userId,
        onSaved: () => ref.invalidate(userAddressesProvider(userId)),
      ),
    );
  }
}

// ─── Address Card ─────────────────────────────────────────────────────────────

class _AddressCard extends ConsumerWidget {
  final UserAddress address;
  final String userId;
  final VoidCallback onRefresh;
  const _AddressCard({
    required this.address,
    required this.userId,
    required this.onRefresh,
  });

  IconData get _labelIcon {
    switch (address.label.toLowerCase()) {
      case 'work':
        return Icons.work_rounded;
      case 'home':
        return Icons.home_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(addressServiceProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: address.isDefault
            ? Border.all(color: AppTheme.primaryColor, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_labelIcon, color: AppTheme.primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      address.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (address.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Default',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  address.address,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onSelected: (v) async {
              if (v == 'default') {
                await service.setDefault(address.id, userId);
                onRefresh();
              } else if (v == 'edit') {
                if (context.mounted) {
                  _showEditAddressSheet(
                    context,
                    ref,
                    address,
                    userId,
                    onRefresh,
                  );
                }
              } else if (v == 'delete') {
                await service.deleteAddress(address.id);
                onRefresh();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(context.l10n.edit)),
              if (!address.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Set as Default'),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  context.l10n.delete,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditAddressSheet(
    BuildContext context,
    WidgetRef ref,
    UserAddress address,
    String userId,
    VoidCallback onRefresh,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAddressSheet(
        address: address,
        userId: userId,
        onSaved: onRefresh,
      ),
    );
  }
}

// ─── Edit Address Sheet ───────────────────────────────────────────────────────

class _EditAddressSheet extends ConsumerStatefulWidget {
  final UserAddress address;
  final String userId;
  final VoidCallback onSaved;
  const _EditAddressSheet({
    required this.address,
    required this.userId,
    required this.onSaved,
  });

  @override
  ConsumerState<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends ConsumerState<_EditAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _label;
  late TextEditingController _addressCtrl;
  bool _loading = false;
  double? _latitude;
  double? _longitude;
  static const _labels = ['Home', 'Work', 'Other'];

  @override
  void initState() {
    super.initState();
    _label = widget.address.label;
    _addressCtrl = TextEditingController(text: widget.address.address);
    _latitude = widget.address.latitude;
    _longitude = widget.address.longitude;
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
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
              const SizedBox(height: 16),
              const Text(
                'Edit Address',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Row(
                children: _labels.map((l) {
                  final selected = _label == l;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l),
                      selected: selected,
                      onSelected: (_) => setState(() => _label = l),
                      selectedColor: AppTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.primaryColor
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Full Address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<PickedLocation>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(
                          initialLatitude: _latitude,
                          initialLongitude: _longitude,
                        ),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _addressCtrl.text = result.address;
                        _latitude = result.latitude;
                        _longitude = result.longitude;
                      });
                    }
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    _latitude != null ? 'Location pinned ✓' : 'Pick on Map',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                          'Update Address',
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
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final service = ref.read(addressServiceProvider);
      await service.updateAddress(
        addressId: widget.address.id,
        label: _label,
        address: _addressCtrl.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
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

class _AddressSheet extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onSaved;
  const _AddressSheet({required this.userId, required this.onSaved});

  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  final _formKey = GlobalKey<FormState>();
  String _label = 'Home';
  final _addressCtrl = TextEditingController();
  bool _isDefault = false;
  bool _loading = false;
  double? _latitude;
  double? _longitude;

  static const _labels = ['Home', 'Work', 'Other'];

  @override
  void dispose() {
    _addressCtrl.dispose();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
              const SizedBox(height: 16),
              const Text(
                'Add Address',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              // Label selector
              Row(
                children: _labels.map((l) {
                  final selected = _label == l;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l),
                      selected: selected,
                      onSelected: (_) => setState(() => _label = l),
                      selectedColor: AppTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.primaryColor
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Full Address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<PickedLocation>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(
                          initialLatitude: _latitude,
                          initialLongitude: _longitude,
                        ),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _addressCtrl.text = result.address;
                        _latitude = result.latitude;
                        _longitude = result.longitude;
                      });
                    }
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    _latitude != null ? 'Location pinned ✓' : 'Pick on Map',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                title: const Text('Set as default address'),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primaryColor,
              ),
              const SizedBox(height: 12),
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
                          'Save Address',
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
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final service = ref.read(addressServiceProvider);
      await service.addAddress(
        userId: widget.userId,
        label: _label,
        address: _addressCtrl.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        isDefault: _isDefault,
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
