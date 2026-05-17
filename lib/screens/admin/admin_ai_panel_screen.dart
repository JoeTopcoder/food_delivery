import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/decision_engine_provider.dart';
import '../../services/ai/decision_engine_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';

class AdminAiPanelScreen extends ConsumerStatefulWidget {
  const AdminAiPanelScreen({super.key});

  @override
  ConsumerState<AdminAiPanelScreen> createState() => _AdminAiPanelScreenState();
}

class _AdminAiPanelScreenState extends ConsumerState<AdminAiPanelScreen> {
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
      if (mounted)
        AppSnackbar.success(context, 'Engine ran — segments & promos updated!');
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

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'AI Engine',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_running)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline_rounded),
              tooltip: 'Run decision engine now',
              onPressed: _runEngine,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(segmentDistributionProvider);
          ref.invalidate(promotionStatsProvider);
          ref.invalidate(promotionConfigsProvider);
        },
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── AI Recommendation Banner ──────────────────────────
            _RecommendationBanner(
              segmentAsync: segmentAsync,
              promoAsync: promoAsync,
            ),

            const SizedBox(height: 16),

            // ── User Segments ─────────────────────────────────────
            _PanelCard(
              title: 'User Segments',
              icon: Icons.people_alt_rounded,
              iconColor: const Color(0xFF6366F1),
              child: segmentAsync.when(
                data: (rows) => rows.isEmpty
                    ? const _EmptyState(
                        label: 'No segment data — run the engine',
                      )
                    : _SegmentChart(rows: rows),
                loading: () => const _Skeleton(height: 160),
                error: (e, _) => _ErrorCard(message: friendlyError(e)),
              ),
            ),

            const SizedBox(height: 16),

            // ── Promotion Caps (admin-editable) ───────────────────
            _PanelCard(
              title: 'AI Promotion Caps',
              icon: Icons.tune_rounded,
              iconColor: const Color(0xFF8B5CF6),
              child: Consumer(
                builder: (context, ref, _) {
                  final cfgAsync = ref.watch(promotionConfigsProvider);
                  return cfgAsync.when(
                    data: (rows) => rows.isEmpty
                        ? const _EmptyState(
                            label: 'No promotions configured yet',
                          )
                        : _PromoConfigEditor(rows: rows),
                    loading: () => const _Skeleton(height: 160),
                    error: (e, _) => _ErrorCard(message: friendlyError(e)),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── Promo Performance ─────────────────────────────────
            _PanelCard(
              title: 'Promo Performance',
              icon: Icons.discount_rounded,
              iconColor: const Color(0xFF10B981),
              child: promoAsync.when(
                data: (rows) => rows.isEmpty
                    ? const _EmptyState(label: 'No promos configured yet')
                    : _PromoTable(rows: rows),
                loading: () => const _Skeleton(height: 200),
                error: (e, _) => _ErrorCard(message: friendlyError(e)),
              ),
            ),

            const SizedBox(height: 16),

            // ── How It Works ──────────────────────────────────────
            _PanelCard(
              title: 'How The Engine Works',
              icon: Icons.settings_suggest_rounded,
              iconColor: const Color(0xFFF59E0B),
              child: const _EngineExplainer(),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Recommendation Banner ────────────────────────────────────────────────────

class _RecommendationBanner extends StatelessWidget {
  final AsyncValue<List<SegmentRow>> segmentAsync;
  final AsyncValue<List<PromoStat>> promoAsync;

  const _RecommendationBanner({
    required this.segmentAsync,
    required this.promoAsync,
  });

  @override
  Widget build(BuildContext context) {
    final segments = segmentAsync.valueOrNull ?? [];
    final promos = promoAsync.valueOrNull ?? [];
    final rec = DecisionEngineService.buildRecommendation(
      segments: segments,
      promos: promos,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Recommendation',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rec,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Segment Chart (bar-style) ────────────────────────────────────────────────

class _SegmentChart extends StatelessWidget {
  final List<SegmentRow> rows;
  const _SegmentChart({required this.rows});

  static const _segmentColors = {
    'new': Color(0xFF6366F1),
    'active': Color(0xFF10B981),
    'loyal': Color(0xFFF59E0B),
    'at_risk': Color(0xFFEF4444),
  };

  static const _segmentIcons = {
    'new': Icons.fiber_new_rounded,
    'active': Icons.check_circle_rounded,
    'loyal': Icons.favorite_rounded,
    'at_risk': Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: rows.map((r) {
        final color = _segmentColors[r.segment] ?? const Color(0xFF6B7280);
        final icon = _segmentIcons[r.segment] ?? Icons.person_rounded;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    _label(r.segment),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${r.userCount} users · ${r.pct.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: r.pct / 100,
                  minHeight: 8,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _label(String seg) {
    switch (seg) {
      case 'new':
        return 'New';
      case 'active':
        return 'Active';
      case 'loyal':
        return 'Loyal';
      case 'at_risk':
        return 'At Risk';
      default:
        return seg;
    }
  }
}

// ─── Promo Table ──────────────────────────────────────────────────────────────

class _PromoTable extends StatelessWidget {
  final List<PromoStat> rows;
  const _PromoTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final cur = AppConstants.currencySymbol;
    final fmt = NumberFormat('#,##0');

    return Column(
      children: [
        // Header
        Row(
          children: const [
            Expanded(flex: 4, child: Text('Promo', style: _headerStyle)),
            Expanded(flex: 2, child: Text('Sent', style: _headerStyle)),
            Expanded(flex: 2, child: Text('Conv.', style: _headerStyle)),
            Expanded(flex: 3, child: Text('Revenue', style: _headerStyle)),
          ],
        ),
        const Divider(height: 10),
        ...rows.map((r) {
          final isBad = r.sent > 10 && r.conversionRate < 0.05;
          final isGood = r.conversionRate > 0.20;
          final convColor = isBad
              ? const Color(0xFFEF4444)
              : isGood
              ? const Color(0xFF10B981)
              : const Color(0xFF6B7280);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.label ?? r.targetSegment,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _typeLabel(r.type, r.value),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.sent}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    r.sent == 0
                        ? '—'
                        : '${(r.conversionRate * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: convColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '$cur${fmt.format(r.revenueGenerated)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _typeLabel(String type, double value) {
    switch (type) {
      case 'discount':
        return '${value.toStringAsFixed(0)}% off';
      case 'fixed':
        return '${AppConstants.currencySymbol}${value.toStringAsFixed(0)} off';
      case 'free_delivery':
        return 'Free delivery';
      default:
        return type;
    }
  }

  static const _headerStyle = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 11,
    color: Color(0xFF6B7280),
  );
}

// ─── Engine Explainer ─────────────────────────────────────────────────────────

class _EngineExplainer extends StatelessWidget {
  const _EngineExplainer();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        '1. Collect',
        'Orders, sessions, and events feed the system.',
        Icons.input_rounded,
      ),
      (
        '2. Segment',
        'Users are classified: New, Active, Loyal, At-Risk.',
        Icons.pie_chart_rounded,
      ),
      (
        '3. Decide',
        'Targeted promos are assigned per segment.',
        Icons.auto_fix_high_rounded,
      ),
      (
        '4. Price',
        'Delivery fee adjusts to real-time supply/demand.',
        Icons.trending_up_rounded,
      ),
      (
        '5. Measure',
        'Conversion rates kill bad promos automatically.',
        Icons.bar_chart_rounded,
      ),
    ];

    return Column(
      children: steps.map((s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(s.$3, color: AppTheme.primaryColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      s.$2,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double height;
  const _Skeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Promotion Config Editor ──────────────────────────────────────────────────

class _PromoConfigEditor extends ConsumerStatefulWidget {
  final List<PromotionConfig> rows;
  const _PromoConfigEditor({required this.rows});

  @override
  ConsumerState<_PromoConfigEditor> createState() => _PromoConfigEditorState();
}

class _PromoConfigEditorState extends ConsumerState<_PromoConfigEditor> {
  static const _segmentOrder = ['new', 'active', 'loyal', 'at_risk', 'all'];
  static const _segmentLabels = {
    'new': 'New users',
    'active': 'Regular (active)',
    'loyal': 'Loyal',
    'at_risk': 'At risk',
    'all': 'Everyone',
  };
  static const _segmentColors = {
    'new': Color(0xFF6366F1),
    'active': Color(0xFF10B981),
    'loyal': Color(0xFFF59E0B),
    'at_risk': Color(0xFFEF4444),
    'all': Color(0xFF6B7280),
  };

  // Local edits keyed by row id, only flushed on Save.
  final Map<String, double> _editedValue = {};
  final Map<String, double> _editedMin = {};
  final Map<String, bool> _editedActive = {};
  String? _saving;

  Future<void> _save(PromotionConfig r) async {
    final newValue = _editedValue[r.id] ?? r.value;
    final newMin = _editedMin[r.id] ?? r.minOrder;
    final newActive = _editedActive[r.id] ?? r.active;
    if (newValue == r.value && newMin == r.minOrder && newActive == r.active) {
      return;
    }

    // Sanity caps so the AI can never give away too much early.
    if (r.type == 'discount' && (newValue < 0 || newValue > 50)) {
      AppSnackbar.error(context, 'Discount % must be between 0 and 50.');
      return;
    }
    if (newMin < 0) {
      AppSnackbar.error(context, 'Min order must be 0 or greater.');
      return;
    }

    setState(() => _saving = r.id);
    try {
      await ref
          .read(decisionEngineServiceProvider)
          .updatePromotionConfig(
            id: r.id,
            value: newValue,
            minOrder: newMin,
            active: newActive,
          );
      ref.invalidate(promotionConfigsProvider);
      ref.invalidate(promotionStatsProvider);
      if (mounted) AppSnackbar.success(context, 'Saved.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = AppConstants.currencySymbol;
    final sorted = [...widget.rows]
      ..sort((a, b) {
        final ai = _segmentOrder.indexOf(a.targetSegment);
        final bi = _segmentOrder.indexOf(b.targetSegment);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set the maximum discount the AI is allowed to assign per segment. '
          'Discounts are capped at 50%.',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        ...sorted.map((r) {
          final color =
              _segmentColors[r.targetSegment] ?? const Color(0xFF6B7280);
          final segLabel = _segmentLabels[r.targetSegment] ?? r.targetSegment;
          final value = _editedValue[r.id] ?? r.value;
          final minOrder = _editedMin[r.id] ?? r.minOrder;
          final active = _editedActive[r.id] ?? r.active;
          final dirty =
              value != r.value || minOrder != r.minOrder || active != r.active;
          final isPct = r.type == 'discount';
          final isFreeDelivery = r.type == 'free_delivery';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        segLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.label ?? '—',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch.adaptive(
                      value: active,
                      onChanged: (v) => setState(() => _editedActive[r.id] = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isFreeDelivery)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Free delivery — no % to set.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          label: isPct ? 'Discount %' : 'Amount $cur',
                          initial: value,
                          suffix: isPct ? '%' : cur,
                          max: isPct ? 50 : 9999,
                          onChanged: (v) =>
                              setState(() => _editedValue[r.id] = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumberField(
                          label: 'Min order $cur',
                          initial: minOrder,
                          suffix: cur,
                          max: 99999,
                          onChanged: (v) =>
                              setState(() => _editedMin[r.id] = v),
                        ),
                      ),
                    ],
                  ),
                if (isPct) ...[
                  const SizedBox(height: 6),
                  Slider(
                    value: value.clamp(0, 50).toDouble(),
                    min: 0,
                    max: 50,
                    divisions: 50,
                    label: '${value.toStringAsFixed(0)}%',
                    activeColor: color,
                    onChanged: (v) =>
                        setState(() => _editedValue[r.id] = v.roundToDouble()),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: dirty && _saving != r.id ? () => _save(r) : null,
                    icon: _saving == r.id
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final double initial;
  final String suffix;
  final double max;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.label,
    required this.initial,
    required this.suffix,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial == widget.initial.truncateToDouble()
        ? widget.initial.toStringAsFixed(0)
        : widget.initial.toString(),
  );

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial &&
        double.tryParse(_ctrl.text) != widget.initial) {
      _ctrl.text = widget.initial == widget.initial.truncateToDouble()
          ? widget.initial.toStringAsFixed(0)
          : widget.initial.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (s) {
        final n = double.tryParse(s.trim());
        if (n != null && n >= 0 && n <= widget.max) widget.onChanged(n);
      },
    );
  }
}
