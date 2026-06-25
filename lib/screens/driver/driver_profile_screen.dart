import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../config/supabase_config.dart';
import '../../models/driver_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';
import '../../utils/app_logger.dart';
import '../../core/utils/responsive.dart';

// ─── Colour tokens ────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0B0D14);
const _kCard = Color(0xFF1A1D2B);
const _kBorder = Color(0xFF252836);
const _kMuted = Color(0xFF9CA3AF);
const _kDark = Color(0xFF13151F);

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  // ── Vehicle / basic ──────────────────────────────────────────────────────
  late TextEditingController _vehicleNumberController;
  late TextEditingController _licenseNumberController;
  String _selectedVehicleType = 'bike';
  bool _controllersInitialized = false;
  bool _saving = false;

  // ── Identity document ─────────────────────────────────────────────────
  String _docType = 'national_id';
  final _docNumber = TextEditingController();
  File? _idFrontFile;
  File? _idBackFile;
  String? _idFrontUrl;
  String? _idBackUrl;

  // ── Driver licence ────────────────────────────────────────────────────
  File? _licenseFrontFile;
  File? _licenseBackFile;
  String? _licenseFrontUrl;
  String? _licenseBackUrl;

  // ── Vehicle registration ──────────────────────────────────────────────
  File? _vehicleRegFile;
  String? _vehicleRegUrl;

  // ── Insurance ─────────────────────────────────────────────────────────
  final _insProvider = TextEditingController();
  final _policyNumber = TextEditingController();
  File? _insFile;
  String? _insUrl;

  bool _savingDocs = false;
  bool _submitting = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _vehicleNumberController = TextEditingController();
    _licenseNumberController = TextEditingController();
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _licenseNumberController.dispose();
    _docNumber.dispose();
    _insProvider.dispose();
    _policyNumber.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _getSuccessRate(Driver? driver) {
    if (driver == null) return '—';
    final completed = driver.completedDeliveries ?? 0;
    final cancelled = driver.cancelledDeliveries ?? 0;
    final total = completed + cancelled;
    if (total == 0) return '—';
    return '${(completed / total * 100).round()}%';
  }

  Future<File?> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _kCard,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Colors.white),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final xFile = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  Future<String?> _uploadDoc(File file, String driverId, String subfolder) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final path = '$driverId/$subfolder/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await SupabaseConfig.client.storage
        .from('driver-documents')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    return SupabaseConfig.client.storage
        .from('driver-documents')
        .getPublicUrl(path);
  }

  // Upload a file to storage — returns the URL, or null on failure (non-fatal).
  Future<String?> _tryUploadDoc(File file, String driverId, String subfolder) async {
    try {
      return await _uploadDoc(file, driverId, subfolder);
    } catch (e) {
      AppLogger.error('Storage upload failed ($subfolder): $e');
      return null; // continue saving text fields even if upload fails
    }
  }

  Future<bool> _saveDocuments(Driver driver) async {
    final svc = ref.read(driverServiceProvider);
    final userId = ref.read(currentUserIdProvider)!;
    final errors = <String>[];

    // ── Identity document ──────────────────────────────────────────────────
    if (_idFrontFile != null) {
      _idFrontUrl = await _tryUploadDoc(_idFrontFile!, driver.id, 'identity/front');
    }
    if (_idBackFile != null) {
      _idBackUrl = await _tryUploadDoc(_idBackFile!, driver.id, 'identity/back');
    }
    // Save whenever doc number is filled OR we have any photo URL (new or existing)
    final hasIdData = _docNumber.text.trim().isNotEmpty ||
        _idFrontUrl != null ||
        _idBackUrl != null;
    if (hasIdData) {
      try {
        await svc.saveIdentityDocument(
          driverId: driver.id,
          documentType: _docType,
          documentNumber: _docNumber.text.trim().isEmpty ? null : _docNumber.text.trim(),
          frontPhotoUrl: _idFrontUrl,
          backPhotoUrl: _idBackUrl,
        );
      } catch (e) {
        AppLogger.error('Save identity doc error: $e');
        errors.add('Identity document');
      }
    }

    // ── Driver licence ─────────────────────────────────────────────────────
    if (_licenseFrontFile != null) {
      _licenseFrontUrl = await _tryUploadDoc(_licenseFrontFile!, driver.id, 'license/front');
    }
    if (_licenseBackFile != null) {
      _licenseBackUrl = await _tryUploadDoc(_licenseBackFile!, driver.id, 'license/back');
    }
    final hasLicenseData = _licenseNumberController.text.trim().isNotEmpty ||
        _licenseFrontUrl != null ||
        _licenseBackUrl != null;
    if (hasLicenseData) {
      try {
        await svc.saveDriverLicense(
          driverId: driver.id,
          licenseNumber: _licenseNumberController.text.trim().isEmpty
              ? null
              : _licenseNumberController.text.trim(),
          frontPhotoUrl: _licenseFrontUrl,
          backPhotoUrl: _licenseBackUrl,
        );
      } catch (e) {
        AppLogger.error('Save license error: $e');
        errors.add("Driver's licence");
      }
    }

    // ── Vehicle registration ───────────────────────────────────────────────
    if (_vehicleRegFile != null) {
      _vehicleRegUrl = await _tryUploadDoc(_vehicleRegFile!, driver.id, 'vehicle/registration');
    }
    // Always save vehicle — type and plate are always available
    try {
      await svc.saveVehicle(
        driverId: driver.id,
        vehicleType: _selectedVehicleType,
        licensePlate: _vehicleNumberController.text.trim().isEmpty
            ? null
            : _vehicleNumberController.text.trim(),
        registrationPhotoUrl: _vehicleRegUrl,
      );
    } catch (e) {
      AppLogger.error('Save vehicle error: $e');
      errors.add('Vehicle registration');
    }

    // ── Insurance ──────────────────────────────────────────────────────────
    if (_insFile != null) {
      _insUrl = await _tryUploadDoc(_insFile!, driver.id, 'insurance');
    }
    final hasInsData = _insProvider.text.trim().isNotEmpty ||
        _policyNumber.text.trim().isNotEmpty ||
        _insUrl != null;
    if (hasInsData) {
      try {
        await svc.saveInsurance(
          driverId: driver.id,
          insuranceProvider: _insProvider.text.trim().isEmpty ? null : _insProvider.text.trim(),
          policyNumber: _policyNumber.text.trim().isEmpty ? null : _policyNumber.text.trim(),
          documentPhotoUrl: _insUrl,
        );
      } catch (e) {
        AppLogger.error('Save insurance error: $e');
        errors.add('Insurance');
      }
    }

    ref.invalidate(driverProfileProvider(userId));
    ref.invalidate(driverVerificationDocsProvider(driver.id));
    return errors.isEmpty;
  }

  Future<void> _onSaveDocumentsTapped(Driver driver) async {
    setState(() => _savingDocs = true);
    try {
      final ok = await _saveDocuments(driver);
      if (!mounted) return;
      if (ok) {
        AppSnackbar.success(context, 'Documents saved successfully!');
      } else {
        AppSnackbar.error(context, 'Some sections could not be saved. Check your connection and try again.');
      }
    } catch (e) {
      AppLogger.error('Save docs error: $e');
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingDocs = false);
    }
  }

  Future<void> _submitForReview(Driver driver) async {
    setState(() => _submitting = true);
    try {
      await _saveDocuments(driver);

      final svc = ref.read(driverServiceProvider);
      await svc.submitApplication(driver.id);

      final userId = ref.read(currentUserIdProvider)!;
      ref.invalidate(driverProfileProvider(userId));
      if (mounted) {
        AppSnackbar.success(context, 'Application submitted for review!');
      }
    } catch (e) {
      AppLogger.error('Submit for review error: $e');
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to delete account: $e');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (authState.user == null || currentUserId == null) {
      if (!authState.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
          }
        });
      }
      return const Scaffold(
        backgroundColor: _kBg,
        body: AppLoadingIndicator(message: 'Loading profile...'),
      );
    }

    final driverProfileAsync = ref.watch(driverProfileProvider(currentUserId));
    final docsAsync = driverProfileAsync.valueOrNull != null
        ? ref.watch(driverVerificationDocsProvider(driverProfileAsync.valueOrNull!.id))
        : null;

    return driverProfileAsync.when(
      data: (driver) {
        if (driver != null && !_controllersInitialized) {
          _vehicleNumberController.text = driver.vehicleNumber ?? '';
          _licenseNumberController.text = driver.licenseNumber ?? '';
          _selectedVehicleType = driver.vehicleType ?? 'bike';
          _controllersInitialized = true;
        }

        // Pre-fill existing doc URLs from DB
        final docs = docsAsync?.valueOrNull;
        final existingIdDoc = (docs?['identity_documents'] as List?)?.isNotEmpty == true
            ? (docs!['identity_documents'] as List).first as Map<String, dynamic>
            : null;
        final existingLicense = docs?['license'] as Map<String, dynamic>?;
        final existingVehicle = docs?['vehicle'] as Map<String, dynamic>?;
        final existingIns = docs?['insurance'] as Map<String, dynamic>?;

        return Scaffold(
          backgroundColor: _kBg,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── Hero App Bar ────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: _kBg,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.translate_rounded, size: 20),
                    tooltip: 'App Settings',
                    onPressed: () => Navigator.of(context).pushNamed('/settings'),
                  ),
                  GestureDetector(
                    onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
                    child: Container(
                      margin: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded, size: 15, color: Color(0xFFEF4444)),
                          SizedBox(width: 5),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _HeroHeader(
                    name: authState.user!.name ?? 'Driver',
                    email: authState.user!.email ?? '',
                    imageUrl: authState.user!.profileImageUrl,
                    isAvailable: driver?.isAvailable ?? false,
                  ),
                ),
                title: Text(
                  context.l10n.driverProfile,
                  style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 0, Responsive.horizontalPadding(context), 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Quick Stats ─────────────────────────────────
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _QuickStat(
                            value: '${driver?.completedDeliveries ?? 0}',
                            label: 'Deliveries',
                            icon: Icons.local_shipping_rounded,
                            color: const Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value: driver?.rating != null && driver!.rating! > 0
                                ? driver.rating!.toStringAsFixed(1)
                                : '—',
                            label: 'Rating',
                            icon: Icons.star_rounded,
                            color: const Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value: _getSuccessRate(driver),
                            label: 'Success',
                            icon: Icons.verified_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value:
                                '${AppConstants.currencySymbol}${(driver?.totalEarnings ?? 0).toStringAsFixed(0)}',
                            label: 'Earned',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF6366F1),
                          ),
                        ],
                      ),

                      // ── Verification Status Banner ───────────────────
                      if (driver != null) ...[
                        const SizedBox(height: 20),
                        _VerificationStatusBanner(driver: driver),
                      ],

                      // ── Vehicle Information ──────────────────────────
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Vehicle Information',
                        icon: Icons.directions_car_rounded,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: _kDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF2A2D3E)),
                              ),
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedVehicleType,
                                dropdownColor: const Color(0xFF1A1D2B),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Vehicle Type',
                                  labelStyle: const TextStyle(
                                    color: _kMuted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  prefixIcon: Icon(
                                    _selectedVehicleType == 'car'
                                        ? Icons.directions_car_rounded
                                        : Icons.two_wheeler_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                  border: InputBorder.none,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'bike', child: Text('Motorcycle / Bike')),
                                  DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
                                  DropdownMenuItem(value: 'car', child: Text('Car')),
                                ],
                                onChanged: (v) => setState(() => _selectedVehicleType = v!),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              controller: _vehicleNumberController,
                              label: 'Plate Number',
                              hint: 'e.g. AB 1234',
                              icon: Icons.pin_rounded,
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              controller: _licenseNumberController,
                              label: "Driver's Licence Number",
                              hint: 'e.g. L12345678',
                              icon: Icons.badge_rounded,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ActionButton(
                        label: 'Save Vehicle Info',
                        loading: _saving,
                        onPressed: driver == null
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  await ref.read(driverServiceProvider).updateDriverProfile(
                                    driverId: driver.id,
                                    vehicleType: _selectedVehicleType,
                                    vehicleNumber: _vehicleNumberController.text.trim(),
                                    licenseNumber: _licenseNumberController.text.trim(),
                                  );
                                  ref.invalidate(driverProfileProvider(currentUserId));
                                  if (context.mounted)
                                    AppSnackbar.success(context, 'Vehicle info updated!');
                                } catch (e) {
                                  if (context.mounted)
                                    AppSnackbar.error(context, friendlyError(e));
                                } finally {
                                  if (mounted) setState(() => _saving = false);
                                }
                              },
                      ),

                      // ── Identity Document ────────────────────────────
                      const SizedBox(height: 24),
                      _SectionCard(
                        title: 'Identity Document',
                        icon: Icons.credit_card_rounded,
                        statusBadge: _docBadge(existingIdDoc?['verification_status']),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Document type
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: _kDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF2A2D3E)),
                              ),
                              child: DropdownButtonFormField<String>(
                                initialValue: _docType,
                                dropdownColor: _kCard,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  labelText: 'Document Type',
                                  labelStyle: TextStyle(color: _kMuted, fontSize: 13),
                                  border: InputBorder.none,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'national_id', child: Text('National ID')),
                                  DropdownMenuItem(value: 'passport', child: Text('Passport')),
                                  DropdownMenuItem(value: 'driving_permit', child: Text('Driving Permit')),
                                  DropdownMenuItem(value: 'voters_id', child: Text("Voter's ID")),
                                ],
                                onChanged: (v) => setState(() => _docType = v!),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              controller: _docNumber,
                              label: 'Document Number',
                              hint: 'e.g. CM123456789',
                              icon: Icons.numbers_rounded,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _PhotoUploadTile(
                                    label: 'Front Side',
                                    file: _idFrontFile,
                                    existingUrl: existingIdDoc?['front_photo_url'] as String?,
                                    onTap: () async {
                                      final f = await _pickImage();
                                      if (f != null) setState(() => _idFrontFile = f);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PhotoUploadTile(
                                    label: 'Back Side',
                                    file: _idBackFile,
                                    existingUrl: existingIdDoc?['back_photo_url'] as String?,
                                    onTap: () async {
                                      final f = await _pickImage();
                                      if (f != null) setState(() => _idBackFile = f);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ── Driver's Licence ─────────────────────────────
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: "Driver's Licence",
                        icon: Icons.badge_rounded,
                        statusBadge: _docBadge(existingLicense?['verification_status']),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _PhotoUploadTile(
                                    label: 'Front Side',
                                    file: _licenseFrontFile,
                                    existingUrl: existingLicense?['front_photo_url'] as String?,
                                    onTap: () async {
                                      final f = await _pickImage();
                                      if (f != null) setState(() => _licenseFrontFile = f);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PhotoUploadTile(
                                    label: 'Back Side',
                                    file: _licenseBackFile,
                                    existingUrl: existingLicense?['back_photo_url'] as String?,
                                    onTap: () async {
                                      final f = await _pickImage();
                                      if (f != null) setState(() => _licenseBackFile = f);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (existingLicense?['rejection_notes'] != null) ...[
                              const SizedBox(height: 10),
                              _RejectionNote(note: existingLicense!['rejection_notes'] as String),
                            ],
                          ],
                        ),
                      ),

                      // ── Vehicle Registration ─────────────────────────
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Vehicle Registration',
                        icon: Icons.directions_car_filled_rounded,
                        statusBadge: _docBadge(existingVehicle?['verification_status']),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PhotoUploadTile(
                              label: 'Registration Document',
                              file: _vehicleRegFile,
                              existingUrl: existingVehicle?['registration_photo_url'] as String?,
                              wide: true,
                              onTap: () async {
                                final f = await _pickImage();
                                if (f != null) setState(() => _vehicleRegFile = f);
                              },
                            ),
                            if (existingVehicle?['rejection_notes'] != null) ...[
                              const SizedBox(height: 10),
                              _RejectionNote(note: existingVehicle!['rejection_notes'] as String),
                            ],
                          ],
                        ),
                      ),

                      // ── Insurance ────────────────────────────────────
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Insurance',
                        icon: Icons.security_rounded,
                        statusBadge: _docBadge(existingIns?['verification_status']),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StyledField(
                              controller: _insProvider,
                              label: 'Insurance Provider',
                              hint: 'e.g. AXA, Jubilee',
                              icon: Icons.business_rounded,
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              controller: _policyNumber,
                              label: 'Policy Number',
                              hint: 'e.g. POL-123456',
                              icon: Icons.numbers_rounded,
                            ),
                            const SizedBox(height: 14),
                            _PhotoUploadTile(
                              label: 'Insurance Document',
                              file: _insFile,
                              existingUrl: existingIns?['document_photo_url'] as String?,
                              wide: true,
                              onTap: () async {
                                final f = await _pickImage();
                                if (f != null) setState(() => _insFile = f);
                              },
                            ),
                            if (existingIns?['rejection_notes'] != null) ...[
                              const SizedBox(height: 10),
                              _RejectionNote(note: existingIns!['rejection_notes'] as String),
                            ],
                          ],
                        ),
                      ),

                      // ── Save Documents Button ────────────────────────
                      const SizedBox(height: 20),
                      _ActionButton(
                        label: 'Save Documents',
                        loading: _savingDocs,
                        color: const Color(0xFF6366F1),
                        icon: Icons.upload_rounded,
                        onPressed: driver == null
                            ? null
                            : () => _onSaveDocumentsTapped(driver),
                      ),

                      // ── Submit for Review ────────────────────────────
                      if (driver != null &&
                          (driver.driverStatus == 'draft' ||
                              driver.driverStatus == 'rejected' ||
                              driver.driverStatus == 'expired_documents')) ...[
                        const SizedBox(height: 12),
                        _ActionButton(
                          label: 'Submit for Review',
                          loading: _submitting,
                          color: const Color(0xFF22C55E),
                          icon: Icons.send_rounded,
                          onPressed: () => _submitForReview(driver),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'Our team will review your documents within 24-48 hours.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: _kMuted),
                          ),
                        ),
                      ],

                      // ── Delete Account ───────────────────────────────
                      const SizedBox(height: 32),
                      _DeleteAccountButton(
                        onPressed: () => _confirmDeleteAccount(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: _kBg,
        body: AppLoadingIndicator(
          message: 'Loading driver profile...',
          color: AppTheme.primaryColor,
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: _kBg,
        body: AppErrorState(message: friendlyError(err)),
      ),
    );
  }

  Widget? _docBadge(String? status) {
    if (status == null) return null;
    Color color;
    String label;
    switch (status) {
      case 'approved':
        color = const Color(0xFF22C55E);
        label = 'Approved';
        break;
      case 'rejected':
        color = const Color(0xFFEF4444);
        label = 'Rejected';
        break;
      case 'expired':
        color = const Color(0xFFF59E0B);
        label = 'Expired';
        break;
      default:
        color = const Color(0xFF6B7280);
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─── Verification Status Banner ───────────────────────────────────────────────

class _VerificationStatusBanner extends StatelessWidget {
  final Driver driver;
  const _VerificationStatusBanner({required this.driver});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color icon;
    String title;
    String subtitle;
    IconData iconData;

    switch (driver.driverStatus) {
      case 'approved':
        bg = const Color(0xFF22C55E).withValues(alpha: 0.1);
        border = const Color(0xFF22C55E).withValues(alpha: 0.3);
        icon = const Color(0xFF22C55E);
        iconData = Icons.verified_rounded;
        title = 'Account Approved';
        subtitle = 'You are verified and can accept deliveries.';
        break;
      case 'pending_review':
      case 'under_review':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.1);
        border = const Color(0xFFF59E0B).withValues(alpha: 0.3);
        icon = const Color(0xFFF59E0B);
        iconData = Icons.hourglass_top_rounded;
        title = 'Under Review';
        subtitle = 'Our team is reviewing your documents. This takes 24-48 hours.';
        break;
      case 'rejected':
        bg = const Color(0xFFEF4444).withValues(alpha: 0.1);
        border = const Color(0xFFEF4444).withValues(alpha: 0.3);
        icon = const Color(0xFFEF4444);
        iconData = Icons.cancel_rounded;
        title = 'Application Rejected';
        subtitle = driver.rejectionReason ?? 'Please re-upload your documents and resubmit.';
        break;
      case 'suspended':
        bg = const Color(0xFFEF4444).withValues(alpha: 0.1);
        border = const Color(0xFFEF4444).withValues(alpha: 0.3);
        icon = const Color(0xFFEF4444);
        iconData = Icons.block_rounded;
        title = 'Account Suspended';
        subtitle = driver.rejectionReason ?? 'Please contact support for assistance.';
        break;
      case 'expired_documents':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.1);
        border = const Color(0xFFF59E0B).withValues(alpha: 0.3);
        icon = const Color(0xFFF59E0B);
        iconData = Icons.warning_amber_rounded;
        title = 'Documents Expired';
        subtitle = 'Upload renewed documents and resubmit.';
        break;
      default: // draft
        bg = const Color(0xFF6366F1).withValues(alpha: 0.1);
        border = const Color(0xFF6366F1).withValues(alpha: 0.3);
        icon = const Color(0xFF6366F1);
        iconData = Icons.assignment_rounded;
        title = 'Complete Your Profile';
        subtitle = 'Upload your documents below and submit for review.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(iconData, color: icon, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: Responsive.bodyText(context),
                    fontWeight: FontWeight.w700,
                    color: icon,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: Responsive.smallText(context), color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo Upload Tile ────────────────────────────────────────────────────────

class _PhotoUploadTile extends StatelessWidget {
  final String label;
  final File? file;
  final String? existingUrl;
  final VoidCallback onTap;
  final bool wide;

  const _PhotoUploadTile({
    required this.label,
    required this.file,
    required this.onTap,
    this.existingUrl,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = file != null || existingUrl != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: wide ? 100 : 110,
        decoration: BoxDecoration(
          color: _kDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPhoto
                ? AppTheme.primaryColor.withValues(alpha: 0.5)
                : const Color(0xFF2A2D3E),
            width: hasPhoto ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: file != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(file!, fit: BoxFit.cover),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              )
            : existingUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    existingUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(label),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_done_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              )
            : _placeholder(label),
      ),
    );
  }

  Widget _placeholder(String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_rounded, color: _kMuted, size: 28),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: _kMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap to upload',
          style: TextStyle(fontSize: 10, color: Color(0xFF4B5563)),
        ),
      ],
    );
  }
}

