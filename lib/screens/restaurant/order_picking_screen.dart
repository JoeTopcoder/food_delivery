import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../models/pick_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

/// In-store picking / fulfilment for a grocery order. Staff scan each product
/// (camera or a hardware/manual code) to tick it off, or tap to pick by hand.
/// When every line is picked, they can mark the order Ready.
class OrderPickingScreen extends ConsumerStatefulWidget {
  final Order order;
  const OrderPickingScreen({super.key, required this.order});

  @override
  ConsumerState<OrderPickingScreen> createState() => _OrderPickingScreenState();
}

class _OrderPickingScreenState extends ConsumerState<OrderPickingScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  String get _orderId => widget.order.id;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _orderLabel {
    final n =
        widget.order.restaurantOrderNumber ??
        widget.order.receiptNumber ??
        widget.order.id.substring(0, 8).toUpperCase();
    return '#$n';
  }

  List<PickLine> _currentLines() =>
      ref.read(pickListProvider(_orderId)).valueOrNull ?? const [];

  // ── Scan / manual processing ───────────────────────────────────────────────

  /// Processes a scanned/entered code. Returns feedback for the live scanner
  /// overlay; when the code is unknown it carries [assignCode] so the caller
  /// can open the "link this code" flow.
  Future<_ScanOutcome> _process(String code) async {
    final svc = ref.read(orderPickingServiceProvider);
    try {
      final res = await svc.scan(_orderId, code);
      ref.invalidate(pickListProvider(_orderId));
      final status = res['status'] as String?;
      final name = res['product_name'] as String? ?? 'Item';
      switch (status) {
        case 'picked':
          HapticFeedback.mediumImpact();
          return _ScanOutcome(
            '✓ $name  (${res['picked_quantity']}/${res['quantity']})',
            AppSnackbarType.success,
          );
        case 'already_complete':
          return _ScanOutcome(
            '$name already picked',
            AppSnackbarType.warning,
          );
        case 'not_in_order':
          HapticFeedback.heavyImpact();
          return _ScanOutcome(
            '$name isn’t on this order',
            AppSnackbarType.error,
          );
        case 'unknown_code':
          return _ScanOutcome(
            'New code — link it to an item',
            AppSnackbarType.info,
            assignCode: code,
          );
        default:
          return _ScanOutcome('Scan not recognised', AppSnackbarType.error);
      }
    } catch (e) {
      return _ScanOutcome(friendlyError(e), AppSnackbarType.error);
    }
  }

  Future<void> _openScanner() async {
    // The scanner stays open for continuous scanning; it pops back a code only
    // when that code is unknown and needs linking to a product.
    final assignCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScannerView(onDetect: _process),
      ),
    );
    if (assignCode != null && mounted) {
      await _promptAssign(assignCode);
    }
  }

  Future<void> _submitManual() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    _codeCtrl.clear();
    final outcome = await _process(code);
    if (!mounted) return;
    if (outcome.assignCode != null) {
      await _promptAssign(outcome.assignCode!);
    } else {
      AppSnackbar.show(context, message: outcome.message, type: outcome.kind);
    }
  }

  /// Ask which order line an unknown code belongs to, link it, and pick one.
  Future<void> _promptAssign(String code) async {
    final lines = _currentLines();
    final chosen = await showModalBottomSheet<PickLine>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignSheet(code: code, lines: lines),
    );
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    final svc = ref.read(orderPickingServiceProvider);
    try {
      await svc.assignBarcode(chosen.menuItemId, code);
      await svc.scan(_orderId, code); // pick one now that it's linked
      ref.invalidate(pickListProvider(_orderId));
      if (mounted) {
        AppSnackbar.success(context, 'Linked to ${chosen.name} & picked one');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Manual per-line editing ─────────────────────────────────────────────────

  Future<void> _setPicked(PickLine line, int qty) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(orderPickingServiceProvider)
          .setItemPicked(line.orderItemId, qty);
      ref.invalidate(pickListProvider(_orderId));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReady() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(orderServiceProvider)
          .updateOrderStatus(_orderId, AppConstants.orderReady);
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(context, 'Order $_orderLabel marked ready');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(pickListProvider(_orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick Order $_orderLabel',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const Text(
              'Scan or tap each item',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: listAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading items…'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(pickListProvider(_orderId)),
        ),
        data: (lines) {
          if (lines.isEmpty) {
            return const AppEmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'No items on this order',
              subtitle: 'Nothing to pick here.',
            );
          }
          final pickedLines = lines.where((l) => l.done).length;
          final totalUnits = lines.fold<int>(0, (s, l) => s + l.quantity);
          final pickedUnits = lines.fold<int>(
            0,
            (s, l) => s + l.pickedQuantity,
          );
          final allDone = pickedLines == lines.length;

          return Column(
            children: [
              _ProgressHeader(
                pickedLines: pickedLines,
                totalLines: lines.length,
                pickedUnits: pickedUnits,
                totalUnits: totalUnits,
              ),
              _ScanBar(
                controller: _codeCtrl,
                busy: _busy,
                onScan: _openScanner,
                onSubmit: _submitManual,
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final line = lines[i];
                    return _PickTile(
                      line: line,
                      busy: _busy,
                      onDecrement: line.pickedQuantity > 0
                          ? () => _setPicked(line, line.pickedQuantity - 1)
                          : null,
                      onIncrement: line.pickedQuantity < line.quantity
                          ? () => _setPicked(line, line.pickedQuantity + 1)
                          : null,
                      onToggleDone: () =>
                          _setPicked(line, line.done ? 0 : line.quantity),
                    );
                  },
                ),
              ),
              if (allDone)
                SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _markReady,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF067647),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'All items picked — Mark Ready',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanOutcome {
  final String message;
  final AppSnackbarType kind;
  final String? assignCode; // non-null -> caller should open the link flow
  const _ScanOutcome(this.message, this.kind, {this.assignCode});

  /// Colour for the live scanner banner, keyed to the feedback kind.
  Color get color => switch (kind) {
    AppSnackbarType.success => const Color(0xFF067647),
    AppSnackbarType.warning => const Color(0xFFB54708),
    AppSnackbarType.error => const Color(0xFFB42318),
    AppSnackbarType.info => const Color(0xFF6941C6),
  };
}

// ── Progress header ──────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  final int pickedLines;
  final int totalLines;
  final int pickedUnits;
  final int totalUnits;
  const _ProgressHeader({
    required this.pickedLines,
    required this.totalLines,
    required this.pickedUnits,
    required this.totalUnits,
  });

  @override
  Widget build(BuildContext context) {
    final frac = totalLines == 0 ? 0.0 : pickedLines / totalLines;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$pickedLines of $totalLines items picked',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$pickedUnits / $totalUnits units',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              color: frac >= 1 ? const Color(0xFF067647) : AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan bar (camera button + code field for wedge / manual entry) ───────────

class _ScanBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onSubmit;
  const _ScanBar({
    required this.controller,
    required this.busy,
    required this.onScan,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: busy ? null : onScan,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text(
              'Scan',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: 'Enter / scan code',
                isDense: true,
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.keyboard_return, size: 20),
                  onPressed: busy ? null : onSubmit,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One pick line ────────────────────────────────────────────────────────────

class _PickTile extends StatelessWidget {
  final PickLine line;
  final bool busy;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback onToggleDone;
  const _PickTile({
    required this.line,
    required this.busy,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final done = line.done;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFECFDF3) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? const Color(0xFFA6F4C5) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          // Done checkbox
          GestureDetector(
            onTap: busy ? null : onToggleDone,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: done ? const Color(0xFF067647) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: done ? const Color(0xFF067647) : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (line.imageUrl != null && line.imageUrl!.isNotEmpty)
                ? Image.network(
                    line.imageUrl!,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumb(),
                  )
                : _thumb(),
          ),
          const SizedBox(width: 10),
          // Name + linked flag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? Colors.grey[600] : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${line.pickedQuantity} / ${line.quantity}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: done
                            ? const Color(0xFF067647)
                            : Colors.grey[700],
                      ),
                    ),
                    if (!line.hasBarcode) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.link_off,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Stepper
          _StepBtn(icon: Icons.remove, onTap: busy ? null : onDecrement),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${line.pickedQuantity}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepBtn(icon: Icons.add, onTap: busy ? null : onIncrement),
        ],
      ),
    );
  }

  Widget _thumb() => Container(
    width: 42,
    height: 42,
    color: Colors.grey[100],
    child: Icon(Icons.shopping_bag_outlined, size: 20, color: Colors.grey[400]),
  );
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppTheme.primaryColor : Colors.grey[400],
        ),
      ),
    );
  }
}

