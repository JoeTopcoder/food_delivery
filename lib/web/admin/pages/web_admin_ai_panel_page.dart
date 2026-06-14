import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../providers/decision_engine_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebAdminAiPanelPage extends ConsumerStatefulWidget {
  const WebAdminAiPanelPage({super.key});

  @override
  ConsumerState<WebAdminAiPanelPage> createState() => _WebAdminAiPanelPageState();
}

class _WebAdminAiPanelPageState extends ConsumerState<WebAdminAiPanelPage> {
  bool _running = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(segmentDistributionProvider);
      ref.invalidate(promotionStatsProvider);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _runEngine() async {
    setState(() => _running = true);
    try {
      await ref.read(decisionEngineServiceProvider).runDecisionEngine();
      ref.invalidate(segmentDistributionProvider);
      ref.invalidate(promotionStatsProvider);
      if (mounted) AppSnackbar.success(context, 'Engine ran — segments & promos updated!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segmentAsync = ref.watch(segmentDistributionProvider);
    final promoAsync = ref.watch(promotionStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Decision Engine', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('User segmentation, automated promotions, and engine control', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                onPressed: () {
                  ref.invalidate(segmentDistributionProvider);
                  ref.invalidate(promotionStatsProvider);
                },
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _running ? null : _runEngine,
                icon: _running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_circle_filled_rounded, size: 18, color: Colors.white),
                label: Text(_running ? 'Running…' : 'Run Engine Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── AI Info banner ───────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.psychology_rounded, color: AppTheme.primaryColor, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart Segmentation Engine', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Automatically segments users by behavior, assigns promotional strategies, and optimises discount targeting. Runs every 30 seconds in background.', style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Two-column layout ────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: User Segments
              Expanded(
                child: _PanelCard(
                  title: 'User Segments',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF6366F1),
                  child: segmentAsync.when(
                    loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
                    error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(segmentDistributionProvider))),
                    data: (rows) => rows.isEmpty
                        ? const Padding(padding: EdgeInsets.all(40), child: AppEmptyState(icon: Icons.people_outline_rounded, title: 'No segment data yet', subtitle: 'Run the engine to generate segments'))
                        : Column(
                            children: rows.map((row) {
                              final color = _segmentColor(row.segment);
                              final totalUsers = rows.fold<int>(0, (s, r) => s + r.userCount);
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                child: Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                    child: Text(row.segment, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: totalUsers > 0 ? row.userCount / totalUsers : 0,
                                      backgroundColor: color.withValues(alpha: 0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(color),
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('${row.userCount}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
                                ]),
                              );
                            }).toList(),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Right: Promotion Stats
              Expanded(
                child: _PanelCard(
                  title: 'Promotion Activity',
                  icon: Icons.local_offer_rounded,
                  color: const Color(0xFF10B981),
                  child: promoAsync.when(
                    loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
                    error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(promotionStatsProvider))),
                    data: (rows) => rows.isEmpty
                        ? const Padding(padding: EdgeInsets.all(40), child: AppEmptyState(icon: Icons.discount_outlined, title: 'No promotion data yet', subtitle: 'Run the engine to generate promotions'))
                        : Column(
                            children: rows.map((row) {
                              final fmt = NumberFormat('#,###');
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Row(children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(row.label ?? row.type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                    Text('${AppConstants.currencySymbol}${fmt.format(row.revenueGenerated)} generated · ${row.targetSegment}', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                  ])),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text('${row.used}/${row.sent}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                                    Text('${(row.conversionRate * 100).toStringAsFixed(1)}% conv.', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                  ]),
                                ]),
                              );
                            }).toList(),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _segmentColor(String s) {
    switch (s.toLowerCase()) {
      case 'high_value': return const Color(0xFF6366F1);
      case 'at_risk': return const Color(0xFFEF4444);
      case 'new': return const Color(0xFF10B981);
      case 'loyal': return const Color(0xFFF59E0B);
      case 'occasional': return const Color(0xFF0EA5E9);
      default: return const Color(0xFF9CA3AF);
    }
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  const _PanelCard({required this.title, required this.icon, required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ]),
        ),
        const Divider(height: 1),
        child,
        const SizedBox(height: 8),
      ],
    ),
  );
}
