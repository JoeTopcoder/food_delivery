import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/core/utils/responsive.dart';
import 'package:food_driver/modules/car_services/models/car_service_provider_image.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:image_picker/image_picker.dart';

const _kPurple = Color(0xFF7C3AED);
const _kPurpleDim = Color(0xFF5B21B6);

class CarServiceProviderProfileScreen extends ConsumerStatefulWidget {
  const CarServiceProviderProfileScreen({super.key});

  @override
  ConsumerState<CarServiceProviderProfileScreen> createState() =>
      _CarServiceProviderProfileScreenState();
}

class _CarServiceProviderProfileScreenState
    extends ConsumerState<CarServiceProviderProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '20');
  bool _initialized = false;
  bool _saving = false;

  // Locally picked files (before upload)
  File? _pickedProfile;
  File? _pickedBanner;

  // Upload progress state
  bool _uploadingProfile = false;
  bool _uploadingBanner = false;
  bool _uploadingGallery = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadProfile(String providerId) async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xf == null) return;
    setState(() => _uploadingProfile = true);
    try {
      await ref.read(carServicesServiceProvider).uploadProviderProfileImage(
            providerId,
            File(xf.path),
          );
      ref.invalidate(myCarServiceProviderProfileProvider);
      setState(() => _pickedProfile = File(xf.path));
    } catch (e) {
      AppLogger.error('Profile image upload failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingProfile = false);
    }
  }

  Future<void> _pickAndUploadBanner(String providerId) async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xf == null) return;
    setState(() => _uploadingBanner = true);
    try {
      await ref.read(carServicesServiceProvider).uploadProviderBannerImage(
            providerId,
            File(xf.path),
          );
      ref.invalidate(myCarServiceProviderProfileProvider);
      setState(() => _pickedBanner = File(xf.path));
    } catch (e) {
      AppLogger.error('Banner image upload failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  Future<void> _addGalleryImage(String providerId) async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xf == null) return;
    setState(() => _uploadingGallery = true);
    try {
      await ref.read(carServicesServiceProvider).uploadProviderGalleryImage(
            providerId,
            File(xf.path),
          );
      ref.invalidate(myCarServiceProviderProfileProvider);
    } catch (e) {
      AppLogger.error('Gallery image upload failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingGallery = false);
    }
  }

  Future<void> _deleteGalleryImage(String imageId) async {
    try {
      await ref.read(carServicesServiceProvider).deleteProviderGalleryImage(imageId);
      ref.invalidate(myCarServiceProviderProfileProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _setPrimary(String providerId, String imageId) async {
    try {
      await ref.read(carServicesServiceProvider).setPrimaryGalleryImage(providerId, imageId);
      ref.invalidate(myCarServiceProviderProfileProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = Responsive.horizontalPadding(context);
    final profileAsync = ref.watch(myCarServiceProviderProfileProvider);

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (provider) {
        if (provider != null && !_initialized) {
          _nameCtrl.text = provider.businessName;
          _bioCtrl.text = provider.bio ?? '';
          _addressCtrl.text = provider.baseLocationAddress ?? '';
          _radiusCtrl.text = provider.serviceAreaRadiusKm.toStringAsFixed(0);
          _initialized = true;
        }

        final gallery = provider?.images ?? [];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Provider Profile'),
            backgroundColor: _kPurple,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign out',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (context.mounted) {
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/signin', (_) => false);
                    }
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Banner ─────────────────────────────────────────────
                  _BannerPicker(
                    bannerUrl: provider?.bannerImageUrl,
                    pickedFile: _pickedBanner,
                    uploading: _uploadingBanner,
                    onTap: provider != null
                        ? () => _pickAndUploadBanner(provider.id)
                        : null,
                  ),

                  // ── Profile avatar (overlapping banner) ───────────────
                  Transform.translate(
                    offset: const Offset(0, -36),
                    child: Center(
                      child: _ProfileAvatarPicker(
                        imageUrl: provider?.profileImageUrl,
                        pickedFile: _pickedProfile,
                        uploading: _uploadingProfile,
                        isVerified: provider?.isVerified ?? false,
                        onTap: provider != null
                            ? () => _pickAndUploadProfile(provider.id)
                            : null,
                      ),
                    ),
                  ),

                  // Status chip
                  if (provider != null) ...[
                    Center(
                      child: provider.isVerified
                          ? const Chip(
                              label: Text('Verified Provider',
                                  style: TextStyle(fontSize: 12)),
                              backgroundColor: Color(0xFFDCFCE7),
                              side: BorderSide.none,
                            )
                          : Chip(
                              label: const Text('Pending Verification',
                                  style: TextStyle(fontSize: 12)),
                              backgroundColor: Colors.amber.shade100,
                              side: BorderSide.none,
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Fields ─────────────────────────────────────────────
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _bioCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Bio / About',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Base Location Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _radiusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Service Area Radius (km)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.radar),
                    ),
                  ),
                  const SizedBox(height: 28),

                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kPurple,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    onPressed: _saving || provider == null
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _saving = true);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(carServicesServiceProvider)
                                  .updateProviderProfile(provider.id, {
                                'business_name': _nameCtrl.text.trim(),
                                'bio': _bioCtrl.text.trim().isEmpty
                                    ? null
                                    : _bioCtrl.text.trim(),
                                'base_location_address':
                                    _addressCtrl.text.trim().isEmpty
                                        ? null
                                        : _addressCtrl.text.trim(),
                                'service_area_radius_km':
                                    double.tryParse(_radiusCtrl.text.trim()) ??
                                        20,
                              });
                              ref.invalidate(myCarServiceProviderProfileProvider);
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile updated'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              AppLogger.error(
                                  'Error updating provider profile', e);
                              if (mounted) {
                                messenger.showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Save Profile',
                            style: TextStyle(fontSize: 16)),
                  ),

                  // ── Gallery ────────────────────────────────────────────
                  if (provider != null) ...[
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        const Text('Gallery',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        _uploadingGallery
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : TextButton.icon(
                                onPressed: () =>
                                    _addGalleryImage(provider.id),
                                icon: const Icon(Icons.add_photo_alternate_outlined,
                                    size: 18),
                                label: const Text('Add Photo'),
                                style: TextButton.styleFrom(
                                    foregroundColor: _kPurple),
                              ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _GalleryGrid(
                      images: gallery,
                      onDelete: _deleteGalleryImage,
                      onSetPrimary: (id) => _setPrimary(provider.id, id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Banner picker ──────────────────────────────────────────────────────────────

class _BannerPicker extends StatelessWidget {
  final String? bannerUrl;
  final File? pickedFile;
  final bool uploading;
  final VoidCallback? onTap;

  const _BannerPicker({
    required this.bannerUrl,
    required this.pickedFile,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (pickedFile != null) {
      image = Image.file(pickedFile!, width: double.infinity, height: 160, fit: BoxFit.cover);
    } else if (bannerUrl != null) {
      image = Image.network(bannerUrl!, width: double.infinity, height: 160, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _emptyBanner(context));
    } else {
      image = _emptyBanner(context);
    }

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(child: image),
            Container(color: Colors.black.withAlpha(30)),
            if (uploading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white))
            else
              Positioned(
                right: 12,
                bottom: 50,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Edit Banner',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBanner(BuildContext context) => Container(
        width: double.infinity,
        height: 160,
        color: _kPurpleDim,
        child: const Icon(Icons.local_car_wash, size: 48, color: Colors.white30),
      );
}

// ── Profile avatar picker ──────────────────────────────────────────────────────

class _ProfileAvatarPicker extends StatelessWidget {
  final String? imageUrl;
  final File? pickedFile;
  final bool uploading;
  final bool isVerified;
  final VoidCallback? onTap;

  const _ProfileAvatarPicker({
    required this.imageUrl,
    required this.pickedFile,
    required this.uploading,
    required this.isVerified,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? bg;
    if (pickedFile != null) {
      bg = FileImage(pickedFile!);
    } else if (imageUrl != null) {
      bg = NetworkImage(imageUrl!);
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: _kPurple.withValues(alpha: 0.15),
            backgroundImage: bg,
            child: bg == null
                ? const Icon(Icons.person, size: 48, color: _kPurple)
                : null,
          ),
          if (uploading)
            Positioned.fill(
              child: CircleAvatar(
                backgroundColor: Colors.black38,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: _kPurple,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                padding: const EdgeInsets.all(5),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
              ),
            ),
          if (isVerified)
            Positioned(
              bottom: 2,
              left: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                padding: const EdgeInsets.all(3),
                child: const Icon(Icons.check, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Gallery grid ───────────────────────────────────────────────────────────────

class _GalleryGrid extends StatelessWidget {
  final List<CarServiceProviderImage> images;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSetPrimary;

  const _GalleryGrid({
    required this.images,
    required this.onDelete,
    required this.onSetPrimary,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No gallery photos yet',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (ctx, i) {
        final img = images[i];
        return _GalleryTile(
          image: img,
          onDelete: () => onDelete(img.id),
          onSetPrimary: () => onSetPrimary(img.id),
        );
      },
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final CarServiceProviderImage image;
  final VoidCallback onDelete;
  final VoidCallback onSetPrimary;

  const _GalleryTile({
    required this.image,
    required this.onDelete,
    required this.onSetPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showOptions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              image.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (image.isPrimary)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kPurple,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Cover',
                      style:
                          TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _showOptions(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.more_vert,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!image.isPrimary)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Set as cover photo'),
                onTap: () {
                  Navigator.pop(context);
                  onSetPrimary();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
              title: const Text('Delete photo',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
