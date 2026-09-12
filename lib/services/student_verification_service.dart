import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/student_verification_model.dart';
import '../utils/app_logger.dart';
import 'student_id_ocr_service.dart';

/// Student-ID verification: schools, submit/finalize, storage, driver
/// confirmation, and admin review. All privileged writes go through the
/// SECURITY DEFINER RPCs — this never sets status/benefits directly.
class StudentVerificationService {
  final SupabaseClient _client;
  StudentVerificationService(this._client);

  static const _bucket = 'student-ids';

  // ── Schools ────────────────────────────────────────────────────────────────
  Future<List<SchoolOption>> getActiveSchools() async {
    final rows = await _client
        .from('schools')
        .select('id, name, address, is_active')
        .eq('is_active', true)
        .order('name');
    return (rows as List)
        .map((r) => SchoolOption.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SchoolOption>> getAllSchools() async {
    final rows = await _client
        .from('schools')
        .select('id, name, address, is_active')
        .order('name');
    return (rows as List)
        .map((r) => SchoolOption.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> addSchool({
    required String name,
    String? address,
    String? code,
    bool active = true,
  }) async {
    await _client.from('schools').insert({
      'name': name,
      'address': address ?? '',
      'school_code': code,
      'is_active': active,
    });
  }

  Future<void> setSchoolActive(String schoolId, bool active) async {
    await _client
        .from('schools')
        .update({'is_active': active, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', schoolId);
  }

  // ── Verification reads ───────────────────────────────────────────────────────
  Future<StudentVerification?> latestVerification(String userId) async {
    final rows = await _client
        .from('student_verifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : StudentVerification.fromJson(list.first as Map<String, dynamic>);
  }

  Future<bool> benefitsActive(String userId) async {
    final res = await _client
        .rpc('student_benefits_active', params: {'p_user_id': userId});
    return res == true;
  }

  // ── Submit + finalise (OCR is run by the caller, on-device) ──────────────────
  /// Uploads the ID image to the private bucket and returns its object path.
  Future<String> uploadIdImage(String userId, File image, {String kind = 'id'}) async {
    final path = '$userId/${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(_bucket).upload(path, image);
    return path; // stored as-is; view via a signed URL
  }

  Future<String> createSignedUrl(String path, {int expiresSeconds = 3600}) {
    return _client.storage.from(_bucket).createSignedUrl(path, expiresSeconds);
  }

  Future<String> submit({
    required String studentId,
    required String studentName,
    required String studentIdNumber,
    required String schoolId,
    required String idImagePath,
    String? selfiePath,
  }) async {
    final res = await _client.rpc('submit_student_verification', params: {
      'p_student_id': studentId,
      'p_student_name': studentName,
      'p_student_id_number': studentIdNumber,
      'p_school_id': schoolId,
      'p_id_image_url': idImagePath,
      'p_selfie_url': selfiePath,
    });
    return res as String;
  }

  Future<StudentVerification> finalize(
    String verificationId,
    StudentIdOcrResult ocr,
  ) async {
    String? d(DateTime? x) => x?.toIso8601String().split('T').first;
    final res = await _client.rpc('finalize_student_verification', params: {
      'p_verification_id': verificationId,
      'p_extracted_name': ocr.name,
      'p_extracted_student_id': ocr.studentId,
      'p_extracted_school': ocr.school,
      'p_issue_date': d(ocr.issueDate),
      'p_expiration_date': d(ocr.expirationDate),
      'p_document_number': ocr.documentNumber,
      'p_ocr_confidence': ocr.confidence,
    });
    return StudentVerification.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  // ── Driver ───────────────────────────────────────────────────────────────────
  /// Minimal student-delivery info for an order (null if not a student order).
  Future<Map<String, dynamic>?> studentOrderInfo(String orderId) async {
    final row = await _client
        .from('orders')
        .select('recipient_type, student_id, school_id, school_name')
        .eq('id', orderId)
        .maybeSingle();
    if (row == null) return null;
    if (row['recipient_type'] != 'student') return null;
    return row;
  }

  Future<String> confirmDelivery(
    String orderId, {
    required bool confirmed,
    String? reason,
  }) async {
    final res = await _client.rpc('confirm_student_delivery', params: {
      'p_order_id': orderId,
      'p_confirmed': confirmed,
      'p_reason': reason,
    });
    final map = Map<String, dynamic>.from(res as Map);
    return (map['status'] as String?) ?? 'ok';
  }

  // ── Admin ──────────────────────────────────────────────────────────────────
  Future<List<StudentDeliveryReview>> getReviews({String? status}) async {
    var q = _client.from('student_delivery_reviews').select();
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => StudentDeliveryReview.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolveReview(String reviewId, String action, {String? notes}) async {
    await _client.rpc('admin_resolve_student_review', params: {
      'p_review_id': reviewId,
      'p_action': action,
      'p_notes': notes,
    });
  }

  Future<List<StudentVerification>> adminVerifications({String? status}) async {
    var q = _client.from('student_verifications').select();
    if (status != null) q = q.eq('verification_status', status);
    final rows = await q.order('created_at', ascending: false).limit(200);
    return (rows as List)
        .map((r) => StudentVerification.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Counts by verification_status for the admin dashboard.
  Future<Map<String, int>> adminMetrics() async {
    final rows = await _client
        .from('student_verifications')
        .select('verification_status');
    final counts = <String, int>{};
    for (final r in (rows as List)) {
      final s = (r as Map)['verification_status'] as String? ?? 'unknown';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Future<int> pendingReviewCount() async {
    final rows = await _client
        .from('student_delivery_reviews')
        .select('id')
        .eq('status', 'pending');
    return (rows as List).length;
  }
}

/// Convenience wrapper: log-and-rethrow used by the UI layer.
Future<T> guardStudentCall<T>(Future<T> Function() fn, String what) async {
  try {
    return await fn();
  } catch (e) {
    AppLogger.error('Student verification: $what failed: $e');
    rethrow;
  }
}
