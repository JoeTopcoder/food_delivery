// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/host_rewards/host_rewards_provider.dart';
import '../../../services/host_rewards/host_rewards_service.dart';
import '../../../utils/app_theme.dart';

/// Admin → Host Rewards. Register hosts & properties, generate QR codes, review
/// commissions, and run admin-controlled payouts. All writes go through the
/// is_admin()-gated RPCs; the client never computes money.
class AdminHostRewardsScreen extends ConsumerStatefulWidget {
  const AdminHostRewardsScreen({super.key});
  @override
  ConsumerState<AdminHostRewardsScreen> createState() =>
      _AdminHostRewardsScreenState();
}

class _AdminHostRewardsScreenState
    extends ConsumerState<AdminHostRewardsScreen> {
  static const _tabs = [
    'Overview',
    'Hosts',
    'Properties',
    'Commissions',
    'Payouts',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Host Rewards'),
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(),
            _HostsTab(),
            _PropertiesTab(),
            _CommissionsTab(),
            _PayoutsTab(),
            _SettingsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Overview ─────────────────────────────────────────────────────────────────
class _OverviewTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostRewardsOverviewProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostRewardsOverviewProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (m) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _kpi('Active hosts', '${m['hosts_active']}', Icons.people_rounded),
              _kpi('Active properties', '${m['properties_active']}',
                  Icons.home_work_rounded),
            ]),
            Row(children: [
              _kpi('Active referrals', '${m['referrals_active']}',
                  Icons.qr_code_rounded),
              _kpi('Pending', HostRewardsService.centsToJmd(m['pending_cents']),
                  Icons.hourglass_bottom_rounded),
            ]),
            Row(children: [
              _kpi('Payable', HostRewardsService.centsToJmd(m['payable_cents']),
                  Icons.account_balance_wallet_rounded),
              _kpi('Paid out', HostRewardsService.centsToJmd(m['paid_cents']),
                  Icons.check_circle_rounded),
            ]),
          ],
        ),
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
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
        ),
      );
}

// ── Hosts ────────────────────────────────────────────────────────────────────
class _HostsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostsListProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showHostForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add host'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(hostsListProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _err(e),
          data: (hosts) => hosts.isEmpty
              ? _empty('No hosts yet. Add one to get started.')
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: hosts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final h = hosts[i];
                    return Card(
                      child: ListTile(
                        title: Text(h['full_name'] ?? '—',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${h['email'] ?? ''}  ${h['phone'] ?? ''}'.trim()),
                        trailing: _statusChip(h['status']),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _showHostForm(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final biz = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Register host'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _tf(name, 'Full name *'),
            _tf(email, 'Email'),
            _tf(phone, 'Phone'),
            _tf(biz, 'Business name'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(hostRewardsServiceProvider).createHost(
            fullName: name.text.trim(),
            email: email.text.trim().isEmpty ? null : email.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            businessName: biz.text.trim().isEmpty ? null : biz.text.trim(),
          );
      ref.invalidate(hostsListProvider);
      ref.invalidate(hostRewardsOverviewProvider);
    } catch (e) {
      _toast(context, 'Failed: $e');
    }
  }
}

// ── Properties ───────────────────────────────────────────────────────────────
class _PropertiesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(hostsListProvider);
    final propsAsync = ref.watch(hostPropertiesProvider(null));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPropertyForm(context, ref),
        icon: const Icon(Icons.add_home_rounded),
        label: const Text('Add property'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(hostPropertiesProvider(null)),
        child: propsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _err(e),
          data: (props) {
            final hostNames = {
              for (final h in (hostsAsync.valueOrNull ?? []))
                h['id'] as String: h['full_name'] as String? ?? '—'
            };
            return props.isEmpty
                ? _empty('No properties yet.')
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: props.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = props[i];
                      return Card(
                        child: ListTile(
                          title: Text(p['property_name'] ?? '—',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${hostNames[p['host_id']] ?? ''} · ${p['referral_code']}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _statusChip(p['status']),
                            IconButton(
                              icon: const Icon(Icons.qr_code_2_rounded),
                              onPressed: () => _showQr(context, ref, p),
                            ),
                          ]),
                        ),
                      );
                    },
                  );
          },
        ),
      ),
    );
  }

  void _showQr(BuildContext context, WidgetRef ref, Map<String, dynamic> p) {
    final svc = ref.read(hostRewardsServiceProvider);
    final code = p['referral_code'] as String;
    final name = (p['property_name'] as String?) ?? 'Property';
    final url = svc.referralUrl(code);
    final cardKey = GlobalKey();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // The printable card (captured to PNG on "Save card").
            RepaintBoundary(
              key: cardKey,
              child: _HostQrCard(propertyName: name, code: code, url: url),
            ),
            const SizedBox(height: 10),
            SelectableText(url,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.image_rounded, size: 18),
                label: const Text('Save QR (PNG)'),
                onPressed: () => _saveQrPng(context, url, code),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.badge_rounded, size: 18),
                label: const Text('Save card'),
                onPressed: () => _saveBoundaryPng(context, cardKey, 'HotBite-Host-$code'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy link'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  _toast(context, 'Referral link copied');
                },
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.autorenew_rounded, size: 18),
            label: const Text('Rotate code'),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await svc.rotateCode(p['id'] as String);
                ref.invalidate(hostPropertiesProvider(null));
                _toast(context, 'New code generated — old QR is now invalid');
              } catch (e) {
                _toast(context, 'Failed: $e');
              }
            },
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _showPropertyForm(BuildContext context, WidgetRef ref) async {
    final hosts = ref.read(hostsListProvider).valueOrNull ?? [];
    if (hosts.isEmpty) {
      _toast(context, 'Add a host first.');
      return;
    }
    String? hostId = hosts.first['id'] as String?;
    final name = TextEditingController();
    final addr = TextEditingController();
    final parish = TextEditingController();
    final area = TextEditingController();
    final instr = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add property'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: hostId,
                decoration: const InputDecoration(labelText: 'Host'),
                items: [
                  for (final h in hosts)
                    DropdownMenuItem(
                        value: h['id'] as String,
                        child: Text(h['full_name'] as String? ?? '—')),
                ],
                onChanged: (v) => setD(() => hostId = v),
              ),
              _tf(name, 'Property name *'),
              _tf(addr, 'Address *'),
              _tf(parish, 'Parish'),
              _tf(area, 'Community / area'),
              _tf(instr, 'Delivery instructions'),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true ||
        hostId == null ||
        name.text.trim().isEmpty ||
        addr.text.trim().isEmpty) {
      return;
    }
    try {
      final res = await ref.read(hostRewardsServiceProvider).createProperty(
            hostId: hostId!,
            name: name.text.trim(),
            address: addr.text.trim(),
            parish: parish.text.trim().isEmpty ? null : parish.text.trim(),
            area: area.text.trim().isEmpty ? null : area.text.trim(),
            instructions: instr.text.trim().isEmpty ? null : instr.text.trim(),
          );
      ref.invalidate(hostPropertiesProvider(null));
      ref.invalidate(hostRewardsOverviewProvider);
      _toast(context, 'Created · code ${res['referral_code']}');
    } catch (e) {
      _toast(context, 'Failed: $e');
    }
  }
}

