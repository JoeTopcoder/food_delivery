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
import '../../utils/context_extensions.dart';

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
      backgroundColor: context.isDark ? null : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.myProfile,
          style: TextStyle(
            color: context.colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
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
                color: context.theme.cardColor,
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
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.createdAt != null
                        ? context.l10n.memberSince(
                            DateFormat.yMMM().format(currentUser!.createdAt),
                          )
                        : '',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (currentUserId != null) _buildOrderStats(currentUserId),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // My Activity
            _SectionTitle(context.l10n.myActivity),
            _SettingsTile(
              icon: Icons.account_balance_wallet_outlined,
              title: context.l10n.digitalWallet,
              subtitle: context.l10n.digitalWalletSub,
              onTap: () => Navigator.of(context).pushNamed('/wallet'),
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: context.l10n.orderHistory,
              subtitle: context.l10n.orderHistorySub,
              onTap: () => Navigator.of(context).pushNamed('/order-history'),
            ),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              title: context.l10n.addressBook,
              subtitle: context.l10n.addressBookSub,
              onTap: () => Navigator.of(context).pushNamed('/address-book'),
            ),
            _SettingsTile(
              icon: Icons.card_giftcard_outlined,
              title: context.l10n.loyaltyPoints,
              subtitle: context.l10n.loyaltyPointsSub,
              onTap: () => Navigator.of(context).pushNamed('/loyalty'),
            ),
            _SettingsTile(
              icon: Icons.favorite_outlined,
              title: context.l10n.favorites,
              subtitle: context.l10n.favoritesSub,
              onTap: () => Navigator.of(context).pushNamed('/favorites'),
            ),
            _SettingsTile(
              icon: Icons.people_outlined,
              title: context.l10n.referFriend,
              subtitle: context.l10n.referFriendSub,
              onTap: () => Navigator.of(context).pushNamed('/referrals'),
            ),
            _SettingsTile(
              icon: Icons.search_rounded,
              title: context.l10n.searchDiscover,
              subtitle: context.l10n.searchDiscoverSub,
              onTap: () => Navigator.of(context).pushNamed('/search'),
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: context.l10n.refundsDisputes,
              subtitle: context.l10n.refundsDisputesSub,
              onTap: () => Navigator.of(context).pushNamed('/refund-dispute'),
            ),
            _SettingsTile(
              icon: Icons.group_outlined,
              title: context.l10n.groupOrders,
              subtitle: context.l10n.groupOrdersSub,
              onTap: () => Navigator.of(context).pushNamed('/group-orders'),
            ),
            _SettingsTile(
              icon: Icons.card_membership_outlined,
              title: context.l10n.subscriptions,
              subtitle: context.l10n.subscriptionsSub,
              onTap: () => Navigator.of(context).pushNamed('/subscriptions'),
            ),
            _SettingsTile(
              icon: Icons.feedback_outlined,
              title: context.l10n.rateFeedback,
              subtitle: context.l10n.rateFeedbackSub,
              onTap: () => Navigator.of(context).pushNamed('/feedback'),
            ),
            const SizedBox(height: 24),

            // Account Settings
            _SectionTitle(context.l10n.accountSettings),
            _SettingsTile(
              icon: Icons.phone_outlined,
              title: context.l10n.phoneNumber,
              subtitle: currentUser?.phone ?? context.l10n.notSet,
              onTap: () => _showEditPhoneDialog(context, ref, currentUser),
            ),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              title: context.l10n.address,
              subtitle: currentUser?.address ?? context.l10n.notSet,
              onTap: () => Navigator.of(context).pushNamed('/address-book'),
            ),
            _SettingsTile(
              icon: Icons.payment_outlined,
              title: context.l10n.paymentMethods,
              subtitle: context.l10n.paymentMethodsSub,
              onTap: () {
                AppSnackbar.info(
                  context,
                  'Payment methods are configured at checkout',
                );
              },
            ),
            const SizedBox(height: 24),

            // Preferences
            _SectionTitle(context.l10n.preferences),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: context.l10n.notifications,
              subtitle: context.l10n.notificationsSub,
              onTap: () => Navigator.of(context).pushNamed('/notifications'),
            ),
            _SettingsTile(
              icon: Icons.language_outlined,
              title: context.l10n.languageRegion,
              subtitle: 'Language, theme & display',
              onTap: () => Navigator.of(context).pushNamed('/settings'),
            ),
            const SizedBox(height: 24),

            // Sign out button
            ElevatedButton(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text(
                'Sign Out',
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
            child: Text(context.l10n.cancel),
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
            child: Text(
              context.l10n.save,
              style: const TextStyle(color: Colors.white),
            ),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
        color: Theme.of(context).cardColor,
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
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
