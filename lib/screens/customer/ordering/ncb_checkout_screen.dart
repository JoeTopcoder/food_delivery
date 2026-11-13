import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../utils/app_theme.dart';

/// Result of the NCB hosted-checkout WebView flow.
enum NcbCheckoutResult { success, failure, cancelled }

/// In-app WebView that hosts the NCB (Genius Checkout) payment page. Loads the
/// session [checkoutUrl]; when the gateway redirects to a `/ncb/success`,
/// `/ncb/failure` or `/ncb/cancel` URL, we intercept it, pop with the result,
/// and the caller verifies server-side. 3-D Secure renders inside the WebView.
class NcbCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  const NcbCheckoutScreen({super.key, required this.checkoutUrl});

  @override
  State<NcbCheckoutScreen> createState() => _NcbCheckoutScreenState();
}

class _NcbCheckoutScreenState extends State<NcbCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (_) {},
        onPageStarted: (url) {
          if (_intercept(url)) return;
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
        onNavigationRequest: (req) {
          if (_intercept(req.url)) return NavigationDecision.prevent;
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  /// Returns true (and closes the screen) if [url] is an NCB return URL.
  bool _intercept(String url) {
    if (_done) return true;
    final u = url.toLowerCase();
    NcbCheckoutResult? result;
    if (u.contains('/ncb/success')) {
      result = NcbCheckoutResult.success;
    } else if (u.contains('/ncb/failure')) {
      result = NcbCheckoutResult.failure;
    } else if (u.contains('/ncb/cancel')) {
      result = NcbCheckoutResult.cancelled;
    }
    if (result == null) return false;
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
    return true;
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: const Text('Your order will not be paid if you leave now.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep paying')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(NcbCheckoutResult.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmCancel(); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure payment'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmCancel,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const LinearProgressIndicator(minHeight: 3),
            if (_loading)
              Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
          ],
        ),
      ),
    );
  }
}