// ── Assign sheet (unknown code -> which item is this?) ───────────────────────

class _AssignSheet extends StatelessWidget {
  final String code;
  final List<PickLine> lines;
  const _AssignSheet({required this.code, required this.lines});

  @override
  Widget build(BuildContext context) {
    // Offer un-linked lines first (the likely target), then the rest.
    final ordered = [...lines]
      ..sort((a, b) {
        if (a.hasBarcode != b.hasBarcode) return a.hasBarcode ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Which item is this?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Link code “$code” to a product so it scans automatically '
                    'next time.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final l = ordered[i];
                  return Material(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(l),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (l.hasBarcode)
                              Text(
                                'has a code',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey[500],
                                ),
                              ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full-screen camera scanner ───────────────────────────────────────────────

class _ScannerView extends StatefulWidget {
  /// Processes a code and returns feedback. If the outcome carries an
  /// [_ScanOutcome.assignCode], the scanner closes and returns that code so the
  /// parent can open the link flow.
  final Future<_ScanOutcome> Function(String code) onDetect;
  const _ScannerView({required this.onDetect});

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _processing = false;
  _ScanOutcome? _feedback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;

    // Debounce: ignore the same code within 2s (the camera fires continuously).
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inMilliseconds < 2000) {
      return;
    }
    _lastCode = code;
    _lastAt = now;

    setState(() => _processing = true);
    final outcome = await widget.onDetect(code);
    if (!mounted) return;
    if (outcome.assignCode != null) {
      Navigator.of(context).pop(outcome.assignCode);
      return;
    }
    setState(() {
      _feedback = outcome;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera unavailable.\n${error.errorDetails?.message ?? 'Check camera permission in Settings, or use the code field instead.'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reticle
          Center(
            child: Container(
              width: 240,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Feedback banner
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_feedback != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _feedback!.color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _feedback!.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
