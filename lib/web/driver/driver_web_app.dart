import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'pages/web_driver_dashboard_page.dart';
import 'pages/web_driver_orders_page.dart';
import 'pages/web_driver_deliveries_page.dart';
import 'pages/web_driver_earnings_page.dart';
import 'pages/web_driver_profile_page.dart';

enum _DriverPage { dashboard, available, active, earnings, profile }

class DriverWebApp extends ConsumerStatefulWidget {
  const DriverWebApp({super.key});

  @override
  ConsumerState<DriverWebApp> createState() => _DriverWebAppState();
}

class _DriverWebAppState extends ConsumerState<DriverWebApp> {
  _DriverPage _currentPage = _DriverPage.dashboard;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final userId   = authState.user?.id ?? '';

    final driverAsync = ref.watch(driverProfileProvider(userId));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: driverAsync.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => Center(child: AppErrorState(message: friendlyError(e))),
        data: (driver) {
          if (driver == null) {
            return const Center(child: Text('Driver profile not found. Please contact support.', style: TextStyle(color: Color(0xFF64748B))));
          }
          return Row(
            children: [
              _Sidebar(
                currentPage: _currentPage,
                userName: authState.user?.name ?? 'Driver',
                isAvailable: driver.isAvailable,
                onNavigate: (p) => setState(() => _currentPage = p),
                onSignOut: _signOut,
              ),
              Expanded(
                child: _buildBody(userId, driver.id),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(String userId, String driverId) {
    return switch (_currentPage) {
      _DriverPage.dashboard => WebDriverDashboardPage(userId: userId, driverId: driverId),
      _DriverPage.available => WebDriverOrdersPage(driverId: driverId),
      _DriverPage.active    => WebDriverDeliveriesPage(driverId: driverId),
      _DriverPage.earnings  => WebDriverEarningsPage(userId: userId, driverId: driverId),
      _DriverPage.profile   => WebDriverProfilePage(userId: userId, driverId: driverId),
    };
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final _DriverPage currentPage;
  final String userName;
  final bool isAvailable;
  final void Function(_DriverPage) onNavigate;
  final VoidCallback onSignOut;

  const _Sidebar({
    required this.currentPage,
    required this.userName,
    required this.isAvailable,
    required this.onNavigate,
    required this.onSignOut,
  });

  static const _items = [
    (icon: Icons.dashboard_rounded,              label: 'Dashboard',        page: _DriverPage.dashboard),
    (icon: Icons.local_shipping_rounded,         label: 'Available Orders', page: _DriverPage.available),
    (icon: Icons.electric_scooter_rounded,       label: 'Active Deliveries',page: _DriverPage.active),
    (icon: Icons.account_balance_wallet_rounded, label: 'Earnings',         page: _DriverPage.earnings),
    (icon: Icons.person_rounded,                 label: 'My Profile',       page: _DriverPage.profile),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A2F4A), Color(0xFF0D1B2A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('7DASH Driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              Text('Hi, ${userName.split(' ').first} 👋', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
          ]),
        ),
        // Online/Offline badge
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: (isAvailable ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (isAvailable ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: isAvailable ? const Color(0xFF10B981) : const Color(0xFF64748B), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(isAvailable ? 'Online — Accepting Orders' : 'Offline', style: TextStyle(color: isAvailable ? const Color(0xFF10B981) : const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: _items.map((item) {
              final selected = currentPage == item.page;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: selected ? const Color(0xFF6366F1).withValues(alpha: 0.15) : null,
                leading: Icon(item.icon, size: 20, color: selected ? const Color(0xFF6366F1) : Colors.white54),
                title: Text(item.label, style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                )),
                onTap: () => onNavigate(item.page),
              );
            }).toList(),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 22),
          leading: const Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
          title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
          onTap: onSignOut,
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}