// ── Commissions ──────────────────────────────────────────────────────────────
class _CommissionsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostCommissionsProvider(null));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hostCommissionsProvider(null)),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _err(e),
        data: (rows) => rows.isEmpty
            ? _empty('No commissions yet.')
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
                          HostRewardsService.centsToJmd(
                              (c['amount_cents'] as num?)?.toInt()),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${snap['property_name'] ?? ''} · order ${(c['order_id'] as String?)?.substring(0, 8) ?? ''}'),
                      trailing: _statusChip(c['status']),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ── Payouts ──────────────────────────────────────────────────────────────────
class _PayoutsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoutsAsync = ref.watch(hostPayoutsProvider);
    final hostsAsync = ref.watch(hostsListProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _approveForHost(context, ref),
        icon: const Icon(Icons.payments_rounded),
        label: const Text('Approve payout'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(hostPayoutsProvider),
        child: payoutsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _err(e),
          data: (rows) {
            final hostNames = {
              for (final h in (hostsAsync.valueOrNull ?? []))
                h['id'] as String: h['full_name'] as String? ?? '—'
            };
            return rows.isEmpty
                ? _empty('No payouts yet.')
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = rows[i];
                      final paid = p['status'] == 'paid';
                      return Card(
                        child: ListTile(
                          title: Text(
                              HostRewardsService.centsToJmd(
                                  (p['amount_cents'] as num?)?.toInt()),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle:
                              Text(hostNames[p['host_id']] ?? p['host_id']),
                          trailing: paid
                              ? _statusChip('paid')
                              : TextButton(
                                  onPressed: () =>
                                      _markPaid(context, ref, p['id'] as String),
                                  child: const Text('Mark paid'),
                                ),
                        ),
                      );
                    },
                  );
          },
        ),
      ),
    );
  }

  Future<void> _approveForHost(BuildContext context, WidgetRef ref) async {
    final hosts = ref.read(hostsListProvider).valueOrNull ?? [];
    if (hosts.isEmpty) {
      _toast(context, 'No hosts.');
      return;
    }
    String? hostId = hosts.first['id'] as String?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Approve payout'),
          content: DropdownButtonFormField<String>(
            initialValue: hostId,
            decoration: const InputDecoration(labelText: 'Host'),
            items: [
              for (final h in hosts)
                DropdownMenuItem(
                    value: h['id'] as String,
                    child: Text(h['full_name'] as String? ?? '—')),
            ],
            onChanged: (v) => setD(() => hostId = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve')),
          ],
        ),
      ),
    );
    if (ok != true || hostId == null) return;
    try {
      final res =
          await ref.read(hostRewardsServiceProvider).approvePayout(hostId!);
      ref.invalidate(hostPayoutsProvider);
      ref.invalidate(hostRewardsOverviewProvider);
      ref.invalidate(hostCommissionsProvider(null));
      _toast(
          context,
          res['ok'] == true
              ? 'Payout approved: ${HostRewardsService.centsToJmd((res['amount_cents'] as num?)?.toInt())}'
              : 'Nothing payable yet.');
    } catch (e) {
      _toast(context, 'Failed: $e');
    }
  }

  Future<void> _markPaid(
      BuildContext context, WidgetRef ref, String payoutId) async {
    final refC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark payout paid'),
        content: _tf(refC, 'Payout reference *'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || refC.text.trim().isEmpty) return;
    try {
      await ref
          .read(hostRewardsServiceProvider)
          .markPayoutPaid(payoutId, refC.text.trim());
      ref.invalidate(hostPayoutsProvider);
      _toast(context, 'Marked paid');
    } catch (e) {
      _toast(context, 'Failed: $e');
    }
  }
}

