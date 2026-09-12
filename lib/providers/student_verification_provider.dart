import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/student_verification_model.dart';
import '../services/student_id_ocr_service.dart';
import '../services/student_verification_service.dart';

final studentVerificationServiceProvider =
    Provider<StudentVerificationService>((ref) {
  return StudentVerificationService(SupabaseConfig.client);
});

final studentIdOcrServiceProvider = Provider<StudentIdOcrService>((ref) {
  return StudentIdOcrService();
});

/// Participating (active) schools — for the student verification form.
final activeSchoolsProvider =
    FutureProvider.autoDispose<List<SchoolOption>>((ref) {
  return ref.watch(studentVerificationServiceProvider).getActiveSchools();
});

/// The student's latest verification attempt (null if never submitted).
final myVerificationProvider = FutureProvider.family
    .autoDispose<StudentVerification?, String>((ref, userId) {
  return ref.watch(studentVerificationServiceProvider).latestVerification(userId);
});

/// Whether student benefits are currently active (drives the lunch gate).
final studentBenefitsActiveProvider =
    FutureProvider.family.autoDispose<bool, String>((ref, userId) {
  return ref.watch(studentVerificationServiceProvider).benefitsActive(userId);
});

// ── Admin ─────────────────────────────────────────────────────────────────────
final adminAllSchoolsProvider =
    FutureProvider.autoDispose<List<SchoolOption>>((ref) {
  return ref.watch(studentVerificationServiceProvider).getAllSchools();
});

final studentReviewsProvider = FutureProvider.family
    .autoDispose<List<StudentDeliveryReview>, String?>((ref, status) {
  return ref.watch(studentVerificationServiceProvider).getReviews(status: status);
});

final adminVerificationsProvider = FutureProvider.family
    .autoDispose<List<StudentVerification>, String?>((ref, status) {
  return ref
      .watch(studentVerificationServiceProvider)
      .adminVerifications(status: status);
});

final studentAdminMetricsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(studentVerificationServiceProvider).adminMetrics();
});
