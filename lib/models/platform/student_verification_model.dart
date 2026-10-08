// Student ID verification records + related read models. Kept as plain Dart
// (no json_serializable) so they don't pull build_runner into shared models.

class SchoolOption {
  final String id;
  final String name;
  final String? address;
  final bool isActive;
  const SchoolOption({
    required this.id,
    required this.name,
    this.address,
    this.isActive = true,
  });
  factory SchoolOption.fromJson(Map<String, dynamic> j) => SchoolOption(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    address: j['address'] as String?,
    isActive: j['is_active'] as bool? ?? true,
  );
}

class StudentVerification {
  final String id;
  final String userId;
  final String? studentName;
  final String? studentIdNumber;
  final String? schoolId;
  final String? studentIdImageUrl;
  final String? submittedSelfieUrl;
  final String? extractedName;
  final String? extractedStudentId;
  final String? extractedSchool;
  final DateTime? extractedExpirationDate;
  final double? ocrConfidence;
  final bool? nameMatch;
  final bool? studentIdMatch;
  final bool? schoolMatch;
  final bool? expirationValid;
  final String status;
  final bool benefitsActive;
  final String? rejectionReason;
  final String? reviewReason;
  final DateTime? verifiedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const StudentVerification({
    required this.id,
    required this.userId,
    this.studentName,
    this.studentIdNumber,
    this.schoolId,
    this.studentIdImageUrl,
    this.submittedSelfieUrl,
    this.extractedName,
    this.extractedStudentId,
    this.extractedSchool,
    this.extractedExpirationDate,
    this.ocrConfidence,
    this.nameMatch,
    this.studentIdMatch,
    this.schoolMatch,
    this.expirationValid,
    required this.status,
    required this.benefitsActive,
    this.rejectionReason,
    this.reviewReason,
    this.verifiedAt,
    this.expiresAt,
    required this.createdAt,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory StudentVerification.fromJson(Map<String, dynamic> j) =>
      StudentVerification(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        studentName: j['student_name'] as String?,
        studentIdNumber: j['student_id_number'] as String?,
        schoolId: j['school_id'] as String?,
        studentIdImageUrl: j['student_id_image_url'] as String?,
        submittedSelfieUrl: j['submitted_selfie_url'] as String?,
        extractedName: j['extracted_name'] as String?,
        extractedStudentId: j['extracted_student_id'] as String?,
        extractedSchool: j['extracted_school'] as String?,
        extractedExpirationDate: _date(j['extracted_expiration_date']),
        ocrConfidence: (j['ocr_confidence'] as num?)?.toDouble(),
        nameMatch: j['name_match'] as bool?,
        studentIdMatch: j['student_id_match'] as bool?,
        schoolMatch: j['school_match'] as bool?,
        expirationValid: j['expiration_valid'] as bool?,
        status: (j['verification_status'] as String?) ?? 'pending',
        benefitsActive: j['benefits_active'] as bool? ?? false,
        rejectionReason: j['rejection_reason'] as String?,
        reviewReason: j['review_reason'] as String?,
        verifiedAt: _date(j['verified_at']),
        expiresAt: _date(j['expires_at']),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );

  bool get isApproved => status == 'approved' && benefitsActive;
  bool get canReupload =>
      status == 'needs_update' || status == 'expired' || status == 'rejected';

  String get statusLabel => switch (status) {
    'pending' => 'Pending',
    'processing' => 'Processing',
    'approved' => 'Verified',
    'needs_update' => 'Needs update',
    'manual_review' => 'Under review',
    'rejected' => 'Rejected',
    'expired' => 'Expired',
    'suspended' => 'Suspended',
    _ => status,
  };
}

class StudentDeliveryReview {
  final String id;
  final String? orderId;
  final String? studentId;
  final String? schoolId;
  final String? driverId;
  final String? reason;
  final String status;
  final String? adminNotes;
  final DateTime createdAt;
  const StudentDeliveryReview({
    required this.id,
    this.orderId,
    this.studentId,
    this.schoolId,
    this.driverId,
    this.reason,
    required this.status,
    this.adminNotes,
    required this.createdAt,
  });
  factory StudentDeliveryReview.fromJson(Map<String, dynamic> j) =>
      StudentDeliveryReview(
        id: j['id'] as String,
        orderId: j['order_id'] as String?,
        studentId: j['student_id'] as String?,
        schoolId: j['school_id'] as String?,
        driverId: j['driver_id'] as String?,
        reason: j['reason'] as String?,
        status: (j['status'] as String?) ?? 'pending',
        adminNotes: j['admin_notes'] as String?,
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
