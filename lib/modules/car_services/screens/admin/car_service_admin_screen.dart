import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';

const _kOrange = Color(0xFFF97316);

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kBg = Color(0xFFF8FAFC);
const _kAmber = Color(0xFFF59E0B);

class CarServiceAdminScreen extends ConsumerStatefulWidget {
  const CarServiceAdminScreen({super.key});

  @override
  ConsumerState<CarServiceAdminScreen> createState() =>
      _CarServiceAdminScreenState();
}

class _CarServiceAdminScreenState
    extends ConsumerState<CarServiceAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approveProvider(CarServiceProvider provider) async {
    try {
      await ref.read(carServicesServiceProvider).approveProvider(provider.id);
      ref.invalidate(pendingProvidersProvider);
      ref.invalidate(carServiceProvidersProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${provider.businessName} approved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error approving provider', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rejectProvider(CarServiceProvider provider) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject ${provider.businessName}?'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(carServicesServiceProvider).rejectProvider(
            provider.id,
            reasonCtrl.text.trim(),
          );
      ref.invalidate(pendingProvidersProvider);
      ref.invalidate(carServiceProvidersProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${provider.businessName} rejected'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error rejecting provider', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _verifyProvider(CarServiceProvider provider) async {
    try {
      await ref.read(carServicesServiceProvider).updateProviderProfile(
          provider.id, {'is_verified': true});
      ref.invalidate(carServiceProvidersProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${provider.businessName} verified'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      AppLogger.error('Error verifying provider', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleProvider(CarServiceProvider provider, bool active) async {
    try {
      await ref.read(carServicesServiceProvider).updateProviderProfile(
          provider.id, {'is_active': active});
      ref.invalidate(carServiceProvidersProvider(null));
    } catch (e) {
      AppLogger.error('Error toggling provider', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(carServiceProvidersProvider(null));
    final categoriesAsync = ref.watch(carServiceCategoriesProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Car Services Admin'),
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Providers'),
            Tab(text: 'Bookings'),
            Tab(text: 'Categories'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Stats bar ──────────────────────────────────────────────────────
          providersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (providers) {
              final verified = providers.where((p) => p.isVerified).length;
              final active = providers.where((p) => p.isActive).length;
              return _StatsBar(
                providers: providers.length,
                verified: verified,
                active: active,
              );
            },
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── PENDING APPROVALS ──────────────────────────────────────
                _PendingApprovalsTab(
                  onApprove: _approveProvider,
                  onReject: _rejectProvider,
                ),

                // ── PROVIDERS ──────────────────────────────────────────────
                providersAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: _kBlue)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (providers) => RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(carServiceProvidersProvider(null)),
                    child: providers.isEmpty
                        ? const Center(child: Text('No providers yet'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: providers.length,
                            itemBuilder: (ctx, i) => _ProviderCard(
                              provider: providers[i],
                              onVerify: () => _verifyProvider(providers[i]),
                              onToggle: (v) =>
                                  _toggleProvider(providers[i], v),
                            ),
                          ),
                  ),
                ),

                // ── BOOKINGS ───────────────────────────────────────────────
                _AdminBookingsTab(),

                // ── CATEGORIES ─────────────────────────────────────────────
                categoriesAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: _kBlue)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (cats) => _CategoriesTab(categories: cats),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats bar ──────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int providers;
  final int verified;
  final int active;

  const _StatsBar({
    required this.providers,
    required this.verified,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatChip(label: 'Total', value: '$providers', color: _kBlue),
          const SizedBox(width: 8),
          _StatChip(
              label: 'Verified', value: '$verified', color: Colors.green),
          const SizedBox(width: 8),
          _StatChip(label: 'Active', value: '$active', color: _kAmber),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: color)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ── Provider card ──────────────────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final CarServiceProvider provider;
  final VoidCallback onVerify;
  final ValueChanged<bool> onToggle;

  const _ProviderCard({
    required this.provider,
    required this.onVerify,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFEFF6FF),
            backgroundImage: provider.profileImageUrl != null
                ? NetworkImage(provider.profileImageUrl!)
                : null,
            child: provider.profileImageUrl == null
                ? const Icon(Icons.person, color: _kBlue)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        provider.businessName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (provider.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded,
                          color: _kBlue, size: 15),
                    ],
                    const SizedBox(width: 4),
                    _StatusBadge(active: provider.isActive),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '⭐ ${provider.rating.toStringAsFixed(1)} · ${provider.totalReviews} reviews · ${provider.totalBookings} jobs',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: provider.isActive,
                activeThumbColor: _kBlue,
                onChanged: onToggle,
              ),
              if (!provider.isVerified)
                GestureDetector(
                  onTap: onVerify,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kAmber.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Verify',
                      style: TextStyle(
                        fontSize: 11,
                        color: _kAmber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: active ? const Color(0xFF166534) : Colors.grey,
        ),
      ),
    );
  }
}

// ── Admin bookings tab ─────────────────────────────────────────────────────────

class _AdminBookingsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(carServiceProvidersProvider(null));
    final currency = NumberFormat.currency(symbol: '\$');

    return providersAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _kBlue)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (providers) {
        if (providers.isEmpty) {
          return const Center(child: Text('No providers / bookings yet'));
        }

        final allBookings = providers
            .map((p) => ref.watch(providerBookingsProvider(p.id)))
            .expand((a) => a.valueOrNull ?? <CarServiceBooking>[])
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (allBookings.isEmpty) {
          return const Center(child: Text('No bookings yet'));
        }

        return RefreshIndicator(
          color: _kBlue,
          onRefresh: () async {
            for (final p in providers) {
              ref.invalidate(providerBookingsProvider(p.id));
            }
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allBookings.length,
            itemBuilder: (ctx, i) {
              final b = allBookings[i];
              final color = _statusColor(b.status);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(6),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.provider?.businessName ?? 'Provider',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            b.offering?.name ?? 'Service',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('MMM d · h:mm a')
                                .format(b.scheduledAt),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            b.status.toDisplayString(),
                            style: TextStyle(
                                fontSize: 10,
                                color: color,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currency.format(b.totalAmount),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _statusColor(CarServiceBookingStatus s) {
    switch (s) {
      case CarServiceBookingStatus.completed:
        return Colors.green;
      case CarServiceBookingStatus.cancelled:
        return Colors.red;
      case CarServiceBookingStatus.inProgress:
        return _kBlue;
      case CarServiceBookingStatus.pending:
        return _kAmber;
      default:
        return Colors.grey;
    }
  }
}

// ── Categories tab ─────────────────────────────────────────────────────────────

class _CategoriesTab extends StatelessWidget {
  final List<CarServiceCategory> categories;
  const _CategoriesTab({required this.categories});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (ctx, i) {
        final c = categories[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconForName(c.iconName),
                    color: _kBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    if (c.description != null && c.description!.isNotEmpty)
                      Text(c.description!,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(
                c.isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: c.isActive ? Colors.green : Colors.grey.shade300,
                size: 20,
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForName(String? name) {
    switch (name) {
      case 'local_car_wash':
        return Icons.local_car_wash;
      case 'airline_seat_recline_normal':
        return Icons.airline_seat_recline_normal;
      case 'star':
        return Icons.star;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'settings':
        return Icons.settings;
      default:
        return Icons.car_repair;
    }
  }
}

// ── Pending approvals tab ───────────────────────────────────────────────────────

class _PendingApprovalsTab extends ConsumerWidget {
  final Future<void> Function(CarServiceProvider) onApprove;
  final Future<void> Function(CarServiceProvider) onReject;

  const _PendingApprovalsTab({
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingProvidersProvider);

    return pendingAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _kBlue)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (providers) {
        if (providers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 56, color: Colors.green),
                const SizedBox(height: 12),
                const Text('No pending applications',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Text('All submissions have been reviewed.',
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: _kBlue,
          onRefresh: () async => ref.invalidate(pendingProvidersProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: providers.length,
            itemBuilder: (ctx, i) => _PendingCard(
              provider: providers[i],
              onApprove: () => onApprove(providers[i]),
              onReject: () => onReject(providers[i]),
            ),
          ),
        );
      },
    );
  }
}

class _PendingCard extends StatelessWidget {
  final CarServiceProvider provider;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingCard({
    required this.provider,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEFF6FF),
                backgroundImage: provider.profileImageUrl != null
                    ? NetworkImage(provider.profileImageUrl!)
                    : null,
                child: provider.profileImageUrl == null
                    ? const Icon(Icons.car_repair, color: _kBlue)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.businessName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (provider.ownerName != null)
                      Text(provider.ownerName!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Pending',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kOrange,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (provider.businessType != null) ...[
            const SizedBox(height: 8),
            Text('Type: ${provider.businessType}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (provider.businessPhone != null) ...[
            const SizedBox(height: 2),
            Text('Phone: ${provider.businessPhone}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (provider.bio != null && provider.bio!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(provider.bio!,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
