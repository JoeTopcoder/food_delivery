import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/host_rewards/host_portal_provider.dart';
import '../../services/host_rewards/host_portal_service.dart';
import '../../utils/app_theme.dart';

/// Host portal (role='host'). Shows the host ONLY their own earnings, properties
/// and payouts — all RLS-scoped server-side.
class HostDashboardScreen extends ConsumerWidget {
  const HostDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My HotBite Earnings'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Properties'),
              Tab(text: 'Earnings'),
              Tab(text: 'Payouts'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _Overview(),
          _Properties(),
          _Earnings(),
          _Payouts(),
        ]),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostDashboardProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostDashboardProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (m) {
          if (m['is_host'] != true) {
            return _empty('Your account isn\'t linked to a host yet.');
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              _kpi('Properties', '${m['properties']}', Icons.home_work_rounded),
              _kpi('Active guests', '${m['referrals']}', Icons.people_rounded),
            ]),
            Row(children: [
              _kpi('Pending', HostPortalService.centsToJmd(m['pending_cents']),
                  Icons.hourglass_bottom_rounded),
              _kpi('Available', HostPortalService.centsToJmd(m['payable_cents']),
                  Icons.account_balance_wallet_rounded),
            ]),
            Row(children: [
              _kpi('Total paid', HostPortalService.centsToJmd(m['paid_cents']),
                  Icons.check_circle_rounded),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('How you earn',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text(
                          'Display your property QR code. When a guest scans it and orders '
                          'to your property, you earn a commission on each delivered order. '
                          'Payouts are processed by HotBite.'),
                    ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: AppTheme.primaryColor),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _Properties extends ConsumerWidget {
  const _Properties();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostMyPropertiesProvider);
    final svc = ref.read(hostPortalServiceProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostMyPropertiesProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (props) => props.isEmpty
            ? _empty('No properties yet. Contact HotBite to add one.')
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: props.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = props[i];
                  final code = p['referral_code'] as String;
                  final url = svc.referralUrl(code);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Text(p['property_name'] ?? '—',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(10),
                          child: QrImageView(
                              data: url, size: 180, version: QrVersions.auto),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(code,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        TextButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy link'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: url));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link copied')));
                          },
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Earnings extends ConsumerWidget {
  const _Earnings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostMyCommissionsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostMyCommissionsProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (rows) => rows.isEmpty
            ? _empty('No earnings yet.')
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = rows[i];
                  final snap = c['property_snapshot'] as Map? ?? {};
                  return Card(
                    child: ListTile(
                      title: Text(
                          HostPortalService.centsToJmd(
                              (c['amount_cents'] as num?)?.toInt()),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${snap['property_name'] ?? ''}'),
                      trailing: _statusChip(c['status']),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Payouts extends ConsumerWidget {
  const _Payouts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostMyPayoutsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostMyPayoutsProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (rows) => rows.isEmpty
            ? _empty('No payouts yet.')
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = rows[i];
                  return Card(
                    child: ListTile(
                      title: Text(
                          HostPortalService.centsToJmd(
                              (p['amount_cents'] as num?)?.toInt()),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(p['payout_reference'] ?? '—'),
                      trailing: _statusChip(p['status']),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

Widget _statusChip(dynamic status) {
  final s = (status ?? '').toString();
  final color = switch (s) {
    'paid' || 'approved' || 'payable' => Colors.green,
    'pending' => Colors.orange,
    'reversed' || 'rejected' => Colors.red,
    _ => Colors.grey,
  };
  return Chip(
    label: Text(s, style: TextStyle(color: color, fontSize: 11)),
    backgroundColor: color.withValues(alpha: 0.12),
    side: BorderSide(color: color.withValues(alpha: 0.3)),
    visualDensity: VisualDensity.compact,
  );
}

Widget _err(Object e) =>
    Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e')));
Widget _empty(String t) => Center(
    child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(t, style: const TextStyle(color: Colors.grey))));
