import 'dart:io';

import '../models/driver_document_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, SupabaseClient, Supabase;

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
    final file = File(params.filePath);
    final bytes = await file.readAsBytes();
    final extension = params.filePath.split('.').last.toLowerCase();
    final filePath =
        '${params.driverId}/${params.documentType}/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _client.storage
        .from('driver-documents')
        .uploadBinary(filePath, bytes, fileOptions: FileOptions(upsert: true));

    final publicUrl = _client.storage
        .from('driver-documents')
        .getPublicUrl(filePath);

    await _client.from('driver_documents').insert({
      'driver_id': params.driverId,
      'type': params.documentType,
      'url': publicUrl,
      'is_verified': false,
      'uploaded_at': DateTime.now().toIso8601String(),
    });
  }
}
