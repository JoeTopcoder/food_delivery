import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/customer_vehicle.dart';
import '../../providers/car_services_providers.dart';

const _kBlue    = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);

class AddEditVehicleScreen extends ConsumerStatefulWidget {
  final CustomerVehicle? vehicle;
  const AddEditVehicleScreen({super.key, this.vehicle});

  @override
  ConsumerState<AddEditVehicleScreen> createState() => _AddEditVehicleScreenState();
}

class _AddEditVehicleScreenState extends ConsumerState<AddEditVehicleScreen> {
  final _formKey  = GlobalKey<FormState>();
  bool _isLoading = false;

  // Fields
  final _makeCtrl   = TextEditingController();
  final _modelCtrl  = TextEditingController();
  final _yearCtrl   = TextEditingController();
  final _colorCtrl  = TextEditingController();
  final _plateCtrl  = TextEditingController();
  final _nickCtrl   = TextEditingController();
  String _vehicleType = 'sedan';
  bool _isDefault = false;
  String? _photoUrl;
  Uint8List? _pendingPhoto;

  static const _types = ['sedan', 'suv', 'van', 'truck', 'bike'];
  static const _typeLabels = {
    'sedan': 'Sedan', 'suv': 'SUV', 'van': 'Van',
    'truck': 'Truck', 'bike': 'Motorcycle',
  };

  bool get _isEdit => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    if (v != null) {
      _makeCtrl.text  = v.make;
      _modelCtrl.text = v.model;
      _yearCtrl.text  = v.year?.toString() ?? '';
      _colorCtrl.text = v.color ?? '';
      _plateCtrl.text = v.licensePlate ?? '';
      _nickCtrl.text  = v.nickname ?? '';
      _vehicleType    = v.vehicleType;
      _isDefault      = v.isDefault;
      _photoUrl       = v.photoUrl;
    }
  }

  @override
  void dispose() {
    _makeCtrl.dispose(); _modelCtrl.dispose(); _yearCtrl.dispose();
    _colorCtrl.dispose(); _plateCtrl.dispose(); _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _pendingPhoto = bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final svc = ref.read(customerVehicleServiceProvider);
      if (_isEdit) {
        final updated = await svc.updateVehicle(widget.vehicle!.id, {
          'make': _makeCtrl.text.trim(),
          'model': _modelCtrl.text.trim(),
          'vehicle_type': _vehicleType,
          'year': _yearCtrl.text.isNotEmpty ? int.tryParse(_yearCtrl.text) : null,
          'color': _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
          'license_plate': _plateCtrl.text.trim().isEmpty ? null : _plateCtrl.text.trim(),
          'nickname': _nickCtrl.text.trim().isEmpty ? null : _nickCtrl.text.trim(),
          'is_default': _isDefault,
        });
        if (_pendingPhoto != null) {
          final url = await svc.uploadPhoto(updated.id, _pendingPhoto!);
          if (url != null) await svc.updateVehicle(updated.id, {'photo_url': url});
        }
      } else {
        String? photoUrl;
        final v = await svc.addVehicle(
          make: _makeCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          vehicleType: _vehicleType,
          year: _yearCtrl.text.isNotEmpty ? int.tryParse(_yearCtrl.text) : null,
          color: _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
          licensePlate: _plateCtrl.text.trim().isEmpty ? null : _plateCtrl.text.trim(),
          nickname: _nickCtrl.text.trim().isEmpty ? null : _nickCtrl.text.trim(),
          isDefault: _isDefault,
        );
        if (_pendingPhoto != null) {
          photoUrl = await svc.uploadPhoto(v.id, _pendingPhoto!);
          if (photoUrl != null) await svc.updateVehicle(v.id, {'photo_url': photoUrl});
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Vehicle' : 'Add Vehicle'),
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Photo picker
              _PhotoPicker(
                photoUrl: _photoUrl,
                pendingPhoto: _pendingPhoto,
                onPick: _pickPhoto,
              ),
              const SizedBox(height: 20),

              // Vehicle type chips
              Text('Vehicle Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _types.map((t) => ChoiceChip(
                  label: Text(_typeLabels[t]!),
                  selected: _vehicleType == t,
                  selectedColor: _kBlue,
                  labelStyle: TextStyle(
                    color: _vehicleType == t ? Colors.white : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _vehicleType = t),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // Make & Model
              Row(children: [
                Expanded(child: _Field(ctrl: _makeCtrl, label: 'Make', hint: 'Toyota', required: true)),
                const SizedBox(width: 12),
                Expanded(child: _Field(ctrl: _modelCtrl, label: 'Model', hint: 'Corolla', required: true)),
              ]),
              const SizedBox(height: 12),

              // Year & Color
              Row(children: [
                Expanded(child: _Field(ctrl: _yearCtrl, label: 'Year', hint: '2022', keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _Field(ctrl: _colorCtrl, label: 'Color', hint: 'Silver')),
              ]),
              const SizedBox(height: 12),

              _Field(ctrl: _plateCtrl, label: 'License Plate', hint: 'ABC 1234'),
              const SizedBox(height: 12),
              _Field(ctrl: _nickCtrl, label: 'Nickname (optional)', hint: 'My Daily Driver'),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('Set as default vehicle', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Used automatically in bookings'),
                value: _isDefault,
                activeThumbColor: _kBlue,
                activeTrackColor: _kBlue.withValues(alpha: 0.4),
                onChanged: (v) => setState(() => _isDefault = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Add Vehicle', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final bool required;
  final TextInputType keyboard;

  const _Field({
    required this.ctrl,
    required this.label,
    this.hint,
    this.required = false,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    validator: required
        ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
        : null,
  );
}

class _PhotoPicker extends StatelessWidget {
  final String? photoUrl;
  final Uint8List? pendingPhoto;
  final VoidCallback onPick;

  const _PhotoPicker({this.photoUrl, this.pendingPhoto, required this.onPick});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (pendingPhoto != null) {
      image = Image.memory(pendingPhoto!, width: 120, height: 90, fit: BoxFit.cover);
    } else if (photoUrl != null) {
      image = Image.network(photoUrl!, width: 120, height: 90, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, size: 40, color: _kBlue));
    } else {
      image = const Icon(Icons.add_a_photo, size: 36, color: _kBlue);
    }

    return Center(
      child: GestureDetector(
        onTap: onPick,
        child: Container(
          width: 140, height: 110,
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBlue.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              image,
              Positioned(
                bottom: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
