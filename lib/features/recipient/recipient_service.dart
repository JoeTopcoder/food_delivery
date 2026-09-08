import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// A student this customer is allowed to order for, with the school currently
/// on file. The school is read fresh each time rather than remembered, because
/// a student can change school between orders.
class LinkedStudent {
  const LinkedStudent({
    required this.id,
    required this.name,
    required this.walletId,
    this.schoolId,
    this.schoolName,
    this.schoolAddress,
    this.schoolLat,
    this.schoolLng,
  });

  final String id;
  final String name;
  final String walletId;
  final String? schoolId;
  final String? schoolName;
  final String? schoolAddress;

  /// The school's own position. Used for the delivery zone lookup, which would
  /// otherwise be taxed against the parent's home rather than the destination.
  final double? schoolLat;
  final double? schoolLng;

  /// A student with no school on file has nowhere for a delivery to go, and
  /// every checkout says so rather than failing at the end.
  bool get hasSchool =>
      schoolId != null && (schoolAddress?.isNotEmpty ?? false);

  factory LinkedStudent.fromJson(Map<String, dynamic> j) => LinkedStudent(
    id: (j['student_id'] ?? '').toString(),
    name: (j['student_name'] ?? 'Student').toString(),
    walletId: (j['wallet_id'] ?? '').toString(),
    schoolId: j['school_id']?.toString(),
    schoolName: j['school_name']?.toString(),
    schoolAddress: j['school_address']?.toString(),
    schoolLat: (j['school_lat'] as num?)?.toDouble(),
    schoolLng: (j['school_lng'] as num?)?.toDouble(),
  );
}

/// Linking and listing the students a customer may order for.
///
/// Shared by every checkout that delivers — food, grocery and packages — so
/// "who is this for?" behaves identically wherever it is asked.
class RecipientService {
  RecipientService(this._client);

  final SupabaseClient _client;

  Future<List<LinkedStudent>> myStudents() async {
    final rows = await _client.rpc('get_my_students');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((r) => LinkedStudent.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Links a student by the wallet ID shown on their own wallet screen. The
  /// parent is taken from the session server-side, so this cannot link on
  /// someone else's behalf.
  Future<String> linkStudent(String walletId) async {
    final res = await _client.rpc(
      'link_student_by_wallet_id',
      params: {'p_wallet_id': walletId.trim()},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : const {};
    return (map['student_name'] ?? 'Student').toString();
  }

  Future<void> unlinkStudent(String studentId) async {
    await _client.rpc('unlink_student', params: {'p_student_id': studentId});
  }
}

final recipientServiceProvider = Provider<RecipientService>(
  (ref) => RecipientService(SupabaseConfig.client),
);

final myStudentsProvider = FutureProvider<List<LinkedStudent>>(
  (ref) => ref.read(recipientServiceProvider).myStudents(),
);

/// The student the current checkout is for; null means the customer themselves,
/// which is the default and what every existing order already is.
///
/// Deliberately NOT persisted and NOT part of the cart: an order sent to one
/// child last week should not silently go to the same child today. autoDispose
/// is what makes that true — the choice dies with the checkout screen that
/// asked for it, so the next order starts at "Myself" again.
final selectedStudentProvider = StateProvider.autoDispose<String?>((ref) => null);

/// The selected student in full, or null when ordering for yourself.
final selectedStudentDetailProvider = Provider.autoDispose<LinkedStudent?>((ref) {
  final id = ref.watch(selectedStudentProvider);
  if (id == null) return null;
  final students = ref.watch(myStudentsProvider).valueOrNull;
  if (students == null) return null;
  for (final s in students) {
    if (s.id == id) return s;
  }
  return null;
});