// ─── Rejection Note ───────────────────────────────────────────────────────────

class _RejectionNote extends StatelessWidget {
  final String note;
  const _RejectionNote({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              note,
              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;

  const _ActionButton({
    required this.label,
    required this.loading,
    this.onPressed,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.primaryColor;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon ?? Icons.save_rounded, size: 18),
        label: loading
            ? const SizedBox.shrink()
            : Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─── Hero Header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? imageUrl;
  final bool isAvailable;

  const _HeroHeader({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1D2E), _kBg],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withValues(alpha: 0.05),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryColor, const Color(0xFF6366F1)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFF1E2030),
                      backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
                      child: imageUrl == null
                          ? const Icon(Icons.person_rounded, size: 38, color: Color(0xFF6B7280))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          style: const TextStyle(fontSize: 12, color: _kMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isAvailable
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFF6B7280))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (isAvailable
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF6B7280))
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isAvailable
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isAvailable ? 'Available' : 'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isAvailable
                                      ? const Color(0xFF22C55E)
                                      : _kMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Stat ───────────────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _QuickStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? statusBadge;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.statusBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Responsive.cardPadding(context), Responsive.cardPadding(context), Responsive.cardPadding(context), 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Responsive.headingSmall(context),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (statusBadge != null) statusBadge!,
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1),
          Padding(padding: EdgeInsets.all(Responsive.cardPadding(context)), child: child),
        ],
      ),
    );
  }
}

// ─── Styled Field ─────────────────────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _kMuted, fontWeight: FontWeight.w600, fontSize: 13),
        hintStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        filled: true,
        fillColor: _kDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

// ─── Delete account button ─────────────────────────────────────────────────────
class _DeleteAccountButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DeleteAccountButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 18),
        label: const Text(
          'Delete Account',
          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFEF4444)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
