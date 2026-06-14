import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/admin_provider.dart';
import '../../../models/user_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

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
          const Text('Users', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Manage all platform users', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
                    label: Text(r == 'All' ? 'All' : _cap(r), style: TextStyle(fontSize: 12, color: isActive ? Colors.white : const Color(0xFF64748B))),
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

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: usersAsync.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allUsersProvider)),
                data: (users) => users.isEmpty
                    ? const Center(child: Text('No users found', style: TextStyle(color: Color(0xFF94A3B8))))
                    : _UsersTable(users: users, onBan: _confirmBan),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Future<void> _confirmBan(User user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ban ${user.name ?? user.email}?'),
        content: const Text('This will suspend the user\'s access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Ban User'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      AppSnackbar.show(context, message: 'User banned');
    }
  }
}

class _UsersTable extends StatelessWidget {
  final List<User> users;
  final ValueChanged<User> onBan;

  const _UsersTable({required this.users, required this.onBan});

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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          child: Text(initial, style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(user.name ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                      ],
                    )),
                    Expanded(flex: 2, child: Text(user.email ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
                    Expanded(child: _RoleBadge(role: user.role)),
                    Expanded(child: Text(user.phone ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                    IconButton(
                      icon: const Icon(Icons.block_rounded, size: 18, color: Color(0xFFEF4444)),
                      tooltip: 'Ban user',
                      onPressed: () => onBan(user),
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
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[role] ?? const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(role, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
