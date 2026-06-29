// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/app_theme.dart';

enum AppPermissionType { location, camera, microphone, notifications }

class PermissionExplanationScreen extends StatefulWidget {
  final AppPermissionType permissionType;

  /// Called after the user taps "Continue" and the permission result is known.
  /// Passes the final [PermissionStatus].
  final void Function(PermissionStatus status)? onResult;

  const PermissionExplanationScreen({
    super.key,
    required this.permissionType,
    this.onResult,
  });

  @override
  State<PermissionExplanationScreen> createState() =>
      _PermissionExplanationScreenState();
}

class _PermissionExplanationScreenState
    extends State<PermissionExplanationScreen> {
  bool _requesting = false;

  _PermissionConfig get _config {
    switch (widget.permissionType) {
      case AppPermissionType.location:
        return const _PermissionConfig(
          icon: Icons.location_on_rounded,
          iconColor: Color(0xFF0077C8),
          title: 'Location Access',
          subtitle: 'Required for delivery and ride features',
          reasons: [
            'Customers: set your delivery address and track your order in real time.',
            'Drivers: required for matching you with nearby orders and rides, turn-by-turn navigation, and live delivery tracking.',
            'Background location is only used when you are actively assigned to a delivery or ride.',
          ],
          permission: Permission.locationWhenInUse,
        );
      case AppPermissionType.camera:
        return const _PermissionConfig(
          icon: Icons.camera_alt_rounded,
          iconColor: Color(0xFF10B981),
          title: 'Camera Access',
          subtitle: 'Used for photos and document uploads',
          reasons: [
            'Upload or update your profile photo.',
            'Drivers: upload licence, insurance, and vehicle documents during verification.',
            'Report order issues with photos (e.g., missing or wrong items).',
            'Restaurants and service providers: upload menu items and service images.',
          ],
          permission: Permission.camera,
        );
      case AppPermissionType.microphone:
        return const _PermissionConfig(
          icon: Icons.mic_rounded,
          iconColor: Color(0xFFF97316),
          title: 'Microphone Access',
          subtitle: 'Used for in-app voice calls',
          reasons: [
            'Voice calls between customers and drivers are powered by Agora.',
            'Microphone access is only active when you are in an active call.',
            'Calls are not recorded by 7Dash.',
          ],
          permission: Permission.microphone,
        );
      case AppPermissionType.notifications:
        return const _PermissionConfig(
          icon: Icons.notifications_active_rounded,
          iconColor: Color(0xFF8B5CF6),
          title: 'Notification Access',
          subtitle: 'Stay updated on orders and deliveries',
          reasons: [
            'Order status updates: when your order is confirmed, being prepared, or out for delivery.',
            'Driver arrival alerts so you can be ready.',
            'Ride status changes and driver location updates.',
            'In-app chat messages from drivers.',
            'Promotional offers (only if you opt in).',
          ],
          permission: Permission.notification,
        );
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    final config = _config;
    try {
      final status = await config.permission.request();
      if (!mounted) return;
      if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog();
      } else {
        widget.onResult?.call(status);
        Navigator.of(context).pop(status);
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_config.title} Disabled'),
        content: const Text(
          'This permission was permanently denied. Please open your device Settings to enable it manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: Text(config.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: config.iconColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(config.icon, color: config.iconColor, size: 44),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      config.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      config.subtitle,
                      style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Why we need this',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...config.reasons.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: config.iconColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r, style: const TextStyle(fontSize: 14, height: 1.5)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'You can change this permission at any time in your device Settings → 7Dash.',
                          style: TextStyle(fontSize: 12, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _requesting ? null : _requestPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _requesting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                widget.onResult?.call(PermissionStatus.denied);
                Navigator.of(context).pop(PermissionStatus.denied);
              },
              child: const Text('Not Now', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionConfig {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<String> reasons;
  final Permission permission;

  const _PermissionConfig({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.reasons,
    required this.permission,
  });
}
