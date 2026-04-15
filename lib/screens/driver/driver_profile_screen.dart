import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  late TextEditingController _vehicleNumberController;
  late TextEditingController _licenseNumberController;
  String _selectedVehicleType = 'bike';
  bool _controllersInitialized = false;

  String _getSuccessRate(Driver? driver) {
    if (driver == null) return '—';
    final completed = driver.completedDeliveries ?? 0;
    final cancelled = driver.cancelledDeliveries ?? 0;
    final total = completed + cancelled;
    if (total == 0) return '—';
    return '${(completed / total * 100).round()}%';
  }

  @override
  void initState() {
    super.initState();
    _vehicleNumberController = TextEditingController();
    _licenseNumberController = TextEditingController();
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (authState.user == null || currentUserId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(
          message: 'Loading profile...',
          color: AppTheme.primaryColor,
        ),
      );
    }

    final driverProfileAsync = ref.watch(driverProfileProvider(currentUserId));

    return driverProfileAsync.when(
      data: (driver) {
        if (driver != null && !_controllersInitialized) {
          _vehicleNumberController.text = driver.vehicleNumber ?? '';
          _licenseNumberController.text = driver.licenseNumber ?? '';
          _selectedVehicleType = driver.vehicleType ?? 'bike';
          _controllersInitialized = true;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF0F1117),
                foregroundColor: Colors.white,
                elevation: 0,
                title: const Text(
                  'Driver Profile',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: Material(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          ref.read(authNotifierProvider.notifier).signOut();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 16,
                                color: Color(0xFFEF4444),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Logout',
                                style: TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Avatar & Name Card ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2030),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF2A2D3E)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: const Color(0xFF2A2D3E),
                                backgroundImage:
                                    authState.user!.profileImageUrl != null
                                    ? NetworkImage(
                                        authState.user!.profileImageUrl!,
                                      )
                                    : null,
                                child: authState.user!.profileImageUrl == null
                                    ? const Icon(
                                        Icons.person_rounded,
                                        size: 44,
                                        color: Color(0xFF6B7280),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              authState.user!.name ?? 'Driver',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              authState.user!.email,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            if (driver != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (driver.isAvailable
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFF6B7280))
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color:
                                          (driver.isAvailable
                                                  ? const Color(0xFF22C55E)
                                                  : const Color(0xFF6B7280))
                                              .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    driver.isAvailable
                                        ? 'Available'
                                        : 'Offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: driver.isAvailable
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Vehicle Information ──
                      const Text(
                        'Vehicle Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Vehicle Type Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2030),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF2A2D3E)),
                        ),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedVehicleType,
                          dropdownColor: const Color(0xFF1E2030),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Vehicle Type',
                            labelStyle: TextStyle(color: Color(0xFF6B7280)),
                            prefixIcon: Icon(
                              Icons.two_wheeler,
                              color: AppTheme.primaryColor,
                            ),
                            border: InputBorder.none,
                          ),
                          items: ['bike', 'car', 'scooter']
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedVehicleType = value!;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Vehicle Number
                      _DarkTextField(
                        controller: _vehicleNumberController,
                        label: 'Vehicle Number',
                        icon: Icons.directions_car_rounded,
                      ),
                      const SizedBox(height: 12),

                      // License Number
                      _DarkTextField(
                        controller: _licenseNumberController,
                        label: 'License Number',
                        icon: Icons.card_membership_rounded,
                      ),
                      const SizedBox(height: 24),

                      // ── Performance Stats ──
                      const Text(
                        'Performance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _StatTile(
                            label: 'Deliveries',
                            value: '${driver?.completedDeliveries ?? 0}',
                            icon: Icons.local_shipping_rounded,
                            color: const Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 10),
                          _StatTile(
                            label: 'Avg Rating',
                            value: driver?.rating != null && driver!.rating! > 0
                                ? driver.rating!.toStringAsFixed(1)
                                : 'N/A',
                            icon: Icons.star_rounded,
                            color: const Color(0xFFFBBF24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _StatTile(
                            label: 'Total Earnings',
                            value:
                                '${AppConstants.currencySymbol}${(driver?.totalEarnings ?? 0).toStringAsFixed(0)}',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 10),
                          _StatTile(
                            label: 'Success Rate',
                            value: _getSuccessRate(driver),
                            icon: Icons.percent_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              if (driver != null) {
                                final driverService = ref.read(
                                  driverServiceProvider,
                                );
                                await driverService.updateDriverProfile(
                                  driverId: driver.id,
                                  vehicleType: _selectedVehicleType,
                                  vehicleNumber: _vehicleNumberController.text
                                      .trim(),
                                  licenseNumber: _licenseNumberController.text
                                      .trim(),
                                );
                                ref.invalidate(
                                  driverProfileProvider(currentUserId),
                                );
                                if (context.mounted) {
                                  AppSnackbar.success(
                                    context,
                                    'Profile updated!',
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                AppSnackbar.error(context, friendlyError(e));
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(
          message: 'Loading driver profile...',
          color: AppTheme.primaryColor,
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: AppErrorState(message: friendlyError(err)),
      ),
    );
  }
}

// ─── Dark Text Field ──────────────────────────────────────────────────────────

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _DarkTextField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        filled: true,
        fillColor: const Color(0xFF1E2030),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppTheme.primaryColor,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Stat Tile ────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
