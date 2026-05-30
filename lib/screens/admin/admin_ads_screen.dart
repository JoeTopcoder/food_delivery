import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/restaurant_model.dart';
import '../../providers/admin_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminAdsScreen extends ConsumerStatefulWidget {
  const AdminAdsScreen({super.key});

  @override
  ConsumerState<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends ConsumerState<AdminAdsScreen> {
  List<Map<String, dynamic>> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds() async {
    setState(() => _loading = true);
    try {
      final ads = await ref.read(adminServiceProvider).getRestaurantAds();
      if (mounted)
        setState(() {
          _ads = ads;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Restaurant Ads',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'AI Ad Generator',
            onPressed: _showAiGeneratorDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateAdDialog,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Ad',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAds,
        color: AppTheme.primaryColor,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ads.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No ads yet',
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: _ads.length,
                itemBuilder: (context, index) =>
                    _AdCard(ad: _ads[index], onChanged: _loadAds, ref: ref),
              ),
      ),
    );
  }

  void _showAiGeneratorDialog() async {
    List<Restaurant> restaurants = [];
    try {
      restaurants = await ref
          .read(adminServiceProvider)
          .getAllRestaurants(offset: 0, limit: 500);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
      return;
    }

    if (!mounted) return;
    if (restaurants.isEmpty) {
      AppSnackbar.error(context, 'No restaurants found');
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _AiAdGeneratorDialog(
        restaurants: restaurants,
        ref: ref,
        onCreated: () {
          ref.invalidate(activeAdsProvider);
          _loadAds();
        },
      ),
    );
  }

  void _showCreateAdDialog() async {
    // First load restaurants for the dropdown
    List<Restaurant> restaurants = [];
    try {
      restaurants = await ref
          .read(adminServiceProvider)
          .getAllRestaurants(offset: 0, limit: 500);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
      return;
    }

    if (!mounted) return;
    if (restaurants.isEmpty) {
      AppSnackbar.error(context, 'No restaurants found');
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _CreateAdDialog(
        restaurants: restaurants,
        ref: ref,
        onCreated: () {
          ref.invalidate(activeAdsProvider);
          _loadAds();
        },
      ),
    );
  }
}

// ─── Ad card ─────────────────────────────────────────────────────────────────

class _AdCard extends StatelessWidget {
  final Map<String, dynamic> ad;
  final VoidCallback onChanged;
  final WidgetRef ref;

  const _AdCard({required this.ad, required this.onChanged, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isActive = ad['is_active'] == true;
    final restaurantData = ad['restaurants'];
    final restaurantName = restaurantData is Map
        ? restaurantData['name'] ?? 'Unknown'
        : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive ? Icons.campaign_rounded : Icons.pause_circle,
                    color: isActive ? const Color(0xFF10B981) : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad['title'] ?? 'Untitled',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        restaurantName.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(isActive: isActive),
              ],
            ),

