import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import '../utils/app_logger.dart';

/// Structured output of on-device OCR over a student ID.
class StudentIdOcrResult {
  final String rawText;
  final String? name;
  final String? studentId;
  final String? school;
  final DateTime? issueDate;
  final DateTime? expirationDate;
  final String? documentNumber;

  /// Heuristic 0-100 confidence. Tesseract's `extractText` gives no per-word
  /// score, so we approximate from how much readable text + how many key fields
  /// were recovered. The server threshold + match checks are the real gate.
  final double confidence;

  const StudentIdOcrResult({
    required this.rawText,
    this.name,
    this.studentId,
    this.school,
    this.issueDate,
    this.expirationDate,
    this.documentNumber,
    required this.confidence,
  });
}

/// Runs Tesseract fully on-device and parses common student-ID fields.
/// No image ever leaves the phone for OCR (self-hosted requirement).
class StudentIdOcrService {
  /// Throws [StudentIdOcrException] on an unreadable image / OCR failure.
  Future<StudentIdOcrResult> recognize(String imagePath) async {
    String text;
    try {
      text = await FlutterTesseractOcr.extractText(imagePath, language: 'eng');
    } catch (e) {
      AppLogger.error('Tesseract OCR failed: $e');
      throw const StudentIdOcrException('Could not read the ID. Please retake the photo.');
    }
    final clean = text.trim();
    if (clean.replaceAll(RegExp(r'\s'), '').length < 12) {
      throw const StudentIdOcrException(
        'The ID was too blurry or unreadable. Please retake the photo in good light.',
      );
    }

    final lines = clean
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final studentId = _findStudentId(clean, lines);
    final dates = _findDates(clean);
    final name = _findName(lines);
    final school = _findSchool(lines);
    final docNo = _findDocumentNumber(clean);

    // Issue = earliest, expiration = latest, when two+ dates are present.
    DateTime? issue, expiry;
    if (dates.isNotEmpty) {
      dates.sort();
      if (dates.length == 1) {
        expiry = dates.first;
      } else {
        issue = dates.first;
        expiry = dates.last;
      }
    }

    // Confidence proxy.
    var score = 30.0;
    if (clean.length > 60) score += 15;
    if (name != null) score += 15;
    if (studentId != null) score += 20;
    if (expiry != null) score += 15;
    if (school != null) score += 5;
    if (score > 100) score = 100;

    return StudentIdOcrResult(
      rawText: clean,
      name: name,
      studentId: studentId,
      school: school,
      issueDate: issue,
      expirationDate: expiry,
      documentNumber: docNo,
      confidence: score,
    );
  }

  // ── field heuristics ───────────────────────────────────────────────────────

  String? _findStudentId(String text, List<String> lines) {
    // Prefer a token after an ID label.
    final labelled = RegExp(
      r'(?:student\s*(?:id|no|number)|id\s*(?:no|number)?)\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{3,})',
      caseSensitive: false,
    ).firstMatch(text);
    if (labelled != null) return labelled.group(1)!.toUpperCase();
    // Else a standalone alphanumeric token that contains digits (4-12 chars).
    for (final l in lines) {
      final m = RegExp(r'\b([A-Z]*\d[A-Z0-9]{3,11})\b', caseSensitive: false)
          .firstMatch(l.replaceAll(' ', ''));
      if (m != null) return m.group(1)!.toUpperCase();
    }
    return null;
  }

  List<DateTime> _findDates(String text) {
    final out = <DateTime>[];
    // dd/mm/yyyy, mm-dd-yyyy, yyyy-mm-dd, dd.mm.yy …
    for (final m in RegExp(r'\b(\d{1,4})[\/\-.](\d{1,2})[\/\-.](\d{1,4})\b')
        .allMatches(text)) {
      final d = _parseNumericDate(m.group(1)!, m.group(2)!, m.group(3)!);
      if (d != null) out.add(d);
    }
    // "Jan 2027", "January 15, 2027"
    for (final m in RegExp(
      r'([A-Za-z]{3,9})\.?\s+(\d{1,2},?\s+)?(\d{4})',
    ).allMatches(text)) {
      final month = _monthNum(m.group(1)!);
      if (month == null) continue;
      final day = int.tryParse((m.group(2) ?? '1').replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
      final year = int.parse(m.group(3)!);
      out.add(DateTime(year, month, day.clamp(1, 28)));
    }
    return out;
  }

  DateTime? _parseNumericDate(String a, String b, String c) {
    int? y, mo, d;
    if (a.length == 4) {
      y = int.tryParse(a); mo = int.tryParse(b); d = int.tryParse(c); // yyyy-mm-dd
    } else if (c.length >= 3) {
      d = int.tryParse(a); mo = int.tryParse(b); y = int.tryParse(c); // dd-mm-yyyy
    } else {
      d = int.tryParse(a); mo = int.tryParse(b);
      final yy = int.tryParse(c);
      y = yy == null ? null : (yy < 70 ? 2000 + yy : 1900 + yy);
    }
    if (y == null || mo == null || d == null) return null;
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
    return DateTime(y, mo, d);
  }

  int? _monthNum(String s) {
    const months = [
      'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'
    ];
    final k = s.toLowerCase();
    for (var i = 0; i < months.length; i++) {
      if (k.startsWith(months[i])) return i + 1;
    }
    return null;
  }

  String? _findName(List<String> lines) {
    final labelled = lines.firstWhere(
      (l) => RegExp(r'name\s*[:#]', caseSensitive: false).hasMatch(l),
      orElse: () => '',
    );
    if (labelled.isNotEmpty) {
      final v = labelled.replaceAll(RegExp(r'.*name\s*[:#]\s*', caseSensitive: false), '').trim();
      if (v.length >= 3) return v;
    }
    // Else the first line that looks like a person's name (2-3 alpha words).
    for (final l in lines) {
      if (RegExp(r'^[A-Za-z][A-Za-z.\-]+(\s+[A-Za-z][A-Za-z.\-]+){1,2}$').hasMatch(l) &&
          !RegExp(r'school|high|academy|college|student|id|card', caseSensitive: false).hasMatch(l)) {
        return l;
      }
    }
    return null;
  }

  String? _findSchool(List<String> lines) {
    for (final l in lines) {
      if (RegExp(r'school|high|academy|college|institute|university',
              caseSensitive: false)
          .hasMatch(l)) {
        return l;
      }
    }
    return null;
  }

  String? _findDocumentNumber(String text) {
    final m = RegExp(r'(?:doc(?:ument)?|card)\s*(?:no|number|#)?\s*[:#]?\s*([A-Z0-9-]{4,})',
            caseSensitive: false)
        .firstMatch(text);
    return m?.group(1)?.toUpperCase();
  }
}

class StudentIdOcrException implements Exception {
  final String message;
  const StudentIdOcrException(this.message);
  @override
  String toString() => message;
}
