import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/student_verification_model.dart';
import '../../providers/student_verification_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

/// Admin: student delivery reviews, verification management, and the
/// participating-school list (Phase 16/23).
class StudentVerificationAdminScreen extends ConsumerStatefulWidget {
  const StudentVerificationAdminScreen({super.key});

  @override
  ConsumerState<StudentVerificationAdminScreen> createState() =>
      _StudentVerificationAdminScreenState();
}

class _StudentVerificationAdminScreenState
    extends ConsumerState<StudentVerificationAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Student Verification',
            style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Reviews'),
            Tab(text: 'Verifications'),
            Tab(text: 'Schools'),
          ],
        ),
      ),
      body: Column(
        children: [
          const _MetricsBar(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _ReviewsTab(),
                _VerificationsTab(),
                _SchoolsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metrics ──────────────────────────────────────────────────────────────────
class _MetricsBar extends ConsumerWidget {
  const _MetricsBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(studentAdminMetricsProvider);
    return m.when(
      loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
      data: (counts) {
        int c(String k) => counts[k] ?? 0;
        final items = <(String, int, Color)>[
          ('Verified', c('approved'), const Color(0xFF067647)),
          ('Pending', c('pending') + c('processing'), const Color(0xFF0E7490)),
          ('Review', c('manual_review'), const Color(0xFF6941C6)),
          ('Needs update', c('needs_update'), const Color(0xFFB54708)),
          ('Expired', c('expired'), const Color(0xFFB54708)),
          ('Suspended', c('suspended'), const Color(0xFFB42318)),
        ];
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final it in items)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: it.$3.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text('${it.$2}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: it.$3)),
                        Text(it.$1,
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Reviews tab ────────────────────────────────────────────────────────────────
class _ReviewsTab extends ConsumerWidget {
  const _ReviewsTab();

  Future<void> _resolve(BuildContext context, WidgetRef ref,
      StudentDeliveryReview r, String action) async {
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(switch (action) {
          'restore' => 'Restore benefits?',
          'keep_suspended' => 'Keep suspended?',
          _ => 'Confirm issue?',
        }),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action == 'restore')
              const Text(
                  'Benefits will be restored only if the student ID has not '
                  'expired.'),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(studentVerificationServiceProvider)
          .resolveReview(r.id, action, notes: notesCtrl.text.trim());
      ref.invalidate(studentReviewsProvider('pending'));
      ref.invalidate(studentAdminMetricsProvider);
      if (context.mounted) AppSnackbar.success(context, 'Review updated');
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentReviewsProvider('pending'));
    final schools = ref.watch(adminAllSchoolsProvider).valueOrNull ?? const [];
    String schoolName(String? id) => id == null
        ? '—'
        : (schools.firstWhere((s) => s.id == id,
                orElse: () => const SchoolOption(id: '', name: 'Unknown school')))
            .name;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(studentReviewsProvider('pending'))),
      data: (reviews) {
        if (reviews.isEmpty) {
          return const AppEmptyState(
            icon: Icons.verified_user_outlined,
            title: 'No pending reviews',
            subtitle: 'Delivery issues reported by drivers will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(studentReviewsProvider('pending')),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = reviews[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.report_gmailerrorred_rounded,
                          color: Color(0xFFB42318), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('School: ${schoolName(r.schoolId)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(r.reason ?? 'Delivery not confirmed at school.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                    const SizedBox(height: 4),
                    Text(
                      'Order ${r.orderId?.substring(0, 8) ?? '—'} · '
                      '${r.createdAt.toLocal().toString().split('.').first}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () =>
                              _resolve(context, ref, r, 'restore'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF067647),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Restore'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              _resolve(context, ref, r, 'keep_suspended'),
                          child: const Text('Keep suspended'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              _resolve(context, ref, r, 'confirm_issue'),
                          child: const Text('Confirm issue'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Verifications tab ────────────────────────────────────────────────────────
class _VerificationsTab extends ConsumerStatefulWidget {
  const _VerificationsTab();
  @override
  ConsumerState<_VerificationsTab> createState() => _VerificationsTabState();
}

class _VerificationsTabState extends ConsumerState<_VerificationsTab> {
  String? _filter;
  static const _filters = [
    null, 'approved', 'manual_review', 'needs_update', 'expired', 'suspended'
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminVerificationsProvider(_filter));
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f == null ? 'All' : f.replaceAll('_', ' ')),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorState(
                message: friendlyError(e),
                onRetry: () =>
                    ref.invalidate(adminVerificationsProvider(_filter))),
            data: (list) {
              if (list.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No verifications',
                  subtitle: 'Student ID submissions will appear here.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final v = list[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.studentName ?? 'Student',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                'ID ${v.studentIdNumber ?? '—'} · '
                                '${v.createdAt.toLocal().toString().split(' ').first}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        _StatusPill(status: v.status),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => const Color(0xFF067647),
      'manual_review' => const Color(0xFF6941C6),
      'needs_update' || 'expired' => const Color(0xFFB54708),
      'suspended' || 'rejected' => const Color(0xFFB42318),
      _ => const Color(0xFF0E7490),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Schools tab ────────────────────────────────────────────────────────────────
class _SchoolsTab extends ConsumerWidget {
  const _SchoolsTab();

  Future<void> _addSchool(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final address = TextEditingController();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add participating school'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'School name *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: address,
                decoration: const InputDecoration(
                    labelText: 'Address', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: code,
                decoration: const InputDecoration(
                    labelText: 'School code', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(studentVerificationServiceProvider).addSchool(
            name: name.text.trim(),
            address: address.text.trim(),
            code: code.text.trim().isEmpty ? null : code.text.trim(),
          );
      ref.invalidate(adminAllSchoolsProvider);
      if (context.mounted) AppSnackbar.success(context, 'School added');
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAllSchoolsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(adminAllSchoolsProvider)),
        data: (schools) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: schools.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final s = schools[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        if (s.address != null && s.address!.isNotEmpty)
                          Text(s.address!,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.isActive,
                    onChanged: (val) async {
                      try {
                        await ref
                            .read(studentVerificationServiceProvider)
                            .setSchoolActive(s.id, val);
                        ref.invalidate(adminAllSchoolsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          AppSnackbar.error(context, friendlyError(e));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSchool(context, ref),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add school',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
