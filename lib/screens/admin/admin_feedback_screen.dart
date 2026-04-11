import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/feature_providers.dart';
import '../../models/feedback_model.dart';
import '../../utils/friendly_error.dart';

class AdminFeedbackScreen extends ConsumerStatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  ConsumerState<AdminFeedbackScreen> createState() =>
      _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends ConsumerState<AdminFeedbackScreen> {
  String? _filterType;

  @override
  Widget build(BuildContext context) {
    final feedbackAsync = ref.watch(allFeedbackProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'App Feedback',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _filterType = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              ...AppFeedback.feedbackTypes.map(
                (t) => PopupMenuItem(value: t, child: Text(t.toUpperCase())),
              ),
            ],
          ),
        ],
      ),
      body: feedbackAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (items) {
          final filtered = _filterType == null
              ? items
              : items.where((f) => f.type == _filterType).toList();
          if (filtered.isEmpty) {
            return const Center(child: Text('No feedback yet'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _FeedbackCard(feedback: filtered[i]),
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends ConsumerWidget {
  final AppFeedback feedback;
  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(feedback.typeEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    feedback.typeLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (feedback.rating != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < feedback.rating!
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 16,
                        color: const Color(0xFFFFA630),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(feedback.message, style: const TextStyle(fontSize: 13)),
            if (feedback.appVersion != null) ...[
              const SizedBox(height: 4),
              Text(
                'v${feedback.appVersion}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              DateFormat.yMMMd().format(feedback.createdAt),
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
            if (feedback.adminResponse != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.reply, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      feedback.adminResponse!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.reply, size: 16),
                  label: const Text('Respond'),
                  onPressed: () => _showRespondDialog(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRespondDialog(BuildContext ctx, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Respond to Feedback'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Your response...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final service = ref.read(feedbackServiceProvider);
      await service.respondToFeedback(
        feedbackId: feedback.id,
        response: result,
        status: 'reviewed',
      );
      ref.invalidate(allFeedbackProvider);
    }
  }
}
