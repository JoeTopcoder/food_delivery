import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/context_extensions.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _messageCtrl = TextEditingController();
  String _type = 'feature';
  int _rating = 5;
  bool _loading = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.rateFeedback,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rating
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'How are you enjoying FoodHub?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        return GestureDetector(
                          onTap: () => setState(() => _rating = i + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              i < _rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: const Color(0xFFFFA630),
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ratingLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Feedback type
            const Text(
              'Feedback Type',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TypeChip('feature', 'Feature Request', Icons.lightbulb),
                _TypeChip('bug', 'Bug Report', Icons.bug_report),
                _TypeChip('compliment', 'Compliment', Icons.thumb_up),
                _TypeChip('complaint', 'Complaint', Icons.thumb_down),
                _TypeChip('other', 'Other', Icons.more_horiz),
              ],
            ),
            const SizedBox(height: 16),

            // Message
            TextField(
              controller: _messageCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Tell us more...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _submit(userId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Feedback',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Previous feedback
            const Text(
              'Your Feedback History',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _FeedbackHistory(userId: userId),
          ],
        ),
      ),
    );
  }

  // ignore: non_constant_identifier_names
  Widget _TypeChip(String value, String label, IconData icon) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Terrible';
      case 2:
        return 'Poor';
      case 3:
        return 'Average';
      case 4:
        return 'Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }

  Future<void> _submit(String userId) async {
    if (_messageCtrl.text.trim().isEmpty) {
      AppSnackbar.warning(context, 'Please enter your feedback');
      return;
    }
    setState(() => _loading = true);
    final service = ref.read(feedbackServiceProvider);
    await service.submitFeedback(
      userId: userId,
      type: _type,
      message: _messageCtrl.text.trim(),
      rating: _rating,
    );
    setState(() {
      _loading = false;
      _messageCtrl.clear();
    });
    ref.invalidate(userFeedbackProvider(userId));
    if (mounted) {
      AppSnackbar.success(context, 'Thank you for your feedback!');
    }
  }
}

// ── Feedback History ────────────────────────────────────────

class _FeedbackHistory extends ConsumerWidget {
  final String userId;
  const _FeedbackHistory({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackAsync = ref.watch(userFeedbackProvider(userId));
    return feedbackAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No feedback yet',
            subtitle: 'Submit your first feedback above',
          );
        }
        return Column(
          children: items
              .take(5)
              .map(
                (fb) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: Text(
                      fb.typeEmoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(
                      fb.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      fb.typeLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: fb.adminResponse != null
                        ? const Icon(
                            Icons.reply,
                            color: Color(0xFF10B981),
                            size: 18,
                          )
                        : null,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
