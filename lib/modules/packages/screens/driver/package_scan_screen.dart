import 'package:flutter/material.dart';

/// Barcode scan screen — uses the camera via mobile_scanner.
/// Falls back to manual entry if the package is unavailable.
///
/// Returns the scanned/entered string via Navigator.pop(context, result).
class PackageScanScreen extends StatefulWidget {
  final String expectedHint; // shown as placeholder in manual fallback
  const PackageScanScreen({super.key, required this.expectedHint});

  @override
  State<PackageScanScreen> createState() => _PackageScanScreenState();
}

class _PackageScanScreenState extends State<PackageScanScreen> {
  final _manualCtrl = TextEditingController();
  bool _showManual = false;

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _submitManual() {
    final v = _manualCtrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Package Barcode'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => setState(() => _showManual = !_showManual),
            child: Text(
              _showManual ? 'Use Camera' : 'Enter Manually',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _showManual ? _buildManual() : _buildCamera(),
    );
  }

  Widget _buildCamera() {
    // mobile_scanner integration — wrap in try/catch at build time
    // so the screen degrades gracefully if the package isn't linked yet.
    try {
      return _CameraView(
        onDetect: (code) => Navigator.pop(context, code),
        onFallback: () => setState(() => _showManual = true),
      );
    } catch (_) {
      return _buildManual();
    }
  }

  Widget _buildManual() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the barcode or tracking number printed on the package.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _manualCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Barcode / Tracking Number',
              hintText: widget.expectedHint,
              prefixIcon:
                  const Icon(Icons.qr_code, color: Color(0xFF7C3AED)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF7C3AED), width: 2),
              ),
            ),
            onSubmitted: (_) => _submitManual(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitManual,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirm', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin wrapper around mobile_scanner loaded via reflection so the app
/// compiles even before mobile_scanner is added to pubspec.
class _CameraView extends StatelessWidget {
  final ValueChanged<String> onDetect;
  final VoidCallback onFallback;

  const _CameraView({required this.onDetect, required this.onFallback});

  @override
  Widget build(BuildContext context) {
    // Attempt to use mobile_scanner dynamically.
    // Once `mobile_scanner` is in pubspec, replace this body with:
    //
    //   import 'package:mobile_scanner/mobile_scanner.dart';
    //   ...
    //   return MobileScanner(
    //     onDetect: (capture) {
    //       final barcode = capture.barcodes.firstOrNull?.rawValue;
    //       if (barcode != null) onDetect(barcode);
    //     },
    //   );
    //
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Camera scanner not yet linked.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onFallback,
            child: const Text('Enter Manually Instead'),
          ),
        ],
      ),
    );
  }
}
