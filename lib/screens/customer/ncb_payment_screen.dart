import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/payment_provider.dart';
import '../../services/payment_service.dart';

class NcbPaymentScreen extends ConsumerStatefulWidget {
  final NcbPaymentSession session;

  const NcbPaymentScreen({super.key, required this.session});

  @override
  ConsumerState<NcbPaymentScreen> createState() => _NcbPaymentScreenState();
}

class _NcbPaymentScreenState extends ConsumerState<NcbPaymentScreen> {
  late final WebViewController _controller;
  bool _isFinalizing = false;
  bool _handledCallback = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
        ),
      );
    _loadPaymentPage();
  }

  /// Fetch the HTML from the edge function and render it via loadHtmlString
  /// so the WebView correctly interprets the content as HTML (not plain text).
  Future<void> _loadPaymentPage() async {
    final uri = Uri.parse(widget.session.paymentUrl);
    try {
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final html = await response.transform(const Utf8Decoder()).join();
      client.close();
      if (!mounted) return;
      await _controller.loadHtmlString(html);
    } catch (_) {
      // Fallback: try direct URL loading
      if (!mounted) return;
      await _controller.loadRequest(uri);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _isCallbackUrl(String url) {
    return url.startsWith(widget.session.callbackUrl);
  }

  Future<void> _onPageFinished(String url) async {
    if (!_isCallbackUrl(url) || _handledCallback) {
      return;
    }

    _handledCallback = true;
    setState(() => _isFinalizing = true);

    final orderId = widget.session.orderId;
    final isNonOrder =
        orderId.startsWith('verify-card-') || orderId.startsWith('wallet-');

    bool success;
    if (isNonOrder) {
      // For non-order transactions, read the status from the callback URL
      final callbackUri = Uri.parse(url);
      final status = callbackUri.queryParameters['status'] ?? 'failed';
      success = status == 'success';
    } else {
      final paymentService = ref.read(paymentServiceProvider);
      final paymentStatus = await paymentService.waitForOrderPaymentStatus(
        orderId,
      );
      success = paymentStatus == AppConstants.paymentCompleted;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Card Payment')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (_isFinalizing)
            Container(
              color: Colors.black.withValues(alpha: 0.2),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Verifying NCB payment...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
