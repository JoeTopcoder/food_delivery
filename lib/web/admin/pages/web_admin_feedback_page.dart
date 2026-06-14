import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/feedback_model.dart';
import '../../../providers/feature_providers.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminFeedbackPage extends ConsumerStatefulWidget {
  const WebAdminFeedbackPage({super.key});

  @override
  ConsumerState<WebAdminFeedbackPage> createState() => _WebAdminFeedbackPageState();
}

class _WebAdminFeedbackPageState extends ConsumerState<WebAdminFeedbackPage> {
  String? _filterType;

  @override
  Widget build(BuildContext context) {
    final feedbackAsync = ref.watch(allFeedbackProvider);

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
                    Text('App Feedback', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('User-submitted feedback and ratings', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              // Type filter chips
              feedbackAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (_) => Wrap(
                  spacing: 8,
                  children: [
                    _FilterChip(label: 'All', selected: _filterType == null, onTap: () => setState(() => _filterType = null)),
                    ...AppFeedback.feedbackTypes.map((t) => _FilterChip(
                      label: t.toUpperCase(),
                      selected: _filterType == t,
                      onTap: () => setState(() => _filterType = _filterType == t ? null : t),
                    )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(allFeedbackProvider)),
            ],
          ),
          const SizedBox(height: 24),

          feedbackAsync.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allFeedbackProvider)),
            data: (items) {
              final filtered = _filterType == null ? items : items.where((f) => f.type == _filterType).toList();
              if (filtered.isEmpty) {
                return const AppEmptyState(icon: Icons.feedback_outlined, title: 'No feedback yet');
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, childAspectRatio: 1.3, crossAxisSpacing: 14, mainAxisSpacing: 14),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _FeedbackCard(feedback: filtered[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF004E89) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : const Color(0xFF64748B))),
    ),
  );
}

class _FeedbackCard extends ConsumerWidget {
  final AppFeedback feedback;
  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ────────────────────────────────────────────
          Row(
            children: [
              Text(feedback.typeEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF6B7280).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(feedback.typeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
              ),
              const Spacer(),
              if (feedback.rating != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => Icon(
                    i < feedback.rating! ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 14,
                    color: const Color(0xFFFFA630),
                  )),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Message ────────────────────────────────────────────
          Expanded(
            child: Text(feedback.message, style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5), overflow: TextOverflow.fade),
          ),
          const SizedBox(height: 6),

          // ── Meta ───────────────────────────────────────────────
          Row(
            children: [
              if (feedback.appVersion != null) ...[
                Text('v${feedback.appVersion}', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                const Text(' · ', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
              Text(DateFormat.yMMMd().format(feedback.createdAt), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ),

          // ── Admin response or respond button ───────────────────
          if (feedback.adminResponse != null) ...[
            const Divider(height: 14),
            Row(
              children: [
                const Icon(Icons.reply, size: 13, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Expanded(child: Text(feedback.adminResponse!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF10B981)), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.reply, size: 14),
                label: const Text('Respond', style: TextStyle(fontSize: 12)),
                onPressed: () => _showRespondDialog(context, ref),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRespondDialog(BuildContext ctx, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Respond to Feedback'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(feedback.message, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Your response…', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(feedbackServiceProvider).respondToFeedback(feedbackId: feedback.id, response: result, status: 'reviewed');
      ref.invalidate(allFeedbackProvider);
      if (ctx.mounted) AppSnackbar.success(ctx, 'Response sent');
    }
  }
}
