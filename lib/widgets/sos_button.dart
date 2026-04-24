import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_feedback_widgets.dart';
import '../utils/friendly_error.dart';

/// A reusable Emergency SOS button and dialog.
/// Shows an SOS icon button that opens a bottom sheet with emergency contacts.
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showSosSheet(context),
      icon: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.sos_rounded, size: 20, color: Colors.red),
      ),
      tooltip: 'Emergency SOS',
    );
  }

  static void showSosSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _SosSheetContent(),
    );
  }
}

class _SosSheetContent extends StatelessWidget {
  const _SosSheetContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emergency_rounded,
              size: 32,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Emergency SOS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'If you are in danger, contact emergency services immediately',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Emergency number
          _SosOption(
            icon: Icons.call_rounded,
            label: 'Call Emergency (911)',
            subtitle: 'Police / Fire / Ambulance',
            color: Colors.red,
            onTap: () => _makeCall('911'),
          ),
          const SizedBox(height: 10),
          _SosOption(
            icon: Icons.local_police_rounded,
            label: 'Call Police (911)',
            subtitle: 'Royal Cayman Islands Police Service',
            color: const Color(0xFF1E40AF),
            onTap: () => _makeCall('911'),
          ),
          const SizedBox(height: 10),
          _SosOption(
            icon: Icons.support_agent_rounded,
            label: 'Contact FoodHub Support',
            subtitle: 'Report an issue with your delivery',
            color: AppTheme.primaryColor,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/support');
            },
          ),
          const SizedBox(height: 10),
          _SosOption(
            icon: Icons.share_location_rounded,
            label: 'Share Live Location',
            subtitle: 'Send your location to a trusted contact',
            color: const Color(0xFF10B981),
            onTap: () async {
              Navigator.pop(context);
              await _shareLocation(context);
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _makeCall(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static Future<void> _shareLocation(BuildContext context) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          AppSnackbar.warning(context, 'Please enable location services');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          AppSnackbar.warning(context, 'Location permission is required');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final mapsUrl =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      final message =
          'EMERGENCY - I need help! Here is my current location: $mapsUrl';

      await Share.share(message);
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

class _SosOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SosOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
