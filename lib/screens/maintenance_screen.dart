import 'package:flutter/material.dart';
import '../config/app_constants.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = AppConstants.supportPhone;
    final email = AppConstants.supportEmail;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.build_rounded,
                    size: 44,
                    color: Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Under Maintenance',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                const Text(
                  "We're making improvements to give you a better experience. We'll be back shortly.",
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF94A3B8),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (phone.isNotEmpty || email.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Text(
                    'Need help?',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (phone.isNotEmpty)
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF60A5FA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
