import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/driver_document_model.dart';
import '../services/driver_document_service.dart';

final driverDocumentServiceProvider = Provider<DriverDocumentService>((ref) {
  return DriverDocumentService();
});

final driverDocumentsProvider =
    FutureProvider.family<List<DriverDocument>, String>((ref, driverId) async {
      final service = ref.watch(driverDocumentServiceProvider);
      return service.getDriverDocuments(driverId);
    });

final uploadDriverDocumentProvider =
    FutureProvider.family<void, UploadDriverDocumentParams>((
      ref,
      params,
    ) async {
      final service = ref.watch(driverDocumentServiceProvider);
      await service.uploadDocument(params);
    });
