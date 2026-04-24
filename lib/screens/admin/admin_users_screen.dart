import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart' as user_models;
import '../../providers/admin_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  String _selectedRole = 'all';
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allUsersProvider);
    ref.invalidate(usersByRoleProvider);
    ref.invalidate(userSearchProvider);
  }

  void _showUserDetails(user_models.User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _UserDetailsSheet(user: user, onBanToggle: () => _toggleBan(user)),
    );
  }

  Future<void> _toggleBan(user_models.User user) async {
    final isBanning = user.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isBanning ? 'Ban User?' : 'Unban User?'),
        content: Text(
          isBanning
              ? 'Ban "${user.name ?? user.email}"? They will lose access to the app.'
              : 'Restore access for "${user.name ?? user.email}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isBanning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(isBanning ? 'Ban' : 'Unban'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(adminServiceProvider)
          .toggleUserStatus(user.id, !user.isActive);
      ref.invalidate(allUsersProvider);
      ref.invalidate(usersByRoleProvider);
      ref.invalidate(userSearchProvider);
      if (mounted) {
        AppSnackbar.success(
          context,
          '${user.name ?? user.email} ${isBanning ? 'banned' : 'unbanned'}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = _searchQuery.isNotEmpty
        ? ref.watch(userSearchProvider(_searchQuery))
        : _selectedRole == 'all'
        ? ref.watch(allUsersProvider((0, 100)))
        : ref.watch(usersByRoleProvider(_selectedRole));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Search & Filter ───────────────────────────────────────────────
          Container(
            color: AppTheme.primaryColor,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name or email…',
                      hintStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: Color(0xFF9CA3AF),
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['all', 'user', 'restaurant', 'driver'].map((
                        role,
                      ) {
                        final selected = _selectedRole == role;
                        final label = role == 'all'
                            ? 'All'
                            : role == 'user'
                            ? 'Customers'
                            : '${role[0].toUpperCase()}${role.substring(1)}s';
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF374151),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedRole = role),
                            selectedColor: AppTheme.primaryColor,
                            backgroundColor: Theme.of(context).cardColor,
                            checkmarkColor: Colors.white,
                            side: BorderSide(
                              color: selected
                                  ? AppTheme.primaryColor
                                  : Colors.grey[300]!,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── User List ─────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primaryColor,
              child: usersAsync.when(
                data: (users) {
                  if (users.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 80),
                        AppEmptyState(
                          icon: Icons.people_outline,
                          title: 'No users found',
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return _UserCard(
                        user: user,
                        onDetails: () => _showUserDetails(user),
                        onBanToggle: () => _toggleBan(user),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: AppLoadingIndicator(message: 'Loading users...'),
                ),
                error: (e, _) => ListView(
                  children: [
                    const SizedBox(height: 80),
                    AppErrorState(message: friendlyError(e), onRetry: _refresh),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── User Card ──────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final user_models.User user;
  final VoidCallback onDetails;
  final VoidCallback onBanToggle;

  const _UserCard({
    required this.user,
    required this.onDetails,
    required this.onBanToggle,
  });

  Color get _roleColor {
    switch (user.role) {
      case 'admin':
        return const Color(0xFF6366F1);
      case 'restaurant':
        return AppTheme.primaryColor;
      case 'driver':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get _roleLabel {
    switch (user.role) {
      case 'customer':
      case 'user':
        return 'Customer';
      default:
        return user.role[0].toUpperCase() + user.role.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = user.isActive;
    final email = user.email ?? '';
    final initial = (user.name?.isNotEmpty ?? false)
        ? user.name![0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

    return GestureDetector(
      onTap: onDetails,
      child: Container(
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
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: _roleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.name ?? 'No name',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          isActive ? 'Active' : 'Banned',
                          isActive ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _badge(_roleLabel, _roleColor, small: true),
                        if (user.phone != null) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.phone,
                            size: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            user.phone!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Call button
              if (user.phone != null && user.phone!.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.call_rounded,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                  tooltip: 'Call ${user.name ?? 'user'}',
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: user.phone!)),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),

              // Menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: Color(0xFF9CA3AF),
                  size: 20,
                ),
                onSelected: (action) {
                  if (action == 'details') {
                    onDetails();
                  } else {
                    onBanToggle();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18),
                        SizedBox(width: 8),
                        Text('View Details'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          isActive ? Icons.block : Icons.check_circle_outline,
                          size: 18,
                          color: isActive ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isActive ? 'Ban User' : 'Unban User',
                          style: TextStyle(
                            color: isActive ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

// ─── User Details Sheet ──────────────────────────────────────────────────────

class _UserDetailsSheet extends ConsumerWidget {
  final user_models.User user;
  final VoidCallback onBanToggle;

  const _UserDetailsSheet({required this.user, required this.onBanToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user.isActive;
    final roleColor = _roleColor(user.role);
    final email = user.email ?? '';
    final initial = (user.name?.isNotEmpty ?? false)
        ? user.name![0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name ?? 'No name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _chip(
                          user.role == 'user' || user.role == 'customer'
                              ? 'Customer'
                              : user.role[0].toUpperCase() +
                                    user.role.substring(1),
                          roleColor,
                        ),
                        const SizedBox(width: 6),
                        _chip(
                          isActive ? 'Active' : 'Banned',
                          isActive ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Details
          _row(context, Icons.email_outlined, 'Email', email),
          if (user.phone != null)
            _row(context, Icons.phone_outlined, 'Phone', user.phone!),
          if (user.address != null)
            _row(context, Icons.location_on_outlined, 'Address', user.address!),
          _row(
            context,
            Icons.calendar_today_outlined,
            'Joined',
            _formatDate(user.createdAt),
          ),

          const SizedBox(height: 20),

          // Call button
          if (user.phone != null && user.phone!.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () =>
                    launchUrl(Uri(scheme: 'tel', path: user.phone!)),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text('Call ${user.name ?? 'User'}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Action button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onBanToggle();
              },
              icon: Icon(
                isActive ? Icons.block : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(isActive ? 'Ban This User' : 'Unban This User'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFF6366F1);
      case 'restaurant':
        return AppTheme.primaryColor;
      case 'driver':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }
}
