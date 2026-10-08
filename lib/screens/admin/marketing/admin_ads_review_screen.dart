import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../models/catalog/ad_model.dart';
import '../../../providers/catalog/ads_provider.dart';
import '../../../services/ads/admin_ads_service.dart';

/// Admin "Restaurant Advertising" console: settings, requests, creative review,
/// quotes/payments, scheduling, campaign controls and performance. All actions
/// run through the server-enforced lifecycle RPCs.
class AdminAdsReviewScreen extends ConsumerWidget {
  const AdminAdsReviewScreen({super.key});
  String _money(int c) => '${AppConstants.currencySymbol}${(c / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reqs = ref.watch(adminAdRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurant Advertising')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminAdRequestsProvider);
          ref.invalidate(adminAdSettingsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SettingsCard(),
            const SizedBox(height: 16),
            Text('Requests', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            reqs.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('Error: $e'),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No requests.', style: TextStyle(color: Colors.grey)))
                  : Column(children: list.map((r) => _AdminRequestTile(request: r, money: _money)).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminAdSettingsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: s.when(
          loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('Could not load settings.'),
          data: (cfg) {
            final enabled = cfg['enabled'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Advertising settings', style: TextStyle(fontWeight: FontWeight.w800)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ads enabled (master flag)'),
                  value: enabled,
                  onChanged: (v) async {
                    await ref.read(adminAdsServiceProvider).updateSettings({'enabled': v});
                    ref.invalidate(adminAdSettingsProvider);
                  },
                ),
                Text('Capacity (max concurrent): ${cfg['max_concurrent']} · '
                     'exposure/session: ${cfg['session_exposure_limit']} · '
                     'serve radius: ${cfg['serve_radius_km']} km',
                     style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('Default placement price: ${AppConstants.currencySymbol}'
                     '${(((cfg['default_placement_cents'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)}',
                     style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminRequestTile extends ConsumerWidget {
  final AdRequest request;
  final String Function(int) money;
  const _AdminRequestTile({required this.request, required this.money});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(adminAdsServiceProvider);
    void refresh() => ref.invalidate(adminAdRequestsProvider);

    return Card(
      child: ExpansionTile(
        title: Text(request.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${request.kind} · ${request.status}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (request.status == 'submitted' || request.status == 'in_review')
            Row(children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                onPressed: () async { await svc.reviewRequest(request.id, 'approved'); refresh(); },
                child: const Text('Approve'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final reason = await _prompt(context, 'Reason for rejection');
                  if (reason == null) return;
                  await svc.reviewRequest(request.id, 'rejected', reason: reason);
                  refresh();
                },
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Reject'),
              ),
            ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.request_quote_rounded, size: 18),
            label: const Text('Issue quote'),
            onPressed: () async {
              final q = await _quoteDialog(context);
              if (q == null) return;
              await svc.issueQuote(request.id, productionCents: q.$1, placementCents: q.$2);
              ref.invalidate(adQuotesProvider(request.id));
            },
          ),
          _AdminCreatives(requestId: request.id),
          _AdminCampaigns(requestId: request.id, money: money),
        ],
      ),
    );
  }
}

class _AdminCreatives extends ConsumerWidget {
  final String requestId;
  const _AdminCreatives({required this.requestId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creatives = ref.watch(adCreativesProvider(requestId));
    final svc = ref.read(adminAdsServiceProvider);
    return creatives.maybeWhen(
      data: (list) => list.isEmpty ? const SizedBox.shrink() : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Creatives', style: TextStyle(fontWeight: FontWeight.w700)),
          ...list.map((c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.isVideo ? Icons.videocam : Icons.image),
                title: Text('v${c.version} · ${c.mediaType} · ${c.status}'),
                subtitle: c.processingError != null ? Text(c.processingError!, style: const TextStyle(color: Colors.red, fontSize: 11)) : null,
                trailing: Wrap(spacing: 2, children: [
                  if (c.status == 'uploaded' || c.status == 'processing' || c.status == 'failed')
                    IconButton(
                      tooltip: 'Mark ready (set playback URL)',
                      icon: const Icon(Icons.cloud_done_outlined),
                      onPressed: () async {
                        final url = await _prompt(context, 'Processed playback URL');
                        if (url == null || url.isEmpty) return;
                        await svc.markCreativeReady(c.id, url);
                        ref.invalidate(adCreativesProvider(requestId));
                      },
                    ),
                  if (c.status == 'pending_approval')
                    IconButton(
                      tooltip: 'Approve (admin)',
                      icon: const Icon(Icons.verified, color: Colors.green),
                      onPressed: () async { await svc.decideCreative(c.id, true); ref.invalidate(adCreativesProvider(requestId)); },
                    ),
                ]),
              )),
        ],
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _AdminCampaigns extends ConsumerStatefulWidget {
  final String requestId;
  final String Function(int) money;
  const _AdminCampaigns({required this.requestId, required this.money});
  @override
  ConsumerState<_AdminCampaigns> createState() => _AdminCampaignsState();
}

class _AdminCampaignsState extends ConsumerState<_AdminCampaigns> {
  Map<String, dynamic>? _metrics;
  String? _metricsFor;

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(adminAdsServiceProvider);
    final campsAsync = ref.watch(_adminCampaignsForRequest(widget.requestId));
    return campsAsync.maybeWhen(
      data: (camps) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Campaigns', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create'),
              onPressed: () async {
                // pick the newest approved creative + newest accepted quote
                final creatives = await svc.creatives(widget.requestId);
                final approved = creatives.where((c) => c.status == 'approved').toList();
                if (approved.isEmpty) {
                  _snack('Need an approved creative first'); return;
                }
                final quotes = await svc.quotes(widget.requestId);
                final accepted = quotes.where((q) => q.status == 'accepted').toList();
                await svc.createCampaign(widget.requestId, approved.first.id,
                    quoteId: accepted.isNotEmpty ? accepted.first.id : null);
                ref.invalidate(_adminCampaignsForRequest(widget.requestId));
              },
            ),
          ]),
          ...camps.map((c) => Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.status}${c.paymentSatisfied ? ' · paid' : ' · unpaid'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                Wrap(spacing: 6, children: [
                  TextButton(onPressed: () => _book(svc, c.id), child: const Text('Reserve booking')),
                  TextButton(onPressed: () => _pay(svc, c.id), child: const Text('Verify payment')),
                  TextButton(onPressed: () async {
                    try { await svc.activate(c.id); _snack('Activated'); }
                    catch (e) { _snack('$e'); }
                    ref.invalidate(_adminCampaignsForRequest(widget.requestId));
                  }, child: const Text('Activate')),
                  if (c.status == 'active')
                    TextButton(onPressed: () async { await svc.setState(c.id, 'pause', reason: 'admin'); ref.invalidate(_adminCampaignsForRequest(widget.requestId)); }, child: const Text('Pause')),
                  if (c.status == 'paused')
                    TextButton(onPressed: () async { await svc.setState(c.id, 'resume'); ref.invalidate(_adminCampaignsForRequest(widget.requestId)); }, child: const Text('Resume')),
                  TextButton(onPressed: () async { await svc.setState(c.id, 'cancel', reason: 'admin'); ref.invalidate(_adminCampaignsForRequest(widget.requestId)); }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Cancel')),
                  TextButton(onPressed: () async {
                    final m = await svc.campaignMetrics(c.id);
                    setState(() { _metrics = m; _metricsFor = c.id; });
                  }, child: const Text('Performance')),
                ]),
                if (_metricsFor == c.id && _metrics != null)
                  Text('Impr ${_metrics!['impressions']} · starts ${_metrics!['video_starts']} · '
                       'compl ${_metrics!['video_completions']} · clicks ${_metrics!['cta_clicks']} · '
                       'orders ${_metrics!['attributed_orders']}',
                       style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )),
        ],
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }

  Future<void> _book(AdminAdsService svc, String campaignId) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (range == null) return;
    try {
      await svc.reserveBooking(campaignId, 1, range.start, range.end.add(const Duration(days: 1)));
      _snack('Booked slot 1');
    } catch (e) { _snack('$e'); }
    ref.invalidate(_adminCampaignsForRequest(widget.requestId));
  }

  Future<void> _pay(AdminAdsService svc, String campaignId) async {
    final amt = await _prompt(context, 'Amount (JMD)');
    if (amt == null) return;
    final cents = ((double.tryParse(amt) ?? 0) * 100).round();
    try {
      await svc.verifyPayment(campaignId, cents, 'placement', 'manual-$campaignId-${DateTime.now().millisecondsSinceEpoch}');
      _snack('Payment recorded');
    } catch (e) { _snack('$e'); }
    ref.invalidate(_adminCampaignsForRequest(widget.requestId));
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

// per-request campaigns provider (admin)
final _adminCampaignsForRequest =
    FutureProvider.autoDispose.family<List<AdCampaign>, String>((ref, requestId) =>
        ref.watch(adminAdsServiceProvider).campaignsForRequest(requestId));

Future<String?> _prompt(BuildContext context, String label) async {
  final ctrl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(label),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}

/// Returns (productionCents, placementCents).
Future<(int, int)?> _quoteDialog(BuildContext context) async {
  final prod = TextEditingController();
  final place = TextEditingController();
  final res = await showDialog<(int, int)>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Issue quote (JMD)'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: prod, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Production', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: place, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Placement', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final p = ((double.tryParse(prod.text) ?? 0) * 100).round();
          final pl = ((double.tryParse(place.text) ?? 0) * 100).round();
          Navigator.pop(context, (p, pl));
        }, child: const Text('Issue')),
      ],
    ),
  );
  prod.dispose();
  place.dispose();
  return res;
}
