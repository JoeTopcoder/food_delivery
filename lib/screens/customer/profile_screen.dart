// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kNavy  = Color(0xFF004E89);
const _kBlue  = Color(0xFF0077C8);
const _kGreen = Color(0xFF10B981);

// ─── Screen ───────────────────────────────────────────────────────────────────
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState
    extends ConsumerState<CustomerProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUser    = ref.watch(currentUserProvider);
    final currentUserId  = ref.watch(currentUserIdProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Gradient hero header ─────────────────────────────
              _HeroHeader(
                currentUser:  currentUser,
                onEditPhoto:  () => _pickAndUploadPhoto(context, ref, currentUser),
                onBack:       () => Navigator.pop(context),
              ),

              // ── Stats card ───────────────────────────────────────
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StatsCard(userId: currentUserId),
                ),
              ),

              // ── Content sections ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  children: [
                    _MenuGroup(label: 'ACTIVITY', items: [
                      _MenuItem(
                        icon:  Icons.account_balance_wallet_rounded,
                        color: _kGreen,
                        title: context.l10n.digitalWallet,
                        sub:   context.l10n.digitalWalletSub,
                        onTap: () => Navigator.of(context).pushNamed('/wallet'),
                      ),
                      _MenuItem(
                        icon:  Icons.receipt_long_rounded,
                        color: _kNavy,
                        title: context.l10n.orderHistory,
                        sub:   context.l10n.orderHistorySub,
                        onTap: () => Navigator.of(context).pushNamed('/order-history'),
                      ),
                      _MenuItem(
                        icon:  Icons.favorite_rounded,
                        color: const Color(0xFFEF4444),
                        title: context.l10n.favorites,
                        sub:   context.l10n.favoritesSub,
                        onTap: () => Navigator.of(context).pushNamed('/favorites'),
                      ),
                      _MenuItem(
                        icon:  Icons.stars_rounded,
                        color: const Color(0xFFF59E0B),
                        title: context.l10n.loyaltyPoints,
                        sub:   context.l10n.loyaltyPointsSub,
                        onTap: () => Navigator.of(context).pushNamed('/loyalty'),
                      ),
                      _MenuItem(
                        icon:  Icons.people_rounded,
                        color: const Color(0xFF0EA5E9),
                        title: context.l10n.referFriend,
                        sub:   context.l10n.referFriendSub,
                        onTap: () => Navigator.of(context).pushNamed('/referrals'),
                      ),
                      _MenuItem(
                        icon:  Icons.group_rounded,
                        color: const Color(0xFF6366F1),
                        title: context.l10n.groupOrders,
                        sub:   context.l10n.groupOrdersSub,
                        onTap: () => Navigator.of(context).pushNamed('/group-orders'),
                      ),
                      _MenuItem(
                        icon:  Icons.card_membership_rounded,
                        color: const Color(0xFF8B5CF6),
                        title: context.l10n.subscriptions,
                        sub:   context.l10n.subscriptionsSub,
                        onTap: () => Navigator.of(context).pushNamed('/subscriptions'),
                      ),
                    ]),

                    const SizedBox(height: 16),

                    _MenuGroup(label: 'ACCOUNT', items: [
                      _MenuItem(
                        icon:  Icons.phone_rounded,
                        color: _kGreen,
                        title: context.l10n.phoneNumber,
                        sub: currentUser?.phone?.isNotEmpty == true
                            ? currentUser!.phone!
                            : context.l10n.notSet,
                        onTap: () => _showEditPhoneDialog(context, ref, currentUser),
                      ),
                      _MenuItem(
                        icon:  Icons.location_on_rounded,
                        color: const Color(0xFF7C3AED),
                        title: context.l10n.addressBook,
                        sub:   context.l10n.addressBookSub,
                        onTap: () => Navigator.of(context).pushNamed('/address-book'),
                      ),

                    ]),

                    const SizedBox(height: 16),

                    _MenuGroup(label: 'PREFERENCES', items: [
                      _MenuItem(
                        icon:  Icons.notifications_rounded,
                        color: const Color(0xFFF59E0B),
                        title: context.l10n.notifications,
                        sub:   context.l10n.notificationsSub,
                        onTap: () => Navigator.of(context).pushNamed('/notifications'),
                      ),
                      _MenuItem(
                        icon:  Icons.language_rounded,
                        color: const Color(0xFF64748B),
                        title: context.l10n.languageRegion,
                        sub:   'Language, theme & display',
                        onTap: () => Navigator.of(context).pushNamed('/settings'),
                      ),
                    ]),

                    const SizedBox(height: 16),

                    _MenuGroup(label: 'SUPPORT', items: [
                      _MenuItem(
                        icon:  Icons.search_rounded,
                        color: const Color(0xFF64748B),
                        title: context.l10n.searchDiscover,
                        sub:   context.l10n.searchDiscoverSub,
                        onTap: () => Navigator.of(context).pushNamed('/search'),
                      ),
                      _MenuItem(
                        icon:  Icons.sync_alt_rounded,
                        color: const Color(0xFFEC4899),
                        title: context.l10n.refundsDisputes,
                        sub:   context.l10n.refundsDisputesSub,
                        onTap: () => Navigator.of(context).pushNamed('/refund-dispute'),
                      ),
                      _MenuItem(
                        icon:  Icons.star_rate_rounded,
                        color: const Color(0xFFF97316),
                        title: context.l10n.rateFeedback,
                        sub:   context.l10n.rateFeedbackSub,
                        onTap: () => Navigator.of(context).pushNamed('/feedback'),
                      ),
                    ]),

                    const SizedBox(height: 16),

                    // Sign out row (same card style, red accent)
                    _SignOutRow(
                      onPressed: () async {
                        await ref
                            .read(authNotifierProvider.notifier)
                            .signOut();
                      },
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo upload ─────────────────────────────────────────────────────────────
  Future<void> _pickAndUploadPhoto(
    BuildContext context,
    WidgetRef ref,
    dynamic currentUser,
  ) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _kNavy.withAlpha(12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: _kNavy),
                ),
                title: const Text('Take Photo',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _kNavy.withAlpha(12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: _kNavy),
                ),
                title: const Text('Choose from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
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
      final bytes  = await picked.readAsBytes();
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
      final updatedUser = await userService.updateUserProfile(
        userId: userId,
        profileImageUrl: publicUrl,
      );
      if (updatedUser != null) {
        ref.read(userSessionOverrideProvider.notifier).state = updatedUser;
      }

      if (context.mounted) AppSnackbar.success(context, 'Profile photo updated!');
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  // ── Edit phone dialog ────────────────────────────────────────────────────────
  void _showEditPhoneDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic currentUser,
  ) {
    final ctrl = TextEditingController(text: currentUser?.phone ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Phone Number',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: '+1 (876) 000-0000',
            prefixIcon: const Icon(Icons.phone_rounded, color: _kNavy),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kNavy, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          FilledButton(
            onPressed: () async {
              final phone = ctrl.text.trim();
              if (phone.isEmpty) return;
              try {
                final updated = await ref.read(userServiceProvider).updateUserProfile(
                  userId: currentUser!.id,
                  phone: phone,
                );
                if (updated != null) {
                  ref.read(userSessionOverrideProvider.notifier).state = updated;
                }
                if (ctx.mounted)     Navigator.pop(ctx);
                if (context.mounted) AppSnackbar.success(context, 'Phone updated');
              } catch (e) {
                if (ctx.mounted)     Navigator.pop(ctx);
                if (context.mounted) AppSnackbar.error(context, friendlyError(e));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: _kNavy),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final dynamic currentUser;
  final VoidCallback onEditPhoto;
  final VoidCallback onBack;

  const _HeroHeader({
    required this.currentUser,
    required this.onEditPhoto,
    required this.onBack,
  });

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name  = currentUser?.name as String?;
    final email = currentUser?.email as String?;
    final photo = currentUser?.profileImageUrl as String?;
    final since = currentUser?.createdAt != null
        ? DateFormat.yMMM().format(currentUser!.createdAt as DateTime)
        : null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kNavy, _kBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Nav row
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onBack,
                  ),
                  const Expanded(
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Avatar
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(180), width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 16,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: Colors.white.withAlpha(30),
                  backgroundImage:
                      photo != null ? NetworkImage(photo) : null,
                  child: photo == null
                      ? Text(
                          _initials(name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onEditPhoto,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: _kNavy,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Name
          Text(
            name ?? 'Guest User',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 4),

          // Email
          if (email != null && email.isNotEmpty)
            Text(
              email,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
            ),

          const SizedBox(height: 6),

          // Member since badge
          if (since != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withAlpha(50)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: Colors.white70,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Member since $since',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ─── Stats card ───────────────────────────────────────────────────────────────
class _StatsCard extends ConsumerWidget {
  final String? userId;
  const _StatsCard({this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync =
        userId != null ? ref.watch(userOrdersProvider(userId!)) : null;

    return _StatsShell(
      child: ordersAsync == null
          ? _StatsRow(orders: 0, spent: 0)
          : ordersAsync.when(
              data: (orders) {
                final active =
                    orders.where((o) => o.status != 'cancelled').toList();
                final spent = active.fold<double>(
                  0,
                  (s, o) => s + o.totalAmount,
                );
                return _StatsRow(orders: active.length, spent: spent);
              },
              loading: () => const SizedBox(
                height: 56,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kNavy,
                  ),
                ),
              ),
              error: (_, __) => _StatsRow(orders: 0, spent: 0),
            ),
    );
  }
}

class _StatsShell extends StatelessWidget {
  final Widget child;
  const _StatsShell({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kNavy.withAlpha(35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: child,
      );
}

class _StatsRow extends StatelessWidget {
  final int orders;
  final double spent;
  const _StatsRow({required this.orders, required this.spent});

  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(child: _Stat(value: '$orders', label: 'Orders')),
          VerticalDivider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
            indent: 6,
            endIndent: 6,
          ),
          Expanded(
            child: _Stat(
              value: '$sym${spent.toStringAsFixed(0)}',
              label: 'Total Spent',
            ),
          ),
          VerticalDivider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
            indent: 6,
            endIndent: 6,
          ),
          Expanded(
            child: _Stat(value: 'Active', label: 'Status', isGreen: true),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool isGreen;

  const _Stat({
    required this.value,
    required this.label,
    this.isGreen = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isGreen ? _kGreen : Theme.of(context).colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      );
}

// ─── Menu group ───────────────────────────────────────────────────────────────
class _MenuGroup extends StatelessWidget {
  final String label;
  final List<_MenuItem> items;

  const _MenuGroup({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(7),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top:    i == 0 ? const Radius.circular(16) : Radius.zero,
                    bottom: i == items.length - 1
                        ? const Radius.circular(16)
                        : Radius.zero,
                  ),
                  child: items[i],
                ),
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 60,
                    endIndent: 16,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Menu item ────────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(22),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sign-out row ─────────────────────────────────────────────────────────────
class _SignOutRow extends StatelessWidget {
  final VoidCallback onPressed;
  const _SignOutRow({required this.onPressed});

  static const _red = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(7),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _red.withAlpha(18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: _red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Sign Out',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: _red,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
