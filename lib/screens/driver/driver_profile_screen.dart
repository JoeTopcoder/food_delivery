import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';

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
  bool _saving = false;

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
      if (!authState.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/signin', (_) => false);
          }
        });
      }
      return Scaffold(
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
          backgroundColor: const Color(0xFF0B0D14),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Hero App Bar ─────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: const Color(0xFF0B0D14),
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.translate_rounded, size: 20),
                    tooltip: 'App Settings',
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/settings'),
                  ),
                  GestureDetector(
                    onTap: () =>
                        ref.read(authNotifierProvider.notifier).signOut(),
                    child: Container(
                      margin: const EdgeInsets.only(
                        right: 14,
                        top: 8,
                        bottom: 8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 15,
                            color: Color(0xFFEF4444),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Sign Out',
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
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _HeroHeader(
                    name: authState.user!.name ?? 'Driver',
                    email: authState.user!.email ?? '',
                    imageUrl: authState.user!.profileImageUrl,
                    isAvailable: driver?.isAvailable ?? false,
                  ),
                ),
                title: Text(
                  context.l10n.driverProfile,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Quick Stats Row ──────────────────────────────
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _QuickStat(
                            value: '${driver?.completedDeliveries ?? 0}',
                            label: 'Deliveries',
                            icon: Icons.local_shipping_rounded,
                            color: const Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value: driver?.rating != null && driver!.rating! > 0
                                ? driver.rating!.toStringAsFixed(1)
                                : '—',
                            label: 'Rating',
                            icon: Icons.star_rounded,
                            color: const Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value: _getSuccessRate(driver),
                            label: 'Success',
                            icon: Icons.verified_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          _QuickStat(
                            value:
                                '${AppConstants.currencySymbol}${(driver?.totalEarnings ?? 0).toStringAsFixed(0)}',
                            label: 'Earned',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF6366F1),
                          ),
                        ],
                      ),

                      // ── Vehicle Information Card ──────────────────────
                      const SizedBox(height: 24),
                      _SectionCard(
                        title: 'Vehicle Information',
                        icon: Icons.directions_car_rounded,
                        child: Column(
                          children: [
                            // Vehicle Type
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF13151F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF2A2D3E),
                                ),
                              ),
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedVehicleType,
                                dropdownColor: const Color(0xFF1A1D2B),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Vehicle Type',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  prefixIcon: Icon(
                                    _selectedVehicleType == 'car'
                                        ? Icons.directions_car_rounded
                                        : Icons.two_wheeler_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                  border: InputBorder.none,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'bike',
                                    child: Text('Motorcycle / Bike'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'scooter',
                                    child: Text('Scooter'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'car',
                                    child: Text('Car'),
                                  ),
                                ],
                                onChanged: (value) => setState(
                                  () => _selectedVehicleType = value!,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Plate Number
                            _StyledField(
                              controller: _vehicleNumberController,
                              label: 'Plate Number',
                              hint: 'e.g. AB 1234',
                              icon: Icons.pin_rounded,
                            ),
                            const SizedBox(height: 12),
                            // Licence Number
                            _StyledField(
                              controller: _licenseNumberController,
                              label: "Driver's Licence Number",
                              hint: 'e.g. L12345678',
                              icon: Icons.badge_rounded,
                            ),
                          ],
                        ),
                      ),

                      // ── Save Button ──────────────────────────────────
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  if (driver == null) return;
                                  setState(() => _saving = true);
                                  try {
                                    final driverService = ref.read(
                                      driverServiceProvider,
                                    );
                                    await driverService.updateDriverProfile(
                                      driverId: driver.id,
                                      vehicleType: _selectedVehicleType,
                                      vehicleNumber: _vehicleNumberController
                                          .text
                                          .trim(),
                                      licenseNumber: _licenseNumberController
                                          .text
                                          .trim(),
                                    );
                                    ref.invalidate(
                                      driverProfileProvider(currentUserId),
                                    );
                                    if (context.mounted)
                                      AppSnackbar.success(
                                        context,
                                        'Profile updated!',
                                      );
                                  } catch (e) {
                                    if (context.mounted)
                                      AppSnackbar.error(
                                        context,
                                        friendlyError(e),
                                      );
                                  } finally {
                                    if (mounted)
                                      setState(() => _saving = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppTheme.primaryColor
                                .withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
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
      loading: () => Scaffold(
        backgroundColor: Color(0xFF0B0D14),
        body: AppLoadingIndicator(
          message: 'Loading driver profile...',
          color: AppTheme.primaryColor,
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF0B0D14),
        body: AppErrorState(message: friendlyError(err)),
      ),
    );
  }
}

// ─── Hero Header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? imageUrl;
  final bool isAvailable;

  const _HeroHeader({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1D2E), Color(0xFF0B0D14)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circle
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withValues(alpha: 0.05),
              ),
            ),
          ),
          // Content
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFF6366F1)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFF1E2030),
                      backgroundImage: imageUrl != null
                          ? NetworkImage(imageUrl!)
                          : null,
                      child: imageUrl == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 38,
                              color: Color(0xFF6B7280),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isAvailable
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFF6B7280))
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  (isAvailable
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF6B7280))
                                      .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isAvailable
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isAvailable ? 'Available' : 'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isAvailable
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Stat ───────────────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _QuickStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D2B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252836)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF252836)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 17),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF252836), height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

// ─── Styled Field ─────────────────────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        filled: true,
        fillColor: const Color(0xFF13151F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2D3E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppTheme.primaryColor,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}
