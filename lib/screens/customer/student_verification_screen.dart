import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/student_verification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_verification_provider.dart';
import '../../services/student_id_ocr_service.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

/// Register + verify a student ID. OCR runs on-device; the approval decision
/// is made server-side by finalize_student_verification.
class StudentVerificationScreen extends ConsumerStatefulWidget {
  /// The student being verified. Defaults to the signed-in user (self-verify);
  /// a parent can pass a linked student's id.
  final String? studentUserId;
  const StudentVerificationScreen({super.key, this.studentUserId});

  @override
  ConsumerState<StudentVerificationScreen> createState() =>
      _StudentVerificationScreenState();
}

class _StudentVerificationScreenState
    extends ConsumerState<StudentVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  String? _schoolId;
  File? _idImage;
  bool _busy = false;
  String _stage = '';
  bool _prefilled = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  String get _studentId =>
      widget.studentUserId ?? ref.read(currentUserIdProvider) ?? '';

  Future<void> _pickId(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (picked != null) setState(() => _idImage = File(picked.path));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    if (_schoolId == null) {
      AppSnackbar.error(context, 'Please select a school');
      return;
    }
    if (_idImage == null) {
      AppSnackbar.error(context, 'Please add a photo of the student ID');
      return;
    }
    final svc = ref.read(studentVerificationServiceProvider);
    final ocr = ref.read(studentIdOcrServiceProvider);
    setState(() {
      _busy = true;
      _stage = 'Uploading ID…';
    });
    try {
      final path = await svc.uploadIdImage(_studentId, _idImage!);
      setState(() => _stage = 'Submitting…');
      final verId = await svc.submit(
        studentId: _studentId,
        studentName: _nameCtrl.text.trim(),
        studentIdNumber: _idCtrl.text.trim(),
        schoolId: _schoolId!,
        idImagePath: path,
      );
      setState(() => _stage = 'Reading the ID…');
      final StudentIdOcrResult result = await ocr.recognize(_idImage!.path);
      setState(() => _stage = 'Checking details…');
      final verification = await svc.finalize(verId, result);

      ref.invalidate(myVerificationProvider(_studentId));
      ref.invalidate(studentBenefitsActiveProvider(_studentId));
      if (!mounted) return;
      _showOutcome(verification);
    } on StudentIdOcrException catch (e) {
      // The row is 'processing'; the student can retry with a clearer photo.
      ref.invalidate(myVerificationProvider(_studentId));
      if (mounted) AppSnackbar.warning(context, e.message);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() { _busy = false; _stage = ''; });
    }
  }

  void _showOutcome(StudentVerification v) {
    final approved = v.isApproved;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(approved ? 'Student ID verified' : v.statusLabel),
        content: Text(
          approved
              ? 'Student ID verified based on the submitted information and OCR '
                  'validation. Your student benefits are now active.'
              : (v.rejectionReason ??
                  v.reviewReason ??
                  'We could not verify this ID automatically. '
                      'Please check the details and try again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = _studentId;
    final verAsync = ref.watch(myVerificationProvider(userId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Student Verification',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            verAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => AppErrorState(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(myVerificationProvider(userId)),
              ),
              data: (v) {
                if (!_prefilled && v != null) {
                  _nameCtrl.text = v.studentName ?? '';
                  _idCtrl.text = v.studentIdNumber ?? '';
                  _schoolId ??= v.schoolId;
                  _prefilled = true;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (v != null) _StatusCard(v: v),
                    if (v == null || v.canReupload || !v.isApproved)
                      _buildForm(v),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(StudentVerification? existing) {
    final schoolsAsync = ref.watch(activeSchoolsProvider);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            existing?.canReupload == true
                ? 'Update student ID'
                : 'Student information',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameCtrl,
            decoration: _decor('Full name *'),
            validator: (x) =>
                (x == null || x.trim().length < 2) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _idCtrl,
            decoration: _decor('Student ID number *'),
            validator: (x) =>
                (x == null || x.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          schoolsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(friendlyError(e),
                style: const TextStyle(color: Colors.red)),
            data: (schools) => DropdownButtonFormField<String>(
              initialValue: _schoolId,
              isExpanded: true,
              decoration: _decor('School *'),
              items: [
                for (final s in schools)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _schoolId = v),
              validator: (v) => v == null ? 'Select a school' : null,
            ),
          ),
          const SizedBox(height: 16),
          _idImagePicker(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(
                _busy ? _stage : 'Verify student ID',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your ID photo is stored privately and used only to verify your '
            'student status. Normal food & grocery ordering is never affected.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _idImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Student ID photo *',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _busy ? null : () => _pickId(ImageSource.camera),
          child: Container(
            height: 170,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            clipBehavior: Clip.antiAlias,
            child: _idImage != null
                ? Image.file(_idImage!, fit: BoxFit.contain)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.badge_outlined,
                          size: 40, color: Colors.grey[600]),
                      const SizedBox(height: 6),
                      Text('Tap to photograph the student ID',
                          style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickId(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickId(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _decor(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  final StudentVerification v;
  const _StatusCard({required this.v});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String msg) = switch (v.status) {
      'approved' => (
          const Color(0xFF067647),
          Icons.verified_rounded,
          v.expiresAt != null
              ? 'Verified. Student benefits active until '
                  '${v.expiresAt!.toLocal().toString().split(' ').first}.'
              : 'Verified. Student benefits are active.'
        ),
      'processing' || 'pending' => (
          const Color(0xFF0E7490),
          Icons.hourglass_top_rounded,
          'We are processing your student ID.'
        ),
      'manual_review' => (
          const Color(0xFF6941C6),
          Icons.gavel_rounded,
          'Your submission is under review by the company.'
        ),
      'needs_update' => (
          const Color(0xFFB54708),
          Icons.upload_file_rounded,
          v.rejectionReason ?? 'Please upload a clearer or current student ID.'
        ),
      'expired' => (
          const Color(0xFFB54708),
          Icons.event_busy_rounded,
          'Your student ID has expired. Upload a current ID to restore benefits.'
        ),
      'suspended' => (
          const Color(0xFFB42318),
          Icons.pause_circle_outline_rounded,
          'Student benefits are currently unavailable while a delivery issue is '
              'reviewed. Normal ordering still works.'
        ),
      'rejected' => (
          const Color(0xFFB42318),
          Icons.cancel_rounded,
          v.rejectionReason ?? 'This student ID could not be verified.'
        ),
      _ => (Colors.grey, Icons.info_outline, v.statusLabel),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.statusLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: color, fontSize: 15)),
                const SizedBox(height: 4),
                Text(msg,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
