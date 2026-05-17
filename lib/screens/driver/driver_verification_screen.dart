import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/driver/driver_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../config/supabase_config.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';
import '../../utils/safe_state_mixin.dart';

class DriverVerificationScreen extends ConsumerStatefulWidget {
  final Driver driver;
  const DriverVerificationScreen({super.key, required this.driver});

  @override
  ConsumerState<DriverVerificationScreen> createState() =>
      _DriverVerificationScreenState();
}

class _DriverVerificationScreenState
    extends ConsumerState<DriverVerificationScreen>
    with SafeConsumerStateMixin<DriverVerificationScreen> {
  static const _bg = Color(0xFF0F1117);
  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);
  static const _steps = 8;

  late int _currentStep;
  bool _loading = false;
  final _picker = ImagePicker();

  // Step 1 — Personal Info
  final _fullName = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _homeAddress = TextEditingController();
  DateTime? _dateOfBirth;

  // Step 2 — Profile Photo
  String? _profilePhotoUrl;
  File? _profilePhotoFile;

  // Step 3 — Service Type
  String _serviceType = 'food_delivery';

  // Step 4 — Identity Document
  String _docType = 'national_id';
  final _docNumber = TextEditingController();
  String? _idFrontUrl;
  String? _idBackUrl;
  File? _idFrontFile;
  File? _idBackFile;
  DateTime? _idExpiry;

  // Step 5 — Driver's License
  final _licenseNumber = TextEditingController();
  final _licenseClass = TextEditingController();
  String? _licenseFrontUrl;
  String? _licenseBackUrl;
  File? _licenseFrontFile;
  File? _licenseBackFile;
  DateTime? _licenseExpiry;

  // Step 6 — Vehicle
  String _vehicleType = 'motorcycle';
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleYear = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _licensePlate = TextEditingController();
  String? _vehicleRegUrl;
  File? _vehicleRegFile;

  // Step 7 — Insurance
  final _insuranceProvider = TextEditingController();
  final _policyNumber = TextEditingController();
  DateTime? _insuranceExpiry;
  String? _insuranceDocUrl;
  File? _insuranceDocFile;

  // Step 8 — Consents
  bool _consentTerms = false;
  bool _consentPrivacy = false;
  bool _consentBackgroundCheck = false;
  bool _consentDataSharing = false;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.driver.onboardingStep.clamp(0, _steps - 1);
    _fullName.text = widget.driver.fullName ?? '';
    _phoneNumber.text = widget.driver.phoneNumber ?? '';
    _homeAddress.text = widget.driver.homeAddress ?? '';
    _dateOfBirth = widget.driver.dateOfBirth;
    _profilePhotoUrl = widget.driver.profilePhotoUrl;
    _serviceType = widget.driver.serviceType;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phoneNumber.dispose();
    _homeAddress.dispose();
    _docNumber.dispose();
    _licenseNumber.dispose();
    _licenseClass.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleYear.dispose();
    _vehicleColor.dispose();
    _licensePlate.dispose();
    _insuranceProvider.dispose();
    _policyNumber.dispose();
    super.dispose();
  }

  DriverService get _svc => ref.read(driverServiceProvider);

  Future<String?> _uploadFile(File file, String folder, String name) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final path = '${widget.driver.id}/$folder/$name.$ext';
      await SupabaseConfig.client.storage
          .from('driver-documents')
          .uploadBinary(path, bytes, fileOptions: FileOptions(upsert: true));
      return SupabaseConfig.client.storage
          .from('driver-documents')
          .getPublicUrl(path);
    } catch (e) {
      AppLogger.error('Upload failed: $e');
      return null;
    }
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final path = '${widget.driver.id}/profile.$ext';
      await SupabaseConfig.client.storage
          .from('driver-profile-photos')
          .uploadBinary(path, bytes, fileOptions: FileOptions(upsert: true));
      return SupabaseConfig.client.storage
          .from('driver-profile-photos')
          .getPublicUrl(path);
    } catch (e) {
      AppLogger.error('Profile photo upload failed: $e');
      return null;
    }
  }

  Future<File?> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  Future<void> _pickDate({
    required DateTime? current,
    required void Function(DateTime) onPicked,
    bool mustBePast = false,
    bool mustBeFuture = false,
  }) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? (mustBeFuture ? now.add(const Duration(days: 30)) : DateTime(1990)),
      firstDate: mustBeFuture ? now : DateTime(1900),
      lastDate: mustBePast ? now : DateTime(now.year + 20),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent, surface: _cardBg),
        ),
        child: child!,
      ),
    );
    if (d != null) onPicked(d);
  }

  Future<void> _nextStep() async {
    setState(() => _loading = true);
    try {
      await _saveCurrentStep();
      if (_currentStep < _steps - 1) {
        setState(() => _currentStep++);
      } else {
        await _submitApplication();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _saveCurrentStep() async {
    final driverId = widget.driver.id;
    switch (_currentStep) {
      case 0:
        if (_fullName.text.trim().isEmpty) throw Exception('Full name is required.');
        if (_phoneNumber.text.trim().isEmpty) throw Exception('Phone number is required.');
        if (_homeAddress.text.trim().isEmpty) throw Exception('Home address is required.');
        if (_dateOfBirth == null) throw Exception('Date of birth is required.');
        await _svc.updateVerificationProfile(
          driverId: driverId,
          fullName: _fullName.text.trim(),
          phoneNumber: _phoneNumber.text.trim(),
          homeAddress: _homeAddress.text.trim(),
          dateOfBirth: _dateOfBirth,
          onboardingStep: 1,
        );

      case 1:
        if (_profilePhotoFile != null) {
          _profilePhotoUrl = await _uploadProfilePhoto(_profilePhotoFile!);
          if (_profilePhotoUrl != null) {
            await _svc.updateVerificationProfile(
              driverId: driverId,
              profilePhotoUrl: _profilePhotoUrl,
              onboardingStep: 2,
            );
          }
        } else {
          await _svc.updateVerificationProfile(driverId: driverId, onboardingStep: 2);
        }

      case 2:
        await _svc.updateVerificationProfile(
          driverId: driverId,
          serviceType: _serviceType,
          onboardingStep: 3,
        );

      case 3:
        if (_idFrontFile != null) {
          _idFrontUrl = await _uploadFile(_idFrontFile!, 'identity', 'front');
        }
        if (_idBackFile != null) {
          _idBackUrl = await _uploadFile(_idBackFile!, 'identity', 'back');
        }
        await _svc.saveIdentityDocument(
          driverId: driverId,
          documentType: _docType,
          documentNumber: _docNumber.text.trim().isEmpty ? null : _docNumber.text.trim(),
          frontPhotoUrl: _idFrontUrl,
          backPhotoUrl: _idBackUrl,
          expiryDate: _idExpiry,
        );
        await _svc.updateVerificationProfile(driverId: driverId, onboardingStep: 4);

      case 4:
        if (_licenseFrontFile != null) {
          _licenseFrontUrl = await _uploadFile(_licenseFrontFile!, 'license', 'front');
        }
        if (_licenseBackFile != null) {
          _licenseBackUrl = await _uploadFile(_licenseBackFile!, 'license', 'back');
        }
        await _svc.saveDriverLicense(
          driverId: driverId,
          licenseNumber: _licenseNumber.text.trim().isEmpty ? null : _licenseNumber.text.trim(),
          licenseClass: _licenseClass.text.trim().isEmpty ? null : _licenseClass.text.trim(),
          expiryDate: _licenseExpiry,
          frontPhotoUrl: _licenseFrontUrl,
          backPhotoUrl: _licenseBackUrl,
        );
        await _svc.updateVerificationProfile(driverId: driverId, onboardingStep: 5);

      case 5:
        if (_vehicleRegFile != null) {
          _vehicleRegUrl = await _uploadFile(_vehicleRegFile!, 'vehicle', 'registration');
        }
        await _svc.saveVehicle(
          driverId: driverId,
          vehicleType: _vehicleType,
          make: _vehicleMake.text.trim().isEmpty ? null : _vehicleMake.text.trim(),
          model: _vehicleModel.text.trim().isEmpty ? null : _vehicleModel.text.trim(),
          year: int.tryParse(_vehicleYear.text.trim()),
          color: _vehicleColor.text.trim().isEmpty ? null : _vehicleColor.text.trim(),
          licensePlate: _licensePlate.text.trim().isEmpty ? null : _licensePlate.text.trim(),
          registrationPhotoUrl: _vehicleRegUrl,
        );
        await _svc.updateVerificationProfile(driverId: driverId, onboardingStep: 6);

      case 6:
        if (_insuranceDocFile != null) {
          _insuranceDocUrl = await _uploadFile(_insuranceDocFile!, 'insurance', 'policy');
        }
        await _svc.saveInsurance(
          driverId: driverId,
          insuranceProvider: _insuranceProvider.text.trim().isEmpty ? null : _insuranceProvider.text.trim(),
          policyNumber: _policyNumber.text.trim().isEmpty ? null : _policyNumber.text.trim(),
          expiryDate: _insuranceExpiry,
          documentPhotoUrl: _insuranceDocUrl,
        );
        await _svc.updateVerificationProfile(driverId: driverId, onboardingStep: 7);

      case 7:
        if (!_consentTerms || !_consentPrivacy || !_consentBackgroundCheck) {
          throw Exception('You must accept all required agreements to continue.');
        }
        break;
    }
  }

  Future<void> _submitApplication() async {
    final driverId = widget.driver.id;
    for (final type in ['terms_of_service', 'privacy_policy', 'background_check']) {
      await _svc.recordConsent(driverId: driverId, consentType: type);
    }
    if (_consentDataSharing) {
      await _svc.recordConsent(driverId: driverId, consentType: 'data_sharing');
    }
    await _svc.submitApplication(driverId);
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) ref.invalidate(driverProfileProvider(userId));
    if (!mounted) return;
    await Navigator.pushReplacementNamed(context, '/driver-application-status');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text(
          'Verification — Step ${_currentStep + 1} of $_steps',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: _currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
            : null,
      ),
      body: Column(
        children: [
          _StepProgressBar(currentStep: _currentStep, totalSteps: _steps),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStep(),
            ),
          ),
          _BottomBar(
            loading: _loading,
            isLastStep: _currentStep == _steps - 1,
            onNext: _nextStep,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildPersonalInfo();
      case 1: return _buildProfilePhoto();
      case 2: return _buildServiceType();
      case 3: return _buildIdentityDoc();
      case 4: return _buildLicense();
      case 5: return _buildVehicle();
      case 6: return _buildInsurance();
      case 7: return _buildConsents();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 0: Personal Info ─────────────────────────────────────────────────

  Widget _buildPersonalInfo() {
    return _StepCard(
      title: 'Personal Information',
      subtitle: 'This information will be used to verify your identity.',
      children: [
        _DarkField(label: 'Full Legal Name *', controller: _fullName),
        const SizedBox(height: 12),
        _DarkField(
          label: 'Phone Number *',
          controller: _phoneNumber,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _DarkField(label: 'Home Address *', controller: _homeAddress, maxLines: 2),
        const SizedBox(height: 12),
        _DatePickerTile(
          label: 'Date of Birth *',
          value: _dateOfBirth,
          onTap: () => _pickDate(
            current: _dateOfBirth,
            mustBePast: true,
            onPicked: (d) => setState(() => _dateOfBirth = d),
          ),
        ),
      ],
    );
  }

  // ── Step 1: Profile Photo ─────────────────────────────────────────────────

  Widget _buildProfilePhoto() {
    return _StepCard(
      title: 'Profile Photo',
      subtitle: 'Upload a clear photo of your face. This appears to customers during delivery.',
      children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final f = await _pickImage(ImageSource.camera);
              if (f != null) setState(() => _profilePhotoFile = f);
            },
            child: CircleAvatar(
              radius: 60,
              backgroundColor: _cardBg,
              backgroundImage: _profilePhotoFile != null
                  ? FileImage(_profilePhotoFile!)
                  : (_profilePhotoUrl != null ? NetworkImage(_profilePhotoUrl!) : null) as ImageProvider?,
              child: _profilePhotoFile == null && _profilePhotoUrl == null
                  ? const Icon(Icons.camera_alt, size: 40, color: Colors.white38)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _OutlineBtn(
              icon: Icons.camera_alt,
              label: 'Camera',
              onTap: () async {
                final f = await _pickImage(ImageSource.camera);
                if (f != null) setState(() => _profilePhotoFile = f);
              },
            ),
            const SizedBox(width: 12),
            _OutlineBtn(
              icon: Icons.photo_library,
              label: 'Gallery',
              onTap: () async {
                final f = await _pickImage(ImageSource.gallery);
                if (f != null) setState(() => _profilePhotoFile = f);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Tip: Use a well-lit, forward-facing photo with no sunglasses.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Step 2: Service Type ──────────────────────────────────────────────────

  Widget _buildServiceType() {
    return _StepCard(
      title: 'Service Type',
      subtitle: 'Select the services you want to offer. You can update this later.',
      children: [
        _ServiceTile(
          icon: Icons.fastfood,
          title: 'Food Delivery',
          subtitle: 'Deliver orders from restaurants to customers.',
          selected: _serviceType == 'food_delivery',
          onTap: () => setState(() => _serviceType = 'food_delivery'),
        ),
        const SizedBox(height: 10),
        _ServiceTile(
          icon: Icons.directions_car,
          title: 'Ride Sharing',
          subtitle: 'Drive passengers to their destinations.',
          selected: _serviceType == 'ride_sharing',
          onTap: () => setState(() => _serviceType = 'ride_sharing'),
        ),
        const SizedBox(height: 10),
        _ServiceTile(
          icon: Icons.swap_horiz,
          title: 'Both Services',
          subtitle: 'Switch between food delivery and rides.',
          selected: _serviceType == 'both',
          onTap: () => setState(() => _serviceType = 'both'),
        ),
      ],
    );
  }

  // ── Step 3: Identity Document ─────────────────────────────────────────────

  Widget _buildIdentityDoc() {
    return _StepCard(
      title: 'Identity Document',
      subtitle: 'Upload a government-issued ID to verify your identity.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _docType,
          dropdownColor: _cardBg,
          style: const TextStyle(color: Colors.white),
          decoration: _darkDecoration('Document Type'),
          items: const [
            DropdownMenuItem(value: 'national_id', child: Text('National ID')),
            DropdownMenuItem(value: 'passport', child: Text('Passport')),
            DropdownMenuItem(value: 'driving_permit', child: Text('Driving Permit')),
            DropdownMenuItem(value: 'voters_id', child: Text("Voter's ID")),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: (v) { if (v != null) setState(() => _docType = v); },
        ),
        const SizedBox(height: 12),
        _DarkField(label: 'Document Number', controller: _docNumber),
        const SizedBox(height: 12),
        _DatePickerTile(
          label: 'Expiry Date (if applicable)',
          value: _idExpiry,
          onTap: () => _pickDate(
            current: _idExpiry,
            mustBeFuture: true,
            onPicked: (d) => setState(() => _idExpiry = d),
          ),
        ),
        const SizedBox(height: 16),
        _PhotoUploadRow(
          label: 'Front of Document',
          file: _idFrontFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _idFrontFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _idFrontFile = f); },
        ),
        const SizedBox(height: 12),
        _PhotoUploadRow(
          label: 'Back of Document',
          file: _idBackFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _idBackFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _idBackFile = f); },
        ),
      ],
    );
  }

  // ── Step 4: Driver's License ──────────────────────────────────────────────

  Widget _buildLicense() {
    return _StepCard(
      title: "Driver's License",
      subtitle: "Upload a valid driver's license to operate as a driver.",
      children: [
        _DarkField(label: 'License Number', controller: _licenseNumber),
        const SizedBox(height: 12),
        _DarkField(label: 'License Class / Category', controller: _licenseClass),
        const SizedBox(height: 12),
        _DatePickerTile(
          label: 'Expiry Date',
          value: _licenseExpiry,
          onTap: () => _pickDate(
            current: _licenseExpiry,
            mustBeFuture: true,
            onPicked: (d) => setState(() => _licenseExpiry = d),
          ),
        ),
        const SizedBox(height: 16),
        _PhotoUploadRow(
          label: 'Front of License',
          file: _licenseFrontFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _licenseFrontFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _licenseFrontFile = f); },
        ),
        const SizedBox(height: 12),
        _PhotoUploadRow(
          label: 'Back of License',
          file: _licenseBackFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _licenseBackFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _licenseBackFile = f); },
        ),
      ],
    );
  }

  // ── Step 5: Vehicle ───────────────────────────────────────────────────────

  Widget _buildVehicle() {
    return _StepCard(
      title: 'Vehicle Information',
      subtitle: 'Details about the vehicle you will use for deliveries.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _vehicleType,
          dropdownColor: _cardBg,
          style: const TextStyle(color: Colors.white),
          decoration: _darkDecoration('Vehicle Type *'),
          items: const [
            DropdownMenuItem(value: 'bicycle', child: Text('Bicycle')),
            DropdownMenuItem(value: 'motorcycle', child: Text('Motorcycle')),
            DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
            DropdownMenuItem(value: 'car', child: Text('Car')),
            DropdownMenuItem(value: 'van', child: Text('Van')),
            DropdownMenuItem(value: 'truck', child: Text('Truck')),
          ],
          onChanged: (v) { if (v != null) setState(() => _vehicleType = v); },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _DarkField(label: 'Make', controller: _vehicleMake)),
            const SizedBox(width: 10),
            Expanded(child: _DarkField(label: 'Model', controller: _vehicleModel)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DarkField(
                label: 'Year',
                controller: _vehicleYear,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _DarkField(label: 'Color', controller: _vehicleColor)),
          ],
        ),
        const SizedBox(height: 12),
        _DarkField(label: 'License Plate / Registration Number', controller: _licensePlate),
        const SizedBox(height: 16),
        _PhotoUploadRow(
          label: 'Vehicle Registration Document',
          file: _vehicleRegFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _vehicleRegFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _vehicleRegFile = f); },
        ),
      ],
    );
  }

  // ── Step 6: Insurance ─────────────────────────────────────────────────────

  Widget _buildInsurance() {
    return _StepCard(
      title: 'Vehicle Insurance',
      subtitle: 'Proof of insurance is required to drive on our platform.',
      children: [
        _DarkField(label: 'Insurance Provider', controller: _insuranceProvider),
        const SizedBox(height: 12),
        _DarkField(label: 'Policy Number', controller: _policyNumber),
        const SizedBox(height: 12),
        _DatePickerTile(
          label: 'Policy Expiry Date',
          value: _insuranceExpiry,
          onTap: () => _pickDate(
            current: _insuranceExpiry,
            mustBeFuture: true,
            onPicked: (d) => setState(() => _insuranceExpiry = d),
          ),
        ),
        const SizedBox(height: 16),
        _PhotoUploadRow(
          label: 'Insurance Certificate',
          file: _insuranceDocFile,
          onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _insuranceDocFile = f); },
          onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _insuranceDocFile = f); },
        ),
      ],
    );
  }

  // ── Step 7: Consents ──────────────────────────────────────────────────────

  Widget _buildConsents() {
    return _StepCard(
      title: 'Agreements & Consents',
      subtitle: 'Please review and accept the following to complete your application.',
      children: [
        _ConsentTile(
          label: 'I agree to the Terms of Service *',
          value: _consentTerms,
          onChanged: (v) => setState(() => _consentTerms = v ?? false),
        ),
        _ConsentTile(
          label: 'I agree to the Privacy Policy *',
          value: _consentPrivacy,
          onChanged: (v) => setState(() => _consentPrivacy = v ?? false),
        ),
        _ConsentTile(
          label: 'I consent to a background check *',
          value: _consentBackgroundCheck,
          onChanged: (v) => setState(() => _consentBackgroundCheck = v ?? false),
        ),
        _ConsentTile(
          label: 'I consent to data sharing with delivery partners (optional)',
          value: _consentDataSharing,
          onChanged: (v) => setState(() => _consentDataSharing = v ?? false),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.1),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: _accent, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your application will be reviewed within 1-3 business days. '
                  'You will be notified once approved.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _darkDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: _bg,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _accent),
    ),
  );
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      color: const Color(0xFF1C1F2E),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (currentStep + 1) / totalSteps,
        child: Container(color: const Color(0xFF6C63FF)),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _StepCard({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 24),
        ...children,
        const SizedBox(height: 20),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool loading;
  final bool isLastStep;
  final VoidCallback onNext;
  const _BottomBar({required this.loading, required this.isLastStep, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F2E),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: loading ? null : onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  isLastStep ? 'Submit Application' : 'Save & Continue',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int? maxLines;
  final List<TextInputFormatter>? inputFormatters;

  const _DarkField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    inputFormatters: inputFormatters,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF0F1117),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
    ),
  );
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DatePickerTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          Text(
            value == null ? label : '${value!.month.toString().padLeft(2, '0')}/${value!.day.toString().padLeft(2, '0')}/${value!.year}',
            style: TextStyle(color: value == null ? Colors.white38 : Colors.white, fontSize: 15),
          ),
        ],
      ),
    ),
  );
}