            if (ad['description'] != null &&
                (ad['description'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                ad['description'],
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 8),

            // Info chips
            Row(
              children: [
                _InfoChip(
                  icon: Icons.trending_up_rounded,
                  label: ad['commission_rate'] != null
                      ? '+${ad['commission_rate']}% commission'
                      : 'Featured Ad',
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                if (ad['ends_at'] != null)
                  _InfoChip(
                    icon: Icons.schedule,
                    label: 'Ends ${_formatDate(ad['ends_at'])}',
                    color: const Color(0xFF6366F1),
                  )
                else if (ad['starts_at'] != null)
                  _InfoChip(
                    icon: Icons.schedule,
                    label: _formatDate(ad['starts_at']),
                    color: const Color(0xFF6366F1),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleActive(context, !isActive),
                    icon: Icon(
                      isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 16,
                    ),
                    label: Text(isActive ? 'Pause' : 'Activate'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isActive
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                      side: BorderSide(
                        color: isActive
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteAd(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _toggleActive(BuildContext context, bool newValue) async {
    try {
      await ref.read(adminServiceProvider).toggleAdActive(ad['id'], newValue);
      ref.invalidate(activeAdsProvider);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _deleteAd(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Ad?'),
        content: Text('Delete "${ad['title']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteRestaurantAd(ad['id']);
      ref.invalidate(activeAdsProvider);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ─── Create Ad Dialog ────────────────────────────────────────────────────────

class _CreateAdDialog extends StatefulWidget {
  final List<Restaurant> restaurants;
  final WidgetRef ref;
  final VoidCallback onCreated;

  const _CreateAdDialog({
    required this.restaurants,
    required this.ref,
    required this.onCreated,
  });

  @override
  State<_CreateAdDialog> createState() => _CreateAdDialogState();
}

class _CreateAdDialogState extends State<_CreateAdDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Restaurant? _selectedRestaurant;
  DateTime? _endsAt;
  bool _creating = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endsAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.campaign_rounded, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          const Text('Create New Ad', style: TextStyle(fontSize: 17)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Restaurant dropdown
            DropdownButtonFormField<Restaurant>(
              initialValue: _selectedRestaurant,
              decoration: InputDecoration(
                labelText: 'Restaurant *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              isExpanded: true,
              items: widget.restaurants.map((r) {
                return DropdownMenuItem(
                  value: r,
                  child: Text(
                    r.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedRestaurant = val),
            ),
            const SizedBox(height: 14),

            // Title
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Ad Title *',
                hintText: 'e.g. Buy 1, get 1 free',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Description
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'e.g. Valid on all combos this weekend',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            // End date picker
            GestureDetector(
              onTap: _pickEndDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _endsAt == null
                            ? 'No end date (runs indefinitely)'
                            : 'Ends: ${_endsAt!.day}/${_endsAt!.month}/${_endsAt!.year}',
                        style: TextStyle(
                          fontSize: 14,
                          color: _endsAt == null
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF111827),
                        ),
                      ),
                    ),
                    if (_endsAt != null)
                      GestureDetector(
                        onTap: () => setState(() => _endsAt = null),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _creating ? null : _createAd,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create Ad'),
        ),
      ],
    );
  }

  Future<void> _createAd() async {
    if (_selectedRestaurant == null) {
      AppSnackbar.error(context, 'Please select a restaurant');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Please enter a title');
      return;
    }

    setState(() => _creating = true);
    try {
      await widget.ref
          .read(adminServiceProvider)
          .createRestaurantAd(
            restaurantId: _selectedRestaurant!.id,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            endsAt: _endsAt,
          );
      widget.onCreated();
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(context, 'Ad created!');
      }
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ─── Helper widgets ──────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Paused',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? const Color(0xFF10B981) : Colors.grey,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI Ad Generator Dialog ──────────────────────────────────────────────────

class _AiAdGeneratorDialog extends StatefulWidget {
  final List<Restaurant> restaurants;
  final WidgetRef ref;
  final VoidCallback onCreated;

  const _AiAdGeneratorDialog({
    required this.restaurants,
    required this.ref,
    required this.onCreated,
  });

  @override
  State<_AiAdGeneratorDialog> createState() => _AiAdGeneratorDialogState();
}

class _AiAdGeneratorDialogState extends State<_AiAdGeneratorDialog> {
  final _briefCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ctaCtrl = TextEditingController();

  Restaurant? _selectedRestaurant;
  bool _generating = false;
  bool _publishing = false;
  bool _hasPreview = false;

  @override
  void dispose() {
    _briefCtrl.dispose();
    _imageCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_selectedRestaurant == null) {
      AppSnackbar.error(context, 'Please select a restaurant');
      return;
    }
    if (_briefCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Please describe the ad you want');
      return;
    }

    setState(() => _generating = true);
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'generate-ad',
        body: {
          'restaurant_name': _selectedRestaurant!.name,
          'brief': _briefCtrl.text.trim(),
        },
      );

      final data = res.data is String
          ? jsonDecode(res.data as String) as Map<String, dynamic>
          : res.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      setState(() {
        _titleCtrl.text = (data['title'] ?? '').toString();
        _descCtrl.text = (data['description'] ?? '').toString();
        _ctaCtrl.text = (data['cta_text'] ?? 'Order Now').toString();
        _hasPreview = true;
        _generating = false;
      });
    } catch (e) {
      setState(() => _generating = false);
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Title cannot be empty');
      return;
    }

    setState(() => _publishing = true);
    try {
      await widget.ref.read(adminServiceProvider).createRestaurantAd(
            restaurantId: _selectedRestaurant!.id,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            imageUrl: _imageCtrl.text.trim().isEmpty
                ? null
                : _imageCtrl.text.trim(),
          );
      widget.onCreated();
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(context, 'Ad published to customers!');
      }
    } catch (e) {
      setState(() => _publishing = false);
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('AI Ad Generator', style: TextStyle(fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // Restaurant dropdown
              DropdownButtonFormField<Restaurant>(
                initialValue: _selectedRestaurant,
                decoration: InputDecoration(
                  labelText: 'Restaurant *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                isExpanded: true,
                items: widget.restaurants.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text(r.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedRestaurant = val),
              ),
              const SizedBox(height: 12),

              // Brief
              TextField(
                controller: _briefCtrl,
                decoration: InputDecoration(
                  labelText: 'Describe the ad *',
                  hintText:
                      'e.g. 20% off burgers this weekend, use code BURGER20',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 12),

              // Image URL (optional)
              TextField(
                controller: _imageCtrl,
                decoration: InputDecoration(
                  labelText: 'Image URL (optional)',
                  hintText: 'https://...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Generate button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_generating || _publishing) ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF7C3AED).withValues(alpha: 0.5),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    _generating ? 'Generating...' : 'Generate with AI',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // Preview section
              if (_hasPreview) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Preview — edit if needed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 10),

                // Generated title (editable)
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                // Generated description (editable)
                TextField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),

                // CTA text (editable)
                TextField(
                  controller: _ctaCtrl,
                  decoration: InputDecoration(
                    labelText: 'Button label',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Publish button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_generating || _publishing) ? null : _publish,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFF10B981).withValues(alpha: 0.5),
                    ),
                    icon: _publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.rocket_launch_rounded, size: 18),
                    label: Text(
                      _publishing
                          ? 'Publishing...'
                          : 'Publish Ad to Customers',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_generating || _publishing)
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