// ── Settings ─────────────────────────────────────────────────────────────────
class _SettingsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostRewardsConfigProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _err(e),
      data: (cfg) {
        final commission = TextEditingController(
            text: (((cfg['default_commission_cents'] as num?)?.toInt() ?? 10000) /
                    100)
                .toStringAsFixed(0));
        final days = TextEditingController(
            text: '${(cfg['referral_days'] as num?)?.toInt() ?? 30}');
        final hold = TextEditingController(
            text: '${(cfg['hold_period_days'] as num?)?.toInt() ?? 7}');
        bool enabled = cfg['enabled'] == true;
        return StatefulBuilder(
          builder: (ctx, setS) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Host Rewards enabled'),
                subtitle: const Text(
                    'Master switch. When off, no commissions are created.'),
                value: enabled,
                activeThumbColor: AppTheme.primaryColor,
                onChanged: (v) => setS(() => enabled = v),
              ),
              const Divider(),
              _tf(commission, 'Default commission (J\$ per eligible order)'),
              _tf(days, 'Referral validity (days)'),
              _tf(hold, 'Payout hold period (days)'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref.read(hostRewardsServiceProvider).updateConfig(
                          defaultCommissionCents:
                              ((double.tryParse(commission.text) ?? 100) * 100)
                                  .round(),
                          referralDays: int.tryParse(days.text),
                          holdPeriodDays: int.tryParse(hold.text),
                          enabled: enabled,
                        );
                    ref.invalidate(hostRewardsConfigProvider);
                    _toast(context, 'Settings saved');
                  } catch (e) {
                    _toast(context, 'Failed: $e');
                  }
                },
                child: const Text('Save settings'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── shared helpers ───────────────────────────────────────────────────────────
Widget _tf(TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      ),
    );

Widget _statusChip(dynamic status) {
  final s = (status ?? '').toString();
  final color = switch (s) {
    'active' || 'paid' || 'approved' || 'payable' => Colors.green,
    'pending' => Colors.orange,
    'suspended' || 'rejected' || 'reversed' => Colors.red,
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

void _toast(BuildContext context, String msg) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// A printable, branded QR card for a host property. Captured to PNG via a
/// RepaintBoundary (no PDF dependency needed — a PNG prints cleanly).
class _HostQrCard extends StatelessWidget {
  final String propertyName;
  final String code;
  final String url;
  const _HostQrCard(
      {required this.propertyName, required this.code, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFE64A19)),
          const SizedBox(width: 6),
          const Text('HotBite',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 2),
        const Text('Order food & groceries, delivered',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 16),
        QrImageView(
            data: url,
            size: 200,
            version: QrVersions.auto,
            backgroundColor: Colors.white),
        const SizedBox(height: 14),
        Text(propertyName,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Scan to order to this stay',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFFF1F1F1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(code,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
      ]),
    );
  }
}

Future<void> _saveQrPng(BuildContext context, String url, String code) async {
  try {
    final painter = QrPainter(
      data: url,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
    );
    final data = await painter.toImageData(1024, format: ui.ImageByteFormat.png);
    if (data == null) throw 'render failed';
    await _sharePng(context, data.buffer.asUint8List(), 'HotBite-QR-$code');
  } catch (e) {
    _toast(context, 'Could not export QR: $e');
  }
}

Future<void> _saveBoundaryPng(
    BuildContext context, GlobalKey key, String filename) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw 'not ready';
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw 'render failed';
    await _sharePng(context, data.buffer.asUint8List(), filename);
  } catch (e) {
    _toast(context, 'Could not export card: $e');
  }
}

Future<void> _sharePng(
    BuildContext context, Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename.png');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    subject: 'HotBite Host QR',
  ));
}
