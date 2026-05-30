import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../models/order_model.dart';
import '../../providers/user_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final Order order;
  const ReviewScreen({super.key, required this.order});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _foodRating = 0;
  int _deliveryRating = 0;
  int _packagingRating = 0;
  final _reviewCtrl = TextEditingController();
  File? _photo;
  bool _loading = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _submit() async {
    if (_foodRating == 0 || _deliveryRating == 0 || _packagingRating == 0) {
      AppSnackbar.warning(context, 'Please rate all three categories');
      return;
    }
    setState(() => _loading = true);
    try {
      final service = ref.read(orderServiceProvider);
      final overall = ((_foodRating + _deliveryRating + _packagingRating) / 3)
          .roundToDouble();

      // Upload photo if provided
      String? photoUrl;
      if (_photo != null) {
        try {
          final fileName =
              'reviews/${widget.order.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final bytes = await _photo!.readAsBytes();
          await Supabase.instance.client.storage
              .from('review-photos')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          photoUrl = Supabase.instance.client.storage
              .from('review-photos')
              .getPublicUrl(fileName);
        } catch (_) {
          // Photo upload failed silently - still submit review without photo
        }
      }

      await service.addReview(
        orderId: widget.order.id,
        rating: overall,
        review: _reviewCtrl.text.trim().isEmpty
            ? null
            : _reviewCtrl.text.trim(),
        foodRating: _foodRating,
        deliveryRating: _deliveryRating,
        packagingRating: _packagingRating,
        photoUrl: photoUrl,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        AppSnackbar.success(context, 'Review submitted! Thank you.');
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rate Your Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${widget.order.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${widget.order.items.length} item(s) · \$${widget.order.totalAmount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Delivered',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Rating categories
            _RatingCategory(
              title: 'Food Quality',
              subtitle: 'How was the food taste and presentation?',
              icon: Icons.restaurant_rounded,
              color: AppTheme.primaryColor,
              value: _foodRating,
              onChanged: (v) => setState(() => _foodRating = v),
            ),
            const SizedBox(height: 12),
            _RatingCategory(
              title: 'Delivery Speed',
              subtitle: 'How fast was the delivery?',
              icon: Icons.directions_bike_rounded,
              color: const Color(0xFF10B981),
              value: _deliveryRating,
              onChanged: (v) => setState(() => _deliveryRating = v),
            ),
            const SizedBox(height: 12),
            _RatingCategory(
              title: 'Packaging',
              subtitle: 'Was the food packaged well?',
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFF6366F1),
              value: _packagingRating,
              onChanged: (v) => setState(() => _packagingRating = v),
            ),

            const SizedBox(height: 20),

            // Overall summary
            if (_foodRating > 0 && _deliveryRating > 0 && _packagingRating > 0)
              _OverallScore(
                food: _foodRating,
                delivery: _deliveryRating,
                packaging: _packagingRating,
              ),

            const SizedBox(height: 20),

            // Written review
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Write a Review (optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reviewCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Share your experience with this restaurant...',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Photo upload
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        color: Color(0xFF6366F1),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _photo != null
                            ? 'Photo added ✓'
                            : 'Add a photo (optional)',
                        style: TextStyle(
                          fontSize: 13,
                          color: _photo != null
                              ? Colors.green
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: _photo != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (_photo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _photo!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Review',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Rating Category Widget ──────────────────────────────────────────────────

class _RatingCategory extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => GestureDetector(
                onTap: () => onChanged(i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < value ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < value
                        ? const Color(0xFFF59E0B)
                        : Theme.of(context).colorScheme.outlineVariant,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
          if (value > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                _label(value),
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _label(int v) {
    switch (v) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}

// ─── Overall Score ────────────────────────────────────────────────────────────

class _OverallScore extends StatelessWidget {
  final int food;
  final int delivery;
  final int packaging;
  const _OverallScore({
    required this.food,
    required this.delivery,
    required this.packaging,
  });

  @override
  Widget build(BuildContext context) {
    final overall = (food + delivery + packaging) / 3;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                overall.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < overall.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar('Food', food, Colors.white),
                const SizedBox(height: 6),
                _bar('Delivery', delivery, Colors.white),
                const SizedBox(height: 6),
                _bar('Packaging', packaging, Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(String label, int val, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: val / 5,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(
                color.withValues(alpha: 0.9),
              ),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$val',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
