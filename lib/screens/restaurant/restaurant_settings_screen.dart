import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class RestaurantSettingsScreen extends ConsumerStatefulWidget {
  const RestaurantSettingsScreen({super.key});

  @override
  ConsumerState<RestaurantSettingsScreen> createState() =>
      _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState
    extends ConsumerState<RestaurantSettingsScreen> {
  late TextEditingController _restaurantNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _cuisineController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  double _deliveryFee = 50.0;
  int _estimatedDeliveryTime = 30;
  bool _isOpen = true;
  bool _isSaving = false;
  bool _hasInitialized = false;
  File? _pickedImage;
  String? _currentImageUrl;

  // Operating hours per day
  final Map<String, Map<String, dynamic>> _operatingHours = {
    'monday': {'open': '08:00', 'close': '22:00', 'is_open': true},
    'tuesday': {'open': '08:00', 'close': '22:00', 'is_open': true},
    'wednesday': {'open': '08:00', 'close': '22:00', 'is_open': true},
    'thursday': {'open': '08:00', 'close': '22:00', 'is_open': true},
    'friday': {'open': '08:00', 'close': '22:00', 'is_open': true},
    'saturday': {'open': '09:00', 'close': '23:00', 'is_open': true},
    'sunday': {'open': '09:00', 'close': '21:00', 'is_open': true},
  };

  static const List<String> _daysOfWeek = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  @override
  void initState() {
    super.initState();
    _restaurantNameController = TextEditingController();
    _descriptionController = TextEditingController();
    _cuisineController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
  }

  @override
  void dispose() {
    _restaurantNameController.dispose();
    _descriptionController.dispose();
    _cuisineController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Widget _imagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_rounded, size: 40, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(
          'Tap to add restaurant photo',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  void _prefillFields(Restaurant restaurant) {
    if (_hasInitialized) return;
    _hasInitialized = true;

    _restaurantNameController.text = restaurant.name;
    _descriptionController.text = restaurant.description ?? '';
    _cuisineController.text = restaurant.cuisineType ?? '';
    _phoneController.text = restaurant.phone ?? '';
    _addressController.text = restaurant.address ?? '';
    _deliveryFee = restaurant.deliveryFee ?? 50.0;
    _estimatedDeliveryTime = restaurant.estimatedDeliveryTime ?? 30;
    _isOpen = restaurant.isOpen;
    _currentImageUrl = restaurant.imageUrl;

    // Load operating hours from restaurant
    if (restaurant.operatingHours != null) {
      for (final day in _daysOfWeek) {
        final dayData = restaurant.operatingHours![day];
        if (dayData is Map) {
          _operatingHours[day] = {
            'open': dayData['open'] ?? '08:00',
            'close': dayData['close'] ?? '22:00',
            'is_open': dayData['is_open'] ?? true,
          };
        }
      }
    }
  }

  Future<void> _pickRestaurantImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<String?> _uploadRestaurantImage(String restaurantId) async {
    if (_pickedImage == null) return null;
    final bytes = await _pickedImage!.readAsBytes();
    final fileName = 'restaurant-images/$restaurantId.jpg';
    await Supabase.instance.client.storage
        .from('profile-photos')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return Supabase.instance.client.storage
        .from('profile-photos')
        .getPublicUrl(fileName);
  }

  Future<void> _saveSettings(String restaurantId) async {
    setState(() => _isSaving = true);

    try {
      // Upload new restaurant image if one was picked (non-blocking)
      String? imageUrl;
      if (_pickedImage != null) {
        try {
          imageUrl = await _uploadRestaurantImage(restaurantId);
        } catch (_) {
          debugPrint('Restaurant image upload failed, saving without image');
        }
      }

      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.updateRestaurant(
        restaurantId: restaurantId,
        name: _restaurantNameController.text.trim(),
        description: _descriptionController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        cuisineType: _cuisineController.text.trim(),
        deliveryFee: _deliveryFee,
        estimatedDeliveryTime: _estimatedDeliveryTime,
        isOpen: _isOpen,
        operatingHours: Map<String, dynamic>.from(_operatingHours),
        imageUrl: imageUrl,
      );

      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null) {
        ref.invalidate(restaurantByOwnerProvider(currentUserId));
      }

      if (mounted) {
        AppSnackbar.success(context, 'Settings saved successfully!');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to manage settings.')),
      );
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading settings...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Restaurant Settings')),
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () =>
              ref.invalidate(restaurantByOwnerProvider(currentUserId)),
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Restaurant Settings')),
            body: const AppEmptyState(
              icon: Icons.storefront_rounded,
              title: 'No Restaurant Found',
              subtitle: 'No restaurant found for your account.',
            ),
          );
        }

        _prefillFields(restaurant);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Restaurant Settings'),
            actions: [
              IconButton(
                icon: const Icon(Icons.translate_rounded),
                tooltip: 'App Settings',
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign Out',
                onPressed: _signOut,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant Info
                const Text(
                  'Restaurant Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Restaurant image upload
                GestureDetector(
                  onTap: _pickRestaurantImage,
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              _pickedImage!,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _currentImageUrl != null &&
                              _currentImageUrl!.isNotEmpty
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  _currentImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _imagePlaceholder(),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Change',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _imagePlaceholder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Restaurant Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cuisineController,
                  decoration: InputDecoration(
                    labelText: 'Cuisine Type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Contact Number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                // Delivery Settings
                const Text(
                  'Delivery Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: _deliveryFee.toStringAsFixed(0),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Delivery Fee',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        helperText: 'Max \$50,000',
                      ),
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null && parsed >= 0 && parsed <= 50000) {
                          setState(() {
                            _deliveryFee = parsed;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Est. Delivery Time: $_estimatedDeliveryTime minutes'),
                    Slider(
                      value: _estimatedDeliveryTime.toDouble(),
                      onChanged: (value) {
                        setState(() {
                          _estimatedDeliveryTime = value.toInt();
                        });
                      },
                      min: 10,
                      max: 120,
                      divisions: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Status
                SwitchListTile(
                  title: const Text('Restaurant is Open'),
                  value: _isOpen,
                  onChanged: (value) {
                    setState(() {
                      _isOpen = value;
                    });
                  },
                ),
                const SizedBox(height: 24),

                // Operating Hours
                const Text(
                  'Operating Hours',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._daysOfWeek.map((day) {
                  final dayHours = _operatingHours[day]!;
                  final dayIsOpen = dayHours['is_open'] as bool;
                  final dayLabel = day[0].toUpperCase() + day.substring(1);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: dayIsOpen ? Colors.white : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: dayIsOpen
                            ? AppTheme.primaryColor.withValues(alpha: 0.3)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Checkbox(
                            value: dayIsOpen,
                            activeColor: AppTheme.primaryColor,
                            onChanged: (val) {
                              setState(() {
                                _operatingHours[day]!['is_open'] = val ?? true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            dayLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: dayIsOpen
                                  ? const Color(0xFF1F2937)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        if (dayIsOpen) ...[
                          _TimePickerChip(
                            label: dayHours['open'] as String,
                            onTap: () => _pickTime(day, 'open'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '–',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          _TimePickerChip(
                            label: dayHours['close'] as String,
                            onTap: () => _pickTime(day, 'close'),
                          ),
                        ] else
                          const Text(
                            'Closed',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),

                // Save Button
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () => _saveSettings(restaurant.id),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Settings'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickTime(String day, String field) async {
    final current = _operatingHours[day]![field] as String;
    final parts = current.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _operatingHours[day]![field] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }
}

class _TimePickerChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TimePickerChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}
