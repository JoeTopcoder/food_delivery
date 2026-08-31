import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

/// Admin "Birthday Campaign" page — Ads & Marketing section. Settings write
/// straight to app_config (same key/value table every other business
/// setting in the app uses); the "today's birthdays" list is a live join of
/// birthday_rewards + users + promo_codes. Redeemed/available status is
/// always read from promo_codes.usage_count — never duplicated here.
class AdminBirthdayCampaignScreen extends ConsumerStatefulWidget {
  const AdminBirthdayCampaignScreen({super.key});

  @override
  ConsumerState<AdminBirthdayCampaignScreen> createState() =>
      _AdminBirthdayCampaignScreenState();
}

class _AdminBirthdayCampaignScreenState
    extends ConsumerState<AdminBirthdayCampaignScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _enabled = true;
  final _discountCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  List<Map<String, dynamic>> _rows = [];

  static const _keys = [
    'birthday_campaign_enabled',
    'birthday_discount_amount',
    'birthday_min_order_amount',
    'birthday_notification_title',
    'birthday_notification_body',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _minOrderCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final config = await _client
          .from('app_config')
          .select('key, value')
          .inFilter('key', _keys);
      final map = {for (final r in config) r['key'] as String: r['value'] as String};
      _enabled = (map['birthday_campaign_enabled'] ?? 'true') == 'true';
      _discountCtrl.text = map['birthday_discount_amount'] ?? '500';
      _minOrderCtrl.text = map['birthday_min_order_amount'] ?? '2000';
      _titleCtrl.text = map['birthday_notification_title'] ?? '🎂 Happy Birthday!';
      _bodyCtrl.text = map['birthday_notification_body'] ??
          "Happy Birthday, {first_name}! 🎉 We've got a special reward waiting for you.";

      // Recent birthday rewards (most recent 50), joined for display.
      final rows = await _client
          .from('birthday_rewards')
          .select(
            'id, birthday_date, notification_sent, '
            'users(name, email), '
            'promo_codes(code, usage_count, max_uses, is_active, expires_at)',
          )
          .order('birthday_date', ascending: false)
          .limit(50);
      _rows = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updates = {
        'birthday_campaign_enabled': _enabled.toString(),
        'birthday_discount_amount': _discountCtrl.text.trim(),
        'birthday_min_order_amount': _minOrderCtrl.text.trim(),
        'birthday_notification_title': _titleCtrl.text.trim(),
        'birthday_notification_body': _bodyCtrl.text.trim(),
      };
      for (final entry in updates.entries) {
        await _client
            .from('app_config')
            .update({'value': entry.value})
            .eq('key', entry.key);
      }
      if (mounted) AppSnackbar.success(context, 'Birthday campaign settings saved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppConstants.currencySymbol;
    final issued = _rows.length;
    final redeemed = _rows.where((r) {
      final promo = r['promo_codes'] as Map<String, dynamic>?;
      return ((promo?['usage_count'] as num?) ?? 0) > 0;
    }).length;
    final rate = issued == 0 ? 0.0 : (redeemed / issued * 100);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Birthday Campaign',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Stats row ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: _StatCard(label: 'Rewards Issued', value: '$issued')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(label: 'Redeemed', value: '$redeemed')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(label: 'Redemption Rate', value: '${rate.toStringAsFixed(0)}%'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Settings card ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Campaign Settings',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Birthday Campaign'),
                          subtitle: const Text('Master on/off switch for the daily job'),
                          value: _enabled,
                          activeTrackColor: AppTheme.primaryColor,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _discountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Discount amount ($c)',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _minOrderCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Minimum order ($c)',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notification title',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _bodyCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Notification body (use {first_name})',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save Settings',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Recent Birthdays',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  if (_rows.isEmpty)
                    const AppEmptyState(
                      icon: Icons.cake_rounded,
                      title: 'No birthday rewards yet',
                      subtitle: 'They\'ll show up here as customers set their birthday and the daily job runs',
                    )
                  else
                    ..._rows.map((r) => _BirthdayRow(row: r)),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _BirthdayRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final user = row['users'] as Map<String, dynamic>?;
    final promo = row['promo_codes'] as Map<String, dynamic>?;
    final name = (user?['name'] as String?) ?? 'Customer';
    final date = row['birthday_date'] != null
        ? DateFormat('MMM d').format(DateTime.parse(row['birthday_date'] as String))
        : '—';
    final code = promo?['code'] as String?;
    final usageCount = (promo?['usage_count'] as num?)?.toInt() ?? 0;
    final isActive = promo?['is_active'] as bool? ?? false;
    final expiresAt = promo?['expires_at'] != null
        ? DateTime.tryParse(promo!['expires_at'] as String)
        : null;
    final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);

    final status = usageCount > 0
        ? 'Redeemed'
        : isExpired
        ? 'Expired'
        : isActive
        ? 'Available'
        : 'Inactive';
    final statusColor = usageCount > 0
        ? const Color(0xFF10B981)
        : isExpired
        ? Colors.red
        : const Color(0xFF6366F1);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          const Text('🎂', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '$date${code != null ? ' · $code' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
