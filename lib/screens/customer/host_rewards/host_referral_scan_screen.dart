import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../services/host_rewards/host_referral_service.dart';
import '../../../utils/app_theme.dart';

/// Customer scans a host property's QR code (or enters the code) to link their
/// account to the property and save it as a delivery address. Opened from the
/// profile, or via the host referral deep link.
class HostReferralScanScreen extends StatefulWidget {
  /// Optional pre-filled code (e.g. from a deep link) — claimed immediately.
  final String? initialCode;
  const HostReferralScanScreen({super.key, this.initialCode});

  @override
  State<HostReferralScanScreen> createState() => _HostReferralScanScreenState();
}

class _HostReferralScanScreenState extends State<HostReferralScanScreen> {
  final _service = HostReferralService();
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  final _manual = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claim(widget.initialCode!));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _done) return;
    final raw = capture.barcodes.map((b) => b.rawValue).firstWhere(
          (v) => v != null && v.isNotEmpty,
          orElse: () => null,
        );
    if (raw == null) return;
    await _claim(raw);
  }

  Future<void> _claim(String raw) async {
    final code = HostReferralService.parseCode(raw);
    if (code == null) {
      _snack('That doesn\'t look like a HotBite host code.');
      return;
    }
    setState(() => _busy = true);
    final res = await _service.claim(code);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['ok'] == true) {
      _done = true;
      final prop = Map<String, dynamic>.from(res['property'] as Map);
      await _showSuccess(prop);
    } else {
      _snack(_errorText(res['error']?.toString()));
    }
  }

  String _errorText(String? code) => switch (code) {
        'already_referred' =>
          'Your account is already linked to a host. Only one host referral is allowed.',
        'invalid_or_inactive_property' => 'This code is no longer valid.',
        'inactive_host' => 'This host is not active.',
        'disabled' => 'Host Rewards is not available right now.',
        'unauthenticated' => 'Please sign in first.',
        _ => 'Could not link this host. Please try again.',
      };

  Future<void> _showSuccess(Map<String, dynamic> prop) async {
    final name = prop['name'] ?? 'your stay';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('You\'re all set! 🎉'),
        content: Text(
            'You\'re now ordering from "$name". Save it as a delivery address so your orders arrive here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () async {
              await _service.saveClaimedProperty(prop);
              if (dctx.mounted) Navigator.pop(dctx);
            },
            child: const Text('Save address'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan host QR code')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                if (_busy)
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Point your camera at the host\'s QR code',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'Or enter code (HBHOST-…)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _claim,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor),
                    onPressed: _busy ? null : () => _claim(_manual.text),
                    child: const Text('Link'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
