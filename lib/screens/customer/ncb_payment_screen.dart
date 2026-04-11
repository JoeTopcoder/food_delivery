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

  bool get _isTestMode =>
      widget.session.paymentUrl.contains('ncb-initiate-payment?');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onNavigationRequest: (request) {
            // Intercept callback URL navigation
            if (_isCallbackUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    if (_isTestMode) {
      _controller.loadHtmlString(_buildTestCardFormHtml());
    } else {
      _controller.loadRequest(Uri.parse(widget.session.paymentUrl));
    }
  }

  String _buildTestCardFormHtml() {
    final orderId = widget.session.orderId;
    final ref = widget.session.transactionId;
    final cb = widget.session.callbackUrl;
    // Extract amount from the payment URL if available
    final uri = Uri.parse(widget.session.paymentUrl);
    final amount = uri.queryParameters['amount'] ?? '0.00';

    final successUrlBase =
        '$cb?order_id=${Uri.encodeComponent(orderId)}&transaction_id=${Uri.encodeComponent(ref)}&status=success&message=Payment+successful';
    final failUrl =
        '$cb?order_id=${Uri.encodeComponent(orderId)}&transaction_id=${Uri.encodeComponent(ref)}&status=failed&message=Payment+cancelled';

    return '''<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>NCB Payment</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f0f2f5;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
    .card{background:#fff;border-radius:16px;box-shadow:0 8px 32px rgba(0,0,0,.1);width:min(400px,100%);overflow:hidden}
    .header{background:linear-gradient(135deg,#1a5c2e,#2d8e47);color:#fff;padding:20px 24px;text-align:center}
    .header h1{font-size:18px;font-weight:600}
    .header .amount{font-size:36px;font-weight:800;margin-top:8px;letter-spacing:-1px}
    .header .amount small{font-size:18px;font-weight:400;opacity:.8}
    .badges{display:flex;gap:6px;justify-content:center;margin-top:10px}
    .badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700}
    .badge-test{background:rgba(255,255,255,.2);color:#fff}
    .brands{display:flex;gap:8px;justify-content:center;margin-top:12px}
    .brand{background:rgba(255,255,255,.15);padding:4px 10px;border-radius:6px;font-size:10px;font-weight:800;color:#fff;letter-spacing:.5px}
    .body{padding:20px 24px}
    .field{margin-bottom:14px}
    .field label{display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;color:#6B7280;margin-bottom:6px;text-transform:uppercase;letter-spacing:.5px}
    .field label svg{width:14px;height:14px}
    .field input{width:100%;padding:14px;border:1.5px solid #E5E7EB;border-radius:10px;font-size:16px;outline:none;transition:border .2s;background:#FAFAFA}
    .field input:focus{border-color:#2d8e47;background:#fff}
    .row{display:flex;gap:12px}
    .row .field{flex:1}
    .btn{width:100%;padding:16px;border:none;border-radius:12px;font-size:16px;font-weight:700;cursor:pointer;transition:all .2s}
    .btn:active{transform:scale(.98)}
    .btn-pay{background:linear-gradient(135deg,#1a5c2e,#2d8e47);color:#fff;margin-bottom:10px;letter-spacing:.3px}
    .btn-pay:disabled{opacity:.6}
    .btn-cancel{background:#F3F4F6;color:#6B7280;font-weight:500}
    .secure{display:flex;align-items:center;justify-content:center;gap:6px;margin-top:16px;padding-top:16px;border-top:1px solid #F3F4F6;font-size:12px;color:#9CA3AF}
    .secure span{color:#2d8e47;font-weight:600}
    .card-icon{position:absolute;right:14px;top:50%;transform:translateY(-50%);pointer-events:none}
    .card-num-wrap{position:relative}
    .spinner{display:inline-block;width:18px;height:18px;border:2.5px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .6s linear infinite;vertical-align:middle;margin-right:8px}
    @keyframes spin{to{transform:rotate(360deg)}}
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>NCB Payment Gateway</h1>
      <div class="amount"><small>J\\\$</small>$amount</div>
      <div class="badges">
        <span class="badge badge-test">TEST MODE</span>
      </div>
      <div class="brands">
        <span class="brand">VISA</span>
        <span class="brand">MASTERCARD</span>
        <span class="brand">KEYCARD</span>
      </div>
    </div>
    <div class="body">
      <div class="field">
        <label>Card Number</label>
        <div class="card-num-wrap">
          <input id="cardNum" type="text" inputmode="numeric" placeholder="4111 1111 1111 1111" maxlength="19" value="4111 1111 1111 1111" oninput="formatCard(this)"/>
        </div>
      </div>
      <div class="row">
        <div class="field">
          <label>Expiry Date</label>
          <input id="expiry" type="text" placeholder="MM/YY" maxlength="5" value="12/28" oninput="formatExpiry(this)"/>
        </div>
        <div class="field">
          <label>CVV</label>
          <input type="text" inputmode="numeric" placeholder="&bull;&bull;&bull;" maxlength="4" value="123"/>
        </div>
      </div>
      <div class="field">
        <label>Cardholder Name</label>
        <input type="text" placeholder="Full name on card" value="Test User" style="text-transform:uppercase"/>
      </div>
      <button class="btn btn-pay" id="payBtn" onclick="pay()">Pay J\\\$$amount</button>
      <button class="btn btn-cancel" onclick="cancel()">Cancel Payment</button>
      <div class="secure">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="#9CA3AF"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zM12 17c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zM15.1 8H8.9V6c0-1.71 1.39-3.1 3.1-3.1s3.1 1.39 3.1 3.1v2z"/></svg>
        Secured by <span>NCB Jamaica</span>
      </div>
    </div>
  </div>
  <script>
    function formatCard(el){
      var v=el.value.replace(/\\D/g,'').substring(0,16);
      el.value=v.replace(/(\\d{4})(?=\\d)/g,'\$1 ');
    }
    function formatExpiry(el){
      var v=el.value.replace(/\\D/g,'').substring(0,4);
      if(v.length>=3) v=v.substring(0,2)+'/'+v.substring(2);
      el.value=v;
    }
    function pay(){
      var cn=document.getElementById('cardNum').value.replace(/\\s/g,'');
      if(cn.length<13){alert('Please enter a valid card number');return;}
      var last4=cn.substring(cn.length-4);
      var brand='visa';
      if(cn.startsWith('5')||cn.startsWith('2'))brand='mastercard';
      else if(cn.startsWith('3'))brand='keycard';
      var btn=document.getElementById('payBtn');
      btn.innerHTML='<span class="spinner"></span>Processing...';
      btn.disabled=true;
      setTimeout(function(){window.location.href="$successUrlBase&card_last4="+last4+"&card_brand="+brand;},1800);
    }
    function cancel(){window.location.href="$failUrl";}
  </script>
</body>
</html>''';
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

    final paymentService = ref.read(paymentServiceProvider);
    final paymentStatus = await paymentService.waitForOrderPaymentStatus(
      widget.session.orderId,
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(paymentStatus == AppConstants.paymentCompleted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Card Payment')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
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
