import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/admin_provider.dart';
import '../../../models/user_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../screens/admin/admin_wallet_adjust_sheet.dart';

class WebAdminUsersPage extends ConsumerStatefulWidget {
  const WebAdminUsersPage({super.key});

  @override
  ConsumerState<WebAdminUsersPage> createState() => _WebAdminUsersPageState();
}

class _WebAdminUsersPageState extends ConsumerState<WebAdminUsersPage> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _roleFilter;
  static const _roles = ['customer', 'restaurant', 'driver', 'admin'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(allUsersProvider);
    ref.invalidate(usersByRoleProvider);
    ref.invalidate(userSearchProvider);
  }

  void _showUserDetails(User user) {
    showDialog(
      context: context,
      builder: (_) => _UserDetailsDialog(
        user: user,
        onBanToggle: () => _toggleBan(user),
        onWalletAdjust: () => _showWallet(user),
      ),
    );
  }

  void _showWallet(User user) {
    AdminWalletAdjustSheet.show(
      context,
      userId: user.id,
      customerName: user.name ?? user.email ?? 'User',
      onDone: _refresh,
    );
  }

  Future<void> _toggleBan(User user) async {
    final isBanning = user.isActive;
    final ok = await showDialog<bool>(
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isBanning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(isBanning ? 'Ban' : 'Unban'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(adminServiceProvider).toggleUserStatus(user.id, !user.isActive);
      _refresh();
      if (mounted) {
        AppSnackbar.success(context, '${user.name ?? user.email} ${isBanning ? 'banned' : 'unbanned'}');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = _search.isNotEmpty
        ? ref.watch(userSearchProvider(_search))
        : _roleFilter != null
            ? ref.watch(usersByRoleProvider(_roleFilter!))
            : ref.watch(allUsersProvider((0, 100)));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Users', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Manage all platform users', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Search & Filters ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              ...['All', ..._roles].map((r) {
                final isActive = r == 'All' ? _roleFilter == null : _roleFilter == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_cap(r), style: TextStyle(fontSize: 12, color: isActive ? Colors.white : const Color(0xFF64748B))),
                    selected: isActive,
                    selectedColor: const Color(0xFF6366F1),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade200),
                    onSelected: (_) => setState(() => _roleFilter = r == 'All' ? null : r),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // ── Table ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: usersAsync.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: _refresh),
                data: (users) => users.isEmpty
                    ? const Center(child: Text('No users found', style: TextStyle(color: Color(0xFF94A3B8))))
                    : _UsersTable(
                        users: users,
                        onDetails: _showUserDetails,
                        onBan: _toggleBan,
                        onWalletAdjust: _showWallet,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cap(String s) {
    if (s == 'All') return 'All';
    if (s == 'customer') return 'Customers';
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1)}s';
  }
}

// ── Users Table ────────────────────────────────────────────────────────────────

class _UsersTable extends StatelessWidget {
  final List<User> users;
  final ValueChanged<User> onDetails;
  final ValueChanged<User> onBan;
  final ValueChanged<User> onWalletAdjust;

  const _UsersTable({
    required this.users,
    required this.onDetails,
    required this.onBan,
    required this.onWalletAdjust,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: _Th('Name')),
              Expanded(flex: 2, child: _Th('Email')),
              Expanded(child: _Th('Role')),
              Expanded(child: _Th('Phone')),
              SizedBox(width: 90, child: _Th('Status')),
              SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final user = users[i];
              final name = user.name;
              final email = user.email;
              final initial = (name != null && name.isNotEmpty)
                  ? name[0].toUpperCase()
                  : (email != null && email.isNotEmpty ? email[0].toUpperCase() : '?');
              final isActive = user.isActive;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          child: Text(initial, style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(user.name ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                    Expanded(flex: 2, child: Text(user.email ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
                    Expanded(child: _RoleBadge(role: user.role)),
                    Expanded(
                      child: Row(children: [
                        if (user.phone != null && user.phone!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              onTap: () => launchUrl(Uri(scheme: 'tel', path: user.phone!)),
                              borderRadius: BorderRadius.circular(4),
                              child: const Icon(Icons.call_rounded, size: 15, color: Color(0xFF10B981)),
                            ),
                          ),
                        Expanded(child: Text(user.phone ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                      ]),
                    ),
                    SizedBox(
                      width: 90,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isActive ? const Color(0xFF10B981) : Colors.red).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Banned',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? const Color(0xFF10B981) : Colors.red),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
                        onSelected: (action) {
                          if (action == 'details') {
                            onDetails(user);
                          } else if (action == 'wallet') {
                            onWalletAdjust(user);
                          } else {
                            onBan(user);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'details',
                            child: Row(children: [Icon(Icons.info_outline, size: 18), SizedBox(width: 8), Text('View Details')]),
                          ),
                          const PopupMenuItem(
                            value: 'wallet',
                            child: Row(children: [
                              Icon(Icons.account_balance_wallet_rounded, size: 18, color: Color(0xFF10B981)),
                              SizedBox(width: 8),
                              Text('Adjust Wallet', style: TextStyle(color: Color(0xFF10B981))),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Row(children: [
                              Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 18, color: isActive ? Colors.red : Colors.green),
                              const SizedBox(width: 8),
                              Text(isActive ? 'Ban User' : 'Unban User', style: TextStyle(color: isActive ? Colors.red : Colors.green)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── User Details Dialog ────────────────────────────────────────────────────────

class _UserDetailsDialog extends StatelessWidget {
  final User user;
  final VoidCallback onBanToggle;
  final VoidCallback onWalletAdjust;

  const _UserDetailsDialog({
    required this.user,
    required this.onBanToggle,
    required this.onWalletAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = user.isActive;
    final roleColor = _roleColor(user.role);
    final email = user.email ?? '';
    final initial = (user.name?.isNotEmpty ?? false)
        ? user.name![0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Center(child: Text(initial, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 22))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.name ?? 'No name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Row(children: [
                        _chip(_roleLabel(user.role), roleColor),
                        const SizedBox(width: 6),
                        _chip(isActive ? 'Active' : 'Banned', isActive ? Colors.green : Colors.red),
                      ]),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _row(Icons.email_outlined, 'Email', email),
              if (user.phone != null) _row(Icons.phone_outlined, 'Phone', user.phone!),
              if (user.address != null) _row(Icons.location_on_outlined, 'Address', user.address!),
              _row(Icons.calendar_today_outlined, 'Joined', _formatDate(user.createdAt)),
              const SizedBox(height: 20),
              if (user.phone != null && user.phone!.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity, height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: user.phone!)),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text('Call ${user.name ?? "User"}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); onWalletAdjust(); },
                    icon: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Color(0xFF10B981)),
                    label: const Text('Adjust Wallet', style: TextStyle(color: Color(0xFF10B981))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF10B981)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(context); onBanToggle(); },
                    icon: Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 18),
                    label: Text(isActive ? 'Ban User' : 'Unban User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin': return const Color(0xFF6366F1);
      case 'restaurant': return const Color(0xFFFF6B35);
      case 'driver': return const Color(0xFF10B981);
      default: return const Color(0xFF6B7280);
    }
  }

  String _roleLabel(String role) {
    if (role == 'user' || role == 'customer') return 'Customer';
    if (role.isEmpty) return 'User';
    return role[0].toUpperCase() + role.substring(1);
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.9))),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 10),
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)))),
      ]),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  static const _colors = {
    'admin': Color(0xFF8B5CF6),
    'restaurant': Color(0xFF0EA5E9),
    'driver': Color(0xFF10B981),
    'customer': Color(0xFF6366F1),
    'user': Color(0xFF6366F1),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[role] ?? const Color(0xFF94A3B8);
    final label = (role == 'user' || role == 'customer') ? 'Customer' : role.isEmpty ? 'User' : role[0].toUpperCase() + role.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
