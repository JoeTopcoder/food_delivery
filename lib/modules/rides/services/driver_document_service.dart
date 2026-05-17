import '../models/driver_document_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UploadDriverDocumentParams {
  final String driverId;
  final String documentType;
  final String filePath;

  UploadDriverDocumentParams({
    required this.driverId,
    required this.documentType,
    required this.filePath,
  });
}

class DriverDocumentService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<DriverDocument>> getDriverDocuments(String driverId) async {
    final response = await _client
        .from('driver_documents')
        .select()
        .eq('driver_id', driverId)
        .order('uploaded_at', ascending: false);
    return (response as List)
        .map((e) => DriverDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> uploadDocument(UploadDriverDocumentParams params) async {
    // This is a placeholder for actual upload logic (e.g., Supabase Storage)
    // You would upload the file, get the URL, then insert a record
    // For now, just simulate success
    await Future.delayed(const Duration(milliseconds: 500));
    // TODO: Implement actual upload logic
  }
}
