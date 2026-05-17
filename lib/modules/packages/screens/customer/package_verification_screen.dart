import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/shipping_company.dart';
import '../../providers/package_providers.dart';
import '../../services/package_service.dart';
import 'package_delivery_summary_screen.dart';

class PackageVerificationScreen extends ConsumerStatefulWidget {
  final ShippingCompany company;
  const PackageVerificationScreen({super.key, required this.company});

  @override
  ConsumerState<PackageVerificationScreen> createState() =>
      _PackageVerificationScreenState();
}

class _PackageVerificationScreenState
    extends ConsumerState<PackageVerificationScreen> {
  final _trackingCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _trackingCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchFromApi() async {
    final raw = _trackingCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter your tracking number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Call the backend, which verifies the tracking number in our DB
      // AND calls the shipping company's API to pull real-time data.
      final result = await ref.read(packageServiceProvider).fetchTrackingNumber(
            shippingCompanyId: widget.company.id,
            trackingNumber: raw,
          );

      if (!mounted) return;

      final pkg = result['package'] as Map<String, dynamic>?;
      if (pkg == null) {
        setState(() => _error = 'No package data returned. Please try again.');
        return;
      }

      // Navigate to summary screen with the full result (same shape as
      // verify-package so PackageDeliverySummaryScreen stays unchanged).
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackageDeliverySummaryScreen(
            company: widget.company,
            verifyResult: result,
          ),
        ),
      );
    } on PackageAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('not found') || msg.contains('404')) {
        setState(() => _error =
            'Tracking number not found at ${widget.company.name}. '
            'Please check the number and try again.');
      } else if (msg.contains('not belong')) {
        setState(() => _error =
            'This package is not registered to your account.');
      } else {
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.company.name),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Company header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warehouse,
                      color: Color(0xFF7C3AED), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.company.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(widget.company.warehouseAddress,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'Enter Tracking Number',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the tracking number from your shipment. '
              'We\'ll look it up and fetch the latest details from '
              '${widget.company.name}.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Tracking number input
            TextField(
              controller: _trackingCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Tracking Number',
                hintText: 'e.g. APZ-001122',
                prefixIcon:
                    const Icon(Icons.qr_code, color: Color(0xFF7C3AED)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF7C3AED), width: 2),
                ),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _fetchFromApi(),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _fetchFromApi,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.track_changes),
                label: Text(
                  _loading
                      ? 'Fetching from ${widget.company.name}…'
                      : 'Fetch Tracking Details',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Info note
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your tracking number is found on your shipping '
                    'confirmation, receipt, or notification from '
                    '${widget.company.name}.',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.blueGrey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
