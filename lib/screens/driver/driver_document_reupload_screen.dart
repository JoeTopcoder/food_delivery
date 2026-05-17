import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/driver/driver_service.dart';
import '../../config/supabase_config.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';
import '../../utils/safe_state_mixin.dart';

/// Shown after a rejection — lets the driver re-upload specific documents
/// without restarting the entire 8-step flow.
class DriverDocumentReuploadScreen extends ConsumerStatefulWidget {
  final Driver driver;
  const DriverDocumentReuploadScreen({super.key, required this.driver});

  @override
  ConsumerState<DriverDocumentReuploadScreen> createState() =>
      _DriverDocumentReuploadScreenState();
}

class _DriverDocumentReuploadScreenState
    extends ConsumerState<DriverDocumentReuploadScreen>
    with SafeConsumerStateMixin<DriverDocumentReuploadScreen> {
  static const _bg = Color(0xFF0F1117);
  static const _accent = Color(0xFF6C63FF);

  final _picker = ImagePicker();
  bool _loading = false;
  String? _uploadingLabel;

  // ID Document
  File? _idFrontFile;
  File? _idBackFile;

  // License
  File? _licenseFrontFile;
  File? _licenseBackFile;

  // Vehicle Registration
  File? _vehicleRegFile;

  // Insurance
  File? _insuranceDocFile;

  DriverService get _svc => ref.read(driverServiceProvider);

  Future<File?> _pickImage(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
    if (x == null) return null;
    return File(x.path);
  }

  Future<String?> _upload(File file, String folder, String name) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final path = '${widget.driver.id}/$folder/$name.$ext';
      await SupabaseConfig.client.storage
          .from('driver-documents')
          .uploadBinary(path, bytes, fileOptions: FileOptions(upsert: true));
      return SupabaseConfig.client.storage.from('driver-documents').getPublicUrl(path);
    } catch (e) {
      AppLogger.error('Upload failed [$folder/$name]: $e');
      return null;
    }
  }

  Future<void> _submitReupload() async {
    setState(() { _loading = true; _uploadingLabel = null; });
    try {
      final driverId = widget.driver.id;
      bool uploaded = false;

      if (_idFrontFile != null || _idBackFile != null) {
        setState(() => _uploadingLabel = 'Uploading identity document…');
        final front = _idFrontFile != null ? await _upload(_idFrontFile!, 'identity', 'front') : null;
        final back = _idBackFile != null ? await _upload(_idBackFile!, 'identity', 'back') : null;
        await _svc.saveIdentityDocument(
          driverId: driverId,
          documentType: 'national_id',
          frontPhotoUrl: front,
          backPhotoUrl: back,
        );
        uploaded = true;
      }

      if (_licenseFrontFile != null || _licenseBackFile != null) {
        setState(() => _uploadingLabel = "Uploading driver's license…");
        final front = _licenseFrontFile != null ? await _upload(_licenseFrontFile!, 'license', 'front') : null;
        final back = _licenseBackFile != null ? await _upload(_licenseBackFile!, 'license', 'back') : null;
        await _svc.saveDriverLicense(driverId: driverId, frontPhotoUrl: front, backPhotoUrl: back);
        uploaded = true;
      }

      if (_vehicleRegFile != null) {
        setState(() => _uploadingLabel = 'Uploading vehicle registration…');
        final url = await _upload(_vehicleRegFile!, 'vehicle', 'registration');
        await _svc.saveVehicle(driverId: driverId, vehicleType: widget.driver.vehicleType ?? 'motorcycle', registrationPhotoUrl: url);
        uploaded = true;
      }

      if (_insuranceDocFile != null) {
        setState(() => _uploadingLabel = 'Uploading insurance certificate…');
        final url = await _upload(_insuranceDocFile!, 'insurance', 'policy');
        await _svc.saveInsurance(driverId: driverId, documentPhotoUrl: url);
        uploaded = true;
      }

      if (!uploaded) {
        if (mounted) AppSnackbar.error(context, 'Please upload at least one document.');
        return;
      }

      // Re-submit the application
      setState(() => _uploadingLabel = 'Submitting application…');
      await _svc.submitApplication(driverId);

      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(driverProfileProvider(userId));

      if (!mounted) return;
      AppSnackbar.success(context, 'Documents re-submitted for review.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() { _loading = false; _uploadingLabel = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Re-upload Documents', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.driver.rejectionReason != null) ...[
              _RejectionBanner(reason: widget.driver.rejectionReason!),
              const SizedBox(height: 20),
            ],
            const Text(
              'Upload only the documents that were flagged. Unchanged documents do not need to be re-uploaded.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),

            _DocSection(
              title: 'Identity Document',
              children: [
                _PhotoRow(label: 'Front', file: _idFrontFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _idFrontFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _idFrontFile = f); }),
                const SizedBox(height: 10),
                _PhotoRow(label: 'Back', file: _idBackFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _idBackFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _idBackFile = f); }),
              ],
            ),
            const SizedBox(height: 20),

            _DocSection(
              title: "Driver's License",
              children: [
                _PhotoRow(label: 'Front', file: _licenseFrontFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _licenseFrontFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _licenseFrontFile = f); }),
                const SizedBox(height: 10),
                _PhotoRow(label: 'Back', file: _licenseBackFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _licenseBackFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _licenseBackFile = f); }),
              ],
            ),
            const SizedBox(height: 20),

            _DocSection(
              title: 'Vehicle Registration',
              children: [
                _PhotoRow(label: 'Registration Doc', file: _vehicleRegFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _vehicleRegFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _vehicleRegFile = f); }),
              ],
            ),
            const SizedBox(height: 20),

            _DocSection(
              title: 'Insurance Certificate',
              children: [
                _PhotoRow(label: 'Insurance Doc', file: _insuranceDocFile, onCamera: () async { final f = await _pickImage(ImageSource.camera); if (f != null) setState(() => _insuranceDocFile = f); }, onGallery: () async { final f = await _pickImage(ImageSource.gallery); if (f != null) setState(() => _insuranceDocFile = f); }),
              ],
            ),
            const SizedBox(height: 32),

            if (_loading && _uploadingLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
                    const SizedBox(width: 10),
                    Text(_uploadingLabel!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submitReupload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit for Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _RejectionBanner extends StatelessWidget {
  final String reason;
  const _RejectionBanner({required this.reason});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.redAccent.withValues(alpha: 0.1),
      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text('Rejection Reason', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(reason, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    ),
  );
}

class _DocSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DocSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1F2E),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final File? file;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _PhotoRow({required this.label, required this.file, required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 6),
      if (file != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file!, height: 100, width: double.infinity, fit: BoxFit.cover),
        ),
        const SizedBox(height: 6),
      ],
      Row(
        children: [
          _Btn(icon: Icons.camera_alt, label: file != null ? 'Retake' : 'Camera', onTap: onCamera),
          const SizedBox(width: 10),
          _Btn(icon: Icons.photo_library, label: file != null ? 'Replace' : 'Gallery', onTap: onGallery),
        ],
      ),
    ],
  );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 15, color: const Color(0xFF6C63FF)),
    label: Text(label, style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Color(0xFF6C63FF)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}
