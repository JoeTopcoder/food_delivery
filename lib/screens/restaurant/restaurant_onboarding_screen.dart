import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../config/supabase_config.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/food/restaurant_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';

// ── Colour tokens ──────────────────────────────────────────────────────────────
const _bg      = Color(0xFF0F1117);
const _cardBg  = Color(0xFF1C1F2E);
const _accent  = Color(0xFFFF6B35);   // orange — restaurant brand colour
const _steps   = 7;

class RestaurantVerificationScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;
  const RestaurantVerificationScreen({super.key, required this.restaurant});

  @override
  ConsumerState<RestaurantVerificationScreen> createState() =>
      _RestaurantVerificationScreenState();
}

class _RestaurantVerificationScreenState
    extends ConsumerState<RestaurantVerificationScreen> {

  late int _currentStep;
  bool _loading = false;
  final _picker = ImagePicker();

  // Step 0 — Business Info
  final _name        = TextEditingController();
  final _description = TextEditingController();
  final _phone       = TextEditingController();
  final _email       = TextEditingController();
  String _cuisineType = 'Fast Food';

  static const _cuisines = [
    'Fast Food', 'African', 'Chinese', 'Indian', 'Italian', 'Pizza',
    'Burgers', 'Chicken', 'Seafood', 'Vegetarian', 'Vegan', 'Sushi',
    'Mexican', 'Lebanese', 'Continental', 'Bakery', 'Desserts', 'Drinks', 'Other',
  ];

  // Step 1 — Restaurant Photo
  String? _photoUrl;
  File?   _photoFile;

  // Step 2 — Store Type
  String _storeType = 'food';

  // Step 3 — Location & Delivery
  final _address              = TextEditingController();
  final _deliveryFee          = TextEditingController();
  final _estimatedDeliveryMin = TextEditingController();

  // Step 4 — Operating Hours
  final _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  final _dayLabels = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  late Map<String, Map<String, dynamic>> _hours;

  // Step 5 — Business Documents
  final _bizRegNumber  = TextEditingController();
  final _healthNumber  = TextEditingController();
  final _foodNumber    = TextEditingController();
  File?   _bizRegFile;
  File?   _healthFile;
  File?   _foodFile;
  String? _bizRegUrl;
  String? _healthUrl;
  String? _foodUrl;
  DateTime? _bizRegExpiry;
  DateTime? _healthExpiry;
  DateTime? _foodExpiry;

  // Step 6 — Terms
  bool _consentTerms       = false;
  bool _consentPrivacy     = false;
  bool _consentCommission  = false;

  RestaurantService get _svc => ref.read(restaurantServiceProvider);

  @override
  void initState() {
    super.initState();
    _currentStep = widget.restaurant.onboardingStep.clamp(0, _steps - 1);
    _name.text        = widget.restaurant.name;
    _description.text = widget.restaurant.description ?? '';
    _phone.text       = widget.restaurant.phone ?? '';
    _email.text       = widget.restaurant.email ?? '';
    if (widget.restaurant.cuisineType != null &&
        _cuisines.contains(widget.restaurant.cuisineType)) {
      _cuisineType = widget.restaurant.cuisineType!;
    }
    _photoUrl  = widget.restaurant.imageUrl;
    _storeType = widget.restaurant.storeType;
    _address.text = widget.restaurant.address ?? '';
    _deliveryFee.text = widget.restaurant.deliveryFee?.toStringAsFixed(0) ?? '';
    _estimatedDeliveryMin.text =
        widget.restaurant.estimatedDeliveryTime?.toString() ?? '30';

    // Init operating hours
    final existing = widget.restaurant.operatingHours;
    _hours = {
      for (final d in _days)
        d: (existing?[d] as Map?)?.cast<String, dynamic>() ??
            {'open': '08:00', 'close': '22:00', 'is_open': true},
    };
  }

  @override
  void dispose() {
    _name.dispose(); _description.dispose(); _phone.dispose(); _email.dispose();
    _address.dispose(); _deliveryFee.dispose(); _estimatedDeliveryMin.dispose();
    _bizRegNumber.dispose(); _healthNumber.dispose(); _foodNumber.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Future<String?> _uploadFile(File file, String subfolder) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final path  = '${widget.restaurant.id}/$subfolder/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await SupabaseConfig.client.storage
          .from('restaurant-documents')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      return SupabaseConfig.client.storage
          .from('restaurant-documents')
          .getPublicUrl(path);
    } catch (e) {
      AppLogger.error('Upload failed ($subfolder): $e');
      return null;
    }
  }

  Future<String?> _uploadPhoto(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final path  = '${widget.restaurant.id}/cover.$ext';
      await SupabaseConfig.client.storage
          .from('restaurant-photos')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      return SupabaseConfig.client.storage
          .from('restaurant-photos')
          .getPublicUrl(path);
    } catch (e) {
      AppLogger.error('Cover photo upload failed: $e');
      return null;
    }
  }

  Future<File?> _pick({ImageSource source = ImageSource.gallery}) async {
    final x = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
    if (x == null) return null;
    return File(x.path);
  }

  Future<void> _pickSource(void Function(File) onPicked) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _cardBg,
      builder: (_) => SafeArea(
        child: Wrap(children: [
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
        ]),
      ),
    );
    if (src == null) return;
    final f = await _pick(source: src);
    if (f != null) onPicked(f);
  }

  Future<void> _pickDate({
    required DateTime? current,
    required void Function(DateTime) onPicked,
  }) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent, surface: _cardBg),
        ),
        child: child!,
      ),
    );
    if (d != null) onPicked(d);
  }

  Future<void> _pickTime(String day, String field) async {
    final current = _hours[day]![field] as String? ?? '08:00';
    final parts   = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent, surface: _cardBg),
        ),
        child: child!,
      ),
    );
    if (t != null) {
      setState(() {
        _hours[day]![field] =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  // ── Step navigation ───────────────────────────────────────────────────────────

  Future<void> _nextStep() async {
    setState(() => _loading = true);
    try {
      await _saveStep(_currentStep);
      if (_currentStep < _steps - 1) {
        setState(() => _currentStep++);
      } else {
        await _submit();
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

  Future<void> _saveStep(int step) async {
    final id = widget.restaurant.id;
    switch (step) {
      case 0:
        if (_name.text.trim().isEmpty) throw Exception('Restaurant name is required.');
        await _svc.updateOnboardingStep(
          restaurantId: id,
          step: 1,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          cuisineType: _cuisineType,
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        );

      case 1:
        if (_photoFile != null) {
          _photoUrl = await _uploadPhoto(_photoFile!);
        }
        await _svc.updateOnboardingStep(
          restaurantId: id, step: 2, imageUrl: _photoUrl,
        );

      case 2:
        await _svc.updateOnboardingStep(
          restaurantId: id, step: 3, storeType: _storeType,
        );

      case 3:
        if (_address.text.trim().isEmpty) throw Exception('Address is required.');
        await _svc.updateOnboardingStep(
          restaurantId: id,
          step: 4,
          address: _address.text.trim(),
          deliveryFee: double.tryParse(_deliveryFee.text),
          estimatedDeliveryTime: int.tryParse(_estimatedDeliveryMin.text),
        );

      case 4:
        await _svc.updateOnboardingStep(
          restaurantId: id, step: 5, operatingHours: Map.from(_hours),
        );

      case 5:
        if (_bizRegFile != null) {
          _bizRegUrl = await _uploadFile(_bizRegFile!, 'business_registration');
        }
        if (_healthFile != null) {
          _healthUrl = await _uploadFile(_healthFile!, 'health_permit');
        }
        if (_foodFile != null) {
          _foodUrl = await _uploadFile(_foodFile!, 'food_permit');
        }
        if (_bizRegUrl != null || _bizRegNumber.text.isNotEmpty) {
          await _svc.saveRestaurantDocument(
            restaurantId: id,
            documentType: 'business_registration',
            documentNumber: _bizRegNumber.text.trim().isEmpty ? null : _bizRegNumber.text.trim(),
            photoUrl: _bizRegUrl,
            expiryDate: _bizRegExpiry,
          );
        }
        if (_healthUrl != null || _healthNumber.text.isNotEmpty) {
          await _svc.saveRestaurantDocument(
            restaurantId: id,
            documentType: 'health_permit',
            documentNumber: _healthNumber.text.trim().isEmpty ? null : _healthNumber.text.trim(),
            photoUrl: _healthUrl,
            expiryDate: _healthExpiry,
          );
        }
        if (_foodUrl != null || _foodNumber.text.isNotEmpty) {
          await _svc.saveRestaurantDocument(
            restaurantId: id,
            documentType: 'food_permit',
            documentNumber: _foodNumber.text.trim().isEmpty ? null : _foodNumber.text.trim(),
            photoUrl: _foodUrl,
            expiryDate: _foodExpiry,
          );
        }
        await _svc.updateOnboardingStep(restaurantId: id, step: 6);

      case 6:
        if (!_consentTerms)      throw Exception('You must accept the Terms of Service.');
        if (!_consentPrivacy)    throw Exception('You must accept the Privacy Policy.');
        if (!_consentCommission) throw Exception('You must accept the Commission Agreement.');
    }
  }

  Future<void> _submit() async {
    await _svc.submitApplication(widget.restaurant.id);
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId != null) ref.invalidate(restaurantByOwnerProvider(ownerId));
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/restaurant-dashboard', (_) => false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(step: _currentStep, totalSteps: _steps, onBack: _currentStep > 0 ? _prevStep : null),
            _ProgressBar(step: _currentStep, totalSteps: _steps),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                child: _buildStep(_currentStep),
              ),
            ),
            _BottomBar(
              step: _currentStep,
              totalSteps: _steps,
              loading: _loading,
              onNext: _nextStep,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int step) {
    switch (step) {
      case 0: return _buildBusinessInfo();
      case 1: return _buildPhoto();
      case 2: return _buildStoreType();
      case 3: return _buildLocation();
      case 4: return _buildHours();
      case 5: return _buildDocuments();
      case 6: return _buildTerms();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 0: Business Info ──────────────────────────────────────────────────

  Widget _buildBusinessInfo() {
    return _StepShell(
      icon: Icons.storefront_rounded,
      title: 'Business Information',
      subtitle: 'Tell us about your restaurant',
      child: Column(
        children: [
          _Field(ctrl: _name,        label: 'Restaurant Name *', hint: 'e.g. Joe\'s Kitchen',   icon: Icons.store_rounded),
          const SizedBox(height: 14),
          _Field(ctrl: _description, label: 'Description',       hint: 'What makes you special?', icon: Icons.notes_rounded, maxLines: 3),
          const SizedBox(height: 14),
          _Dropdown(
            label: 'Cuisine Type',
            value: _cuisineType,
            items: _cuisines,
            onChanged: (v) => setState(() => _cuisineType = v!),
          ),
          const SizedBox(height: 14),
          _Field(ctrl: _phone, label: 'Phone Number', hint: '+1 555 000 0000', icon: Icons.phone_rounded,
              keyboard: TextInputType.phone),
          const SizedBox(height: 14),
          _Field(ctrl: _email, label: 'Email Address', hint: 'restaurant@email.com', icon: Icons.email_rounded,
              keyboard: TextInputType.emailAddress),
        ],
      ),
    );
  }

  // ── Step 1: Photo ──────────────────────────────────────────────────────────

  Widget _buildPhoto() {
    return _StepShell(
      icon: Icons.add_a_photo_rounded,
      title: 'Restaurant Photo',
      subtitle: 'Upload a cover photo that customers will see',
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _pickSource((f) => setState(() => _photoFile = f)),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: (_photoFile != null || _photoUrl != null)
                    ? _accent.withValues(alpha: 0.5)
                    : Colors.white12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoFile != null
                  ? Image.file(_photoFile!, fit: BoxFit.cover)
                  : _photoUrl != null
                      ? Image.network(_photoUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _photoPlaceholder())
                      : _photoPlaceholder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Tap to upload from camera or gallery',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          const SizedBox(height: 8),
          Text('Recommended: 1200×800 px, JPG or PNG',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_rounded, color: Colors.white24, size: 48),
      const SizedBox(height: 12),
      Text('Tap to upload cover photo',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
    ],
  );

  // ── Step 2: Store Type ─────────────────────────────────────────────────────

  Widget _buildStoreType() {
    return _StepShell(
      icon: Icons.category_rounded,
      title: 'Store Type',
      subtitle: 'What type of products do you sell?',
      child: Column(
        children: [
          _TypeCard(
            icon: Icons.restaurant_rounded,
            label: 'Food Restaurant',
            desc: 'Cooked meals, fast food, and dining',
            selected: _storeType == 'food',
            onTap: () => setState(() => _storeType = 'food'),
          ),
          const SizedBox(height: 12),
          _TypeCard(
            icon: Icons.local_grocery_store_rounded,
            label: 'Grocery Store',
            desc: 'Fresh produce, packaged goods, essentials',
            selected: _storeType == 'grocery',
            onTap: () => setState(() => _storeType = 'grocery'),
          ),
          const SizedBox(height: 12),
          _TypeCard(
            icon: Icons.layers_rounded,
            label: 'Both',
            desc: 'Food restaurant with a grocery section',
            selected: _storeType == 'both',
            onTap: () => setState(() => _storeType = 'both'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Location ────────────────────────────────────────────────────────

  Widget _buildLocation() {
    return _StepShell(
      icon: Icons.location_on_rounded,
      title: 'Location & Delivery',
      subtitle: 'Where are you located and how do you deliver?',
      child: Column(
        children: [
          _Field(ctrl: _address, label: 'Full Address *', hint: '123 Main St, City, Country',
              icon: Icons.place_rounded, maxLines: 2),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Field(
                  ctrl: _deliveryFee,
                  label: 'Delivery Fee',
                  hint: '0.00',
                  icon: Icons.delivery_dining_rounded,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  ctrl: _estimatedDeliveryMin,
                  label: 'Est. Delivery (min)',
                  hint: '30',
                  icon: Icons.timer_rounded,
                  keyboard: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 4: Operating Hours ─────────────────────────────────────────────────

  Widget _buildHours() {
    return _StepShell(
      icon: Icons.schedule_rounded,
      title: 'Operating Hours',
      subtitle: 'Set your open/close times for each day',
      child: Column(
        children: [
          for (int i = 0; i < _days.length; i++)
            _DayRow(
              label: _dayLabels[i],
              data: _hours[_days[i]]!,
              onToggle: (v) => setState(() => _hours[_days[i]]!['is_open'] = v),
              onOpenTap:  () => _pickTime(_days[i], 'open'),
              onCloseTap: () => _pickTime(_days[i], 'close'),
            ),
        ],
      ),
    );
  }

  // ── Step 5: Documents ──────────────────────────────────────────────────────

  Widget _buildDocuments() {
    return _StepShell(
      icon: Icons.description_rounded,
      title: 'Business Documents',
      subtitle: 'Upload your permits and certificates for verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DocSection(
            title: 'Business Registration',
            icon: Icons.business_rounded,
            numberCtrl: _bizRegNumber,
            numberHint: 'Registration number',
            file: _bizRegFile,
            expiry: _bizRegExpiry,
            onPickFile: () => _pickSource((f) => setState(() => _bizRegFile = f)),
            onPickExpiry: () => _pickDate(current: _bizRegExpiry, onPicked: (d) => setState(() => _bizRegExpiry = d)),
          ),
          const SizedBox(height: 16),
          _DocSection(
            title: 'Health / Sanitation Permit',
            icon: Icons.health_and_safety_rounded,
            numberCtrl: _healthNumber,
            numberHint: 'Permit number',
            file: _healthFile,
            expiry: _healthExpiry,
            onPickFile: () => _pickSource((f) => setState(() => _healthFile = f)),
            onPickExpiry: () => _pickDate(current: _healthExpiry, onPicked: (d) => setState(() => _healthExpiry = d)),
          ),
          const SizedBox(height: 16),
          _DocSection(
            title: 'Food Handling Permit',
            icon: Icons.restaurant_menu_rounded,
            numberCtrl: _foodNumber,
            numberHint: 'Permit number',
            file: _foodFile,
            expiry: _foodExpiry,
            onPickFile: () => _pickSource((f) => setState(() => _foodFile = f)),
            onPickExpiry: () => _pickDate(current: _foodExpiry, onPicked: (d) => setState(() => _foodExpiry = d)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'You can skip documents now and upload them later from your profile.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 6: Terms ──────────────────────────────────────────────────────────

  Widget _buildTerms() {
    return _StepShell(
      icon: Icons.handshake_rounded,
      title: 'Agreements',
      subtitle: 'Please read and accept the following before submitting',
      child: Column(
        children: [
          _ConsentTile(
            value: _consentTerms,
            title: 'Terms of Service',
            desc: 'I agree to the platform terms of service and usage policies.',
            onChanged: (v) => setState(() => _consentTerms = v),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            value: _consentPrivacy,
            title: 'Privacy Policy',
            desc: 'I consent to the collection and use of my data as described in the privacy policy.',
            onChanged: (v) => setState(() => _consentPrivacy = v),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            value: _consentCommission,
            title: 'Commission Agreement',
            desc: 'I understand and agree to the commission structure applicable to my restaurant.',
            onChanged: (v) => setState(() => _consentCommission = v),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'After submitting, our team will review your application within 24-48 hours. '
                    'You will be notified once approved.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;

  const _TopBar({required this.step, required this.totalSteps, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
            onPressed: onBack ?? () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'Step ${step + 1} of $totalSteps',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  const _ProgressBar({required this.step, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / totalSteps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(_accent),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool loading;
  final VoidCallback onNext;

  const _BottomBar({
    required this.step,
    required this.totalSteps,
    required this.loading,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: loading ? null : onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _accent.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  isLast ? 'Submit Application' : 'Continue',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _StepShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboard,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: _cardBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2D3E))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2D3E))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        dropdownColor: _cardBg,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.category_rounded, color: _accent, size: 20),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon, required this.label, required this.desc,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.12) : _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _accent : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: (selected ? _accent : Colors.white).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: selected ? _accent : Colors.white54, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(
                      color: selected ? _accent : Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _accent, size: 22),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final String label;
  final Map<String, dynamic> data;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenTap;
  final VoidCallback onCloseTap;

  const _DayRow({
    required this.label, required this.data,
    required this.onToggle, required this.onOpenTap, required this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = data['is_open'] as bool? ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Switch(
            value: isOpen,
            onChanged: onToggle,
            activeThumbColor: _accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          if (isOpen) ...[
            Expanded(
              child: GestureDetector(
                onTap: onOpenTap,
                child: _TimeChip(label: data['open'] as String? ?? '08:00'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('–', style: TextStyle(color: Colors.white54)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onCloseTap,
                child: _TimeChip(label: data['close'] as String? ?? '22:00'),
              ),
            ),
          ] else
            const Expanded(
              child: Text('Closed', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  const _TimeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class _DocSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final TextEditingController numberCtrl;
  final String numberHint;
  final File? file;
  final DateTime? expiry;
  final VoidCallback onPickFile;
  final VoidCallback onPickExpiry;

  const _DocSection({
    required this.title, required this.icon, required this.numberCtrl,
    required this.numberHint, required this.file, required this.expiry,
    required this.onPickFile, required this.onPickExpiry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: numberCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: numberHint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF13151F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2A2D3E))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2A2D3E))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onPickFile,
                  child: Container(
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: file != null ? _accent.withValues(alpha: 0.5) : Colors.white12,
                        width: file != null ? 1.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: file != null
                        ? Stack(fit: StackFit.expand, children: [
                            Image.file(file!, fit: BoxFit.cover),
                            Positioned(
                              top: 5, right: 5,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                                child: const Icon(Icons.check_rounded, color: Colors.white, size: 11),
                              ),
                            ),
                          ])
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.upload_file_rounded, color: Colors.white24, size: 26),
                              const SizedBox(height: 6),
                              Text('Upload Document',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onPickExpiry,
                  child: Container(
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: expiry != null ? _accent.withValues(alpha: 0.4) : Colors.white12,
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_rounded, color: expiry != null ? _accent : Colors.white24, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          expiry != null
                              ? '${expiry!.day}/${expiry!.month}/${expiry!.year}'
                              : 'Expiry Date',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: expiry != null ? _accent : Colors.white24,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool value;
  final String title;
  final String desc;
  final ValueChanged<bool> onChanged;

  const _ConsentTile({
    required this.value, required this.title, required this.desc, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? _accent.withValues(alpha: 0.08) : _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value ? _accent.withValues(alpha: 0.4) : Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: value ? _accent : Colors.white38,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                      color: value ? _accent : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
