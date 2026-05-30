import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../providers/auth_provider.dart';
import '../../providers/driver_document_provider.dart';
import '../../services/driver_document_service.dart';
import '../../../../utils/friendly_error.dart';

class DriverDocumentUploadScreen extends ConsumerStatefulWidget {
  const DriverDocumentUploadScreen({super.key});

  @override
  ConsumerState<DriverDocumentUploadScreen> createState() =>
      _DriverDocumentUploadScreenState();
}

class _DriverDocumentUploadScreenState
    extends ConsumerState<DriverDocumentUploadScreen> {
  final _picker = ImagePicker();
  bool _isSubmitting = false;

  final Map<String, File?> _selectedFiles = {
    'license': null,
    'registration': null,
    'insurance': null,
  };

  static const _documents = [
    {'type': 'license', 'label': 'Driver License'},
    {'type': 'registration', 'label': 'Vehicle Registration'},
    {'type': 'insurance', 'label': 'Insurance'},
  ];

  Future<void> _pickFile(String type) async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );

    if (pickedFile == null) return;

    setState(() {
      _selectedFiles[type] = File(pickedFile.path);
    });
  }

  Future<void> _submitUpload() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to upload documents')),
      );
      return;
    }

    final selectedFiles = _selectedFiles.entries
        .where((entry) => entry.value != null)
        .toList();

    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one document.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      for (final entry in selectedFiles) {
        await ref
            .read(driverDocumentServiceProvider)
            .uploadDocument(
              UploadDriverDocumentParams(
                driverId: userId,
                documentType: entry.key,
                filePath: entry.value!.path,
              ),
            );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents uploaded successfully.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Documents'), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _documents.length,
                itemBuilder: (context, index) {
                  final type = _documents[index]['type']!;
                  final label = _documents[index]['label']!;
                  final file = _selectedFiles[type];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: file != null
                                      ? Colors.green[50]
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  file != null ? 'Selected' : 'Not uploaded',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: file != null
                                        ? Colors.green[800]
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (file != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              file.path.split('/').last,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => _pickFile(type),
                                  icon: const Icon(Icons.upload_file),
                                  label: Text(
                                    file != null
                                        ? 'Change file'
                                        : 'Select file',
                                  ),
                                ),
                              ),
                              if (file != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () {
                                          setState(
                                            () => _selectedFiles[type] = null,
                                          );
                                        },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitUpload,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit for Verification'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