class _PhotoUploadRow extends StatelessWidget {
  final String label;
  final File? file;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _PhotoUploadRow({required this.label, required this.file, required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(file!, height: 120, width: double.infinity, fit: BoxFit.cover),
          ),
        if (file != null) const SizedBox(height: 8),
        Row(
          children: [
            _OutlineBtn(icon: Icons.camera_alt, label: file != null ? 'Retake' : 'Camera', onTap: onCamera),
            const SizedBox(width: 10),
            _OutlineBtn(icon: Icons.photo_library, label: file != null ? 'Replace' : 'Gallery', onTap: onGallery),
          ],
        ),
      ],
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16, color: const Color(0xFF6C63FF)),
    label: Text(label, style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 13)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Color(0xFF6C63FF)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ServiceTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF6C63FF).withValues(alpha: 0.15) : const Color(0xFF1C1F2E),
        border: Border.all(color: selected ? const Color(0xFF6C63FF) : Colors.white12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF6C63FF) : Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (selected) const Icon(Icons.check_circle, color: Color(0xFF6C63FF)),
        ],
      ),
    ),
  );
}

class _ConsentTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _ConsentTile({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    value: value,
    onChanged: onChanged,
    checkColor: Colors.white,
    activeColor: const Color(0xFF6C63FF),
    controlAffinity: ListTileControlAffinity.leading,
  );
}
