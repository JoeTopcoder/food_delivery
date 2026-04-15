import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: currentUser?.profileImageUrl != null
                            ? NetworkImage(currentUser!.profileImageUrl!)
                            : null,
                        child: currentUser?.profileImageUrl == null
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () =>
                              _pickAndUploadPhoto(context, ref, currentUser),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentUser?.name ?? 'User',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.email ?? '',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.createdAt != null
                        ? 'Member since ${DateFormat.yMMM().format(currentUser!.createdAt)}'
                        : '',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  if (currentUserId != null) _buildOrderStats(currentUserId),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // My Activity
            _SectionTitle('My Activity'),
            _SettingsTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Digital Wallet',
              subtitle: 'Add funds, view balance & cashback',
              onTap: () => Navigator.of(context).pushNamed('/wallet'),
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Order History',
              subtitle: 'View your past orders',
              onTap: () => Navigator.of(context).pushNamed('/order-history'),
            ),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              title: 'Address Book',
              subtitle: 'Manage saved addresses',
              onTap: () => Navigator.of(context).pushNamed('/address-book'),
            ),
            _SettingsTile(
              icon: Icons.card_giftcard_outlined,
              title: 'Loyalty Points',
              subtitle: 'Earn & redeem points',
              onTap: () => Navigator.of(context).pushNamed('/loyalty'),
            ),
            _SettingsTile(
              icon: Icons.favorite_outlined,
              title: 'Favorites',
              subtitle: 'Your favorite restaurants',
              onTap: () => Navigator.of(context).pushNamed('/favorites'),
            ),
            _SettingsTile(
              icon: Icons.people_outlined,
              title: 'Refer a Friend',
              subtitle: 'Earn rewards for referrals',
              onTap: () => Navigator.of(context).pushNamed('/referrals'),
            ),
            _SettingsTile(
              icon: Icons.search_rounded,
              title: 'Search & Discover',
              subtitle: 'Find restaurants with filters',
              onTap: () => Navigator.of(context).pushNamed('/search'),
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Refunds & Disputes',
              subtitle: 'Request refunds or report issues',
              onTap: () => Navigator.of(context).pushNamed('/refund-dispute'),
            ),
            _SettingsTile(
              icon: Icons.group_outlined,
              title: 'Group Orders',
              subtitle: 'Order together with friends',
              onTap: () => Navigator.of(context).pushNamed('/group-orders'),
            ),
            _SettingsTile(
              icon: Icons.card_membership_outlined,
              title: 'Subscriptions',
              subtitle: 'Meal plans & subscriptions',
              onTap: () => Navigator.of(context).pushNamed('/subscriptions'),
            ),
            _SettingsTile(
              icon: Icons.feedback_outlined,
              title: 'Rate & Feedback',
              subtitle: 'Tell us how we\'re doing',
              onTap: () => Navigator.of(context).pushNamed('/feedback'),
            ),
            const SizedBox(height: 24),

            // Account Settings
            _SectionTitle('Account Settings'),
            _SettingsTile(
              icon: Icons.phone_outlined,
              title: 'Phone Number',
              subtitle: currentUser?.phone ?? 'Not set',
              onTap: () => _showEditPhoneDialog(context, ref, currentUser),
            ),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              title: 'Address',
              subtitle: currentUser?.address ?? 'Not set',
              onTap: () => Navigator.of(context).pushNamed('/address-book'),
            ),
            _SettingsTile(
              icon: Icons.payment_outlined,
              title: 'Payment Methods',
              subtitle: 'Manage payment methods',
              onTap: () {
                AppSnackbar.info(
                  context,
                  'Payment methods are configured at checkout',
                );
              },
            ),
            const SizedBox(height: 24),

            // Preferences
            _SectionTitle('Preferences'),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Manage notification settings',
              onTap: () => Navigator.of(context).pushNamed('/notifications'),
            ),
            _SettingsTile(
              icon: Icons.language_outlined,
              title: 'Language & Region',
              subtitle: 'English (US)',
              onTap: () => _showLanguageDialog(context),
            ),
            const SizedBox(height: 24),

            // Logout Button
            ElevatedButton(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(
    BuildContext context,
    WidgetRef ref,
    dynamic currentUser,
  ) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final userId = currentUser?.id as String?;
      if (userId == null) return;
      final fileName = 'profile-photos/$userId.jpg';

      await Supabase.instance.client.storage
          .from('profile-photos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('profile-photos')
          .getPublicUrl(fileName);

      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(
        userId: userId,
        profileImageUrl: publicUrl,
      );
      ref.invalidate(currentUserProvider);

      if (context.mounted) {
        AppSnackbar.success(context, 'Profile photo updated!');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  void _showLanguageDialog(BuildContext context) {
    String selected = 'English (US)';
    final languages = [
      'English (US)',
      'Patois (Cayman)',
      'Español',
      'Français',
    ];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Language & Region'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages
                .map(
                  (lang) => RadioListTile<String>(
                    title: Text(lang),
                    value: lang,
                    // ignore: deprecated_member_use
                    groupValue: selected,
                    activeColor: AppTheme.primaryColor,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setDialogState(() => selected = v!),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                AppSnackbar.success(context, 'Language set to $selected');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPhoneDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic currentUser,
  ) {
    final phoneCtrl = TextEditingController(text: currentUser?.phone ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Phone Number'),
        content: TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: 'Enter phone number',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final phone = phoneCtrl.text.trim();
              if (phone.isNotEmpty) {
                try {
                  final userService = ref.read(userServiceProvider);
                  await userService.updateUserProfile(
                    userId: currentUser!.id,
                    phone: phone,
                  );
                  ref.invalidate(currentUserProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    AppSnackbar.success(context, 'Phone number updated');
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    AppSnackbar.error(context, friendlyError(e));
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStats(String userId) {
    final ordersAsync = ref.watch(userOrdersProvider(userId));
    return ordersAsync.when(
      data: (orders) {
        final activeOrders = orders
            .where((o) => o.status != 'cancelled')
            .toList();
        final totalSpent = activeOrders.fold<double>(
          0,
          (sum, o) => sum + o.totalAmount,
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ProfileStat(label: 'Orders', value: '${activeOrders.length}'),
            Container(width: 1, height: 30, color: Colors.grey[300]),
            _ProfileStat(
              label: 'Spent',
              value:
                  '${AppConstants.currencySymbol}${totalSpent.toStringAsFixed(0)}',
            ),
            Container(width: 1, height: 30, color: Colors.grey[300]),
            _ProfileStat(label: 'Member', value: 'Active'),
          ],
        );
      },
      loading: () => const AppLoadingIndicator(
        fullScreen: false,
        message: 'Loading stats...',
      ),
      error: (_, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ProfileStat(label: 'Orders', value: '0'),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _ProfileStat(label: 'Spent', value: '\$0'),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _ProfileStat(label: 'Member', value: 'Active'),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Color(0xFF1F2937),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing: const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
