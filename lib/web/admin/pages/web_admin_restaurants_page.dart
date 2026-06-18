import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_constants.dart';
import '../../../providers/admin_provider.dart';
import '../../../models/restaurant_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebAdminRestaurantsPage extends ConsumerStatefulWidget {
  const WebAdminRestaurantsPage({super.key});

  @override
  ConsumerState<WebAdminRestaurantsPage> createState() => _WebAdminRestaurantsPageState();
}

class _WebAdminRestaurantsPageState extends ConsumerState<WebAdminRestaurantsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['All', 'Pending', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(allRestaurantsAdminProvider);
    ref.invalidate(pendingRestaurantsProvider);
    ref.invalidate(rejectedRestaurantsProvider);
  }

  Future<void> _verify(Restaurant r, bool approve) async {
    try {
      await ref.read(adminServiceProvider).verifyRestaurant(r.id, approve);
      _refresh();
      if (mounted) {
        AppSnackbar.show(
          context,
          message: approve ? '"${r.name}" verified' : '"${r.name}" rejected',
          type: approve ? AppSnackbarType.success : AppSnackbarType.warning,
        );
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showVerifyConfirm(Restaurant r, bool approve) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(approve ? 'Verify Restaurant?' : r.isVerified ? 'Revoke Verification?' : 'Reject Restaurant?'),
        content: Text(
          approve
              ? 'Verify "${r.name}"? They will appear to customers on the app.'
              : r.isVerified
                  ? 'Remove verification from "${r.name}"? They won\'t be visible to customers.'
                  : 'Reject "${r.name}"? They won\'t be visible to customers.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _verify(r, approve); },
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? const Color(0xFF10B981) : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(approve ? 'Verify' : r.isVerified ? 'Revoke' : 'Reject'),
          ),
        ],
      ),
    );
  }

  void _showCommissionDialog(Restaurant r) {
    final raw = r.commissionRate ?? 15;
    double commission = (raw <= 1 ? raw * 100 : raw).clamp(0, 50).toDouble();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Set Commission: ${r.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${commission.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
              Slider(
                value: commission, min: 0, max: 50, divisions: 50,
                activeColor: const Color(0xFF8B5CF6),
                label: '${commission.toStringAsFixed(0)}%',
                onChanged: (v) => setS(() => commission = v),
              ),
              const Text('Platform commission on each order', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(adminServiceProvider).updateRestaurantCommission(r.id, commission / 100);
                  _refresh();
                  if (mounted) AppSnackbar.success(context, 'Commission set to ${commission.toStringAsFixed(0)}%');
                } catch (e) {
                  if (mounted) AppSnackbar.error(context, friendlyError(e));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showServiceFeeDialog(Restaurant r) {
    double fee = r.serviceFee ?? 0;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Set Service Fee: ${r.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${AppConstants.currencySymbol}${fee.toStringAsFixed(0)}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9))),
              Slider(
                value: fee, min: 0, max: 200, divisions: 40,
                activeColor: const Color(0xFF0EA5E9),
                label: '${AppConstants.currencySymbol}${fee.toStringAsFixed(0)}',
                onChanged: (v) => setS(() => fee = v),
              ),
              const Text('Fee charged to customer for pickup orders', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(adminServiceProvider).updateRestaurantServiceFee(r.id, fee);
                  _refresh();
                  if (mounted) AppSnackbar.success(context, 'Service fee set to ${AppConstants.currencySymbol}${fee.toStringAsFixed(0)}');
                } catch (e) {
                  if (mounted) AppSnackbar.error(context, friendlyError(e));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(Restaurant r) {
    showDialog(
      context: context,
      builder: (_) => _RestaurantDetailsDialog(
        restaurant: r,
        onVerify: () => _showVerifyConfirm(r, true),
        onReject: () => _showVerifyConfirm(r, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allRestaurantsAdminProvider((0, 100)));
    final pendingAsync = ref.watch(pendingRestaurantsProvider);
    final rejectedAsync = ref.watch(rejectedRestaurantsProvider);

    final current = _tab.index == 0 ? allAsync : _tab.index == 1 ? pendingAsync : rejectedAsync;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Restaurants', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                  Text('Manage restaurant partners', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: _refresh),
            ],
          ),
          const SizedBox(height: 20),

          // ── Tabs ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
            ),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(10)),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.all(6),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Table ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: current.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: _refresh),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No restaurants found', style: TextStyle(color: Color(0xFF94A3B8))))
                    : _RestaurantsTable(
                        restaurants: items,
                        onVerify: (r) => _showVerifyConfirm(r, true),
                        onReject: (r) => _showVerifyConfirm(r, false),
                        onCommission: _showCommissionDialog,
                        onServiceFee: _showServiceFeeDialog,
                        onDetails: _showDetails,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Restaurants Table ──────────────────────────────────────────────────────────

class _RestaurantsTable extends StatelessWidget {
  final List<Restaurant> restaurants;
  final ValueChanged<Restaurant> onVerify;
  final ValueChanged<Restaurant> onReject;
  final ValueChanged<Restaurant> onCommission;
  final ValueChanged<Restaurant> onServiceFee;
  final ValueChanged<Restaurant> onDetails;

  const _RestaurantsTable({
    required this.restaurants,
    required this.onVerify,
    required this.onReject,
    required this.onCommission,
    required this.onServiceFee,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: _Th('Name')),
              Expanded(child: _Th('Cuisine')),
              SizedBox(width: 90, child: _Th('Status')),
              SizedBox(width: 70, child: _Th('Rating')),
              SizedBox(width: 80, child: _Th('Comm.')),
              Expanded(child: _Th('Address')),
              SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: ListView.separated(
            itemCount: restaurants.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final r = restaurants[i];
              final isVerified = r.isVerified;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    // Name
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                        if (r.phone != null && r.phone!.isNotEmpty)
                          InkWell(
                            onTap: () => launchUrl(Uri(scheme: 'tel', path: r.phone!)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.call_rounded, size: 12, color: Color(0xFF10B981)),
                              const SizedBox(width: 3),
                              Text(r.phone!, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                            ]),
                          ),
                      ]),
                    ),
                    Expanded(child: Text(r.cuisineType ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                    SizedBox(width: 90, child: _VerifiedBadge(isVerified: isVerified)),
                    SizedBox(
                      width: 70,
                      child: Row(children: [
                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(r.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ]),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '${((r.commissionRate ?? 0.15) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text(r.address ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
                    SizedBox(
                      width: 48,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
                        onSelected: (action) {
                          switch (action) {
                            case 'details': onDetails(r); break;
                            case 'commission': onCommission(r); break;
                            case 'service_fee': onServiceFee(r); break;
                            case 'verify': onVerify(r); break;
                            case 'reject': onReject(r); break;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'details', child: Row(children: [Icon(Icons.info_outline_rounded, size: 18), SizedBox(width: 8), Text('View Details')])),
                          const PopupMenuItem(value: 'commission', child: Row(children: [Icon(Icons.percent_rounded, size: 18, color: Color(0xFF8B5CF6)), SizedBox(width: 8), Text('Set Commission', style: TextStyle(color: Color(0xFF8B5CF6)))])),
                          const PopupMenuItem(value: 'service_fee', child: Row(children: [Icon(Icons.shopping_bag_rounded, size: 18, color: Color(0xFF0EA5E9)), SizedBox(width: 8), Text('Set Service Fee', style: TextStyle(color: Color(0xFF0EA5E9)))])),
                          if (!isVerified)
                            const PopupMenuItem(value: 'verify', child: Row(children: [Icon(Icons.verified_rounded, size: 18, color: Color(0xFF10B981)), SizedBox(width: 8), Text('Verify', style: TextStyle(color: Color(0xFF10B981)))])),
                          PopupMenuItem(
                            value: 'reject',
                            child: Row(children: [
                              const Icon(Icons.block_rounded, size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(isVerified ? 'Revoke Verification' : 'Reject', style: const TextStyle(color: Colors.red)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Restaurant Details Dialog ──────────────────────────────────────────────────

class _RestaurantDetailsDialog extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  const _RestaurantDetailsDialog({
    required this.restaurant,
    required this.onVerify,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final isVerified = r.isVerified;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isVerified ? const Color(0xFFFF6B35).withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.store_rounded, color: isVerified ? const Color(0xFFFF6B35) : const Color(0xFFF59E0B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
                    Text(r.cuisineType ?? 'Cuisine N/A', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  ]),
                ),
                _VerifiedBadge(isVerified: isVerified),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            // Body
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('General Info', [
                      _item('Address', r.address ?? 'N/A'),
                      _item('Phone', r.phone ?? 'N/A'),
                      _item('Email', r.email ?? 'N/A'),
                      _item('Store Type', r.storeType),
                      _item('Status', r.status),
                      _item('Description', r.description ?? 'N/A'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Operations', [
                      _item('Opening', r.openingTime ?? 'N/A'),
                      _item('Closing', r.closingTime ?? 'N/A'),
                      _item('Delivery Time', '${r.estimatedDeliveryTime ?? 30} min'),
                      _item('Delivery Fee', '${AppConstants.currencySymbol}${r.deliveryFee?.toStringAsFixed(2) ?? "0.00"}'),
                      _item('Service Fee', '${AppConstants.currencySymbol}${r.serviceFee?.toStringAsFixed(2) ?? "0.00"}'),
                      _item('Commission', '${((r.commissionRate ?? 0.15) * 100).toStringAsFixed(0)}%'),
                      _item('Rating', '${r.rating?.toStringAsFixed(2) ?? "0.00"} (${r.reviewCount ?? 0} reviews)'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Financials', [
                      _item('Total Earnings', '${AppConstants.currencySymbol}${r.totalEarnings?.toStringAsFixed(2) ?? "0.00"}'),
                      _item('Total Paid Out', '${AppConstants.currencySymbol}${r.totalPaidOut?.toStringAsFixed(2) ?? "0.00"}'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Banking', [
                      _item('Bank', r.bankName ?? 'N/A'),
                      _item('Branch', r.bankBranch ?? 'N/A'),
                      _item('Account Holder', r.bankAccountHolder ?? 'N/A'),
                      _item('Account Number', r.bankAccountNumber ?? 'N/A'),
                      _item('Account Type', r.bankAccountType ?? 'N/A'),
                    ]),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () { Navigator.pop(context); onReject(); },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text(isVerified ? 'Revoke Verification' : 'Reject'),
                  ),
                ),
                if (!isVerified) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(context); onVerify(); },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Verify Restaurant'),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
          child: Column(children: List.generate(rows.length, (i) => Column(children: [
            rows[i],
            if (i < rows.length - 1) const Divider(height: 1, color: Color(0xFFE2E8F0), indent: 16),
          ]))),
        ),
      ],
    );
  }

  Widget _item(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _VerifiedBadge extends StatelessWidget {
  final bool isVerified;
  const _VerifiedBadge({required this.isVerified});

  @override
  Widget build(BuildContext context) {
    final color = isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isVerified ? Icons.verified_rounded : Icons.hourglass_top_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(isVerified ? 'Verified' : 'Pending', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}
