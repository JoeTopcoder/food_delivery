import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'legal_helpers.dart';

class LegalCenterScreen extends StatelessWidget {
  const LegalCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal Center', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          _header(context, 'Policies & Terms', Icons.gavel_rounded),
          LegalTile(
            icon: Icons.privacy_tip_outlined,
            iconColor: const Color(0xFF0077C8),
            title: 'Privacy Policy',
            subtitle: 'How we collect, use, and protect your data',
            onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
          ),
          LegalTile(
            icon: Icons.description_outlined,
            iconColor: const Color(0xFF7C3AED),
            title: 'Terms & Conditions',
            subtitle: 'Rules governing use of 7Dash services',
            onTap: () => Navigator.of(context).pushNamed('/terms'),
          ),
          LegalTile(
            icon: Icons.replay_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Refund Policy',
            subtitle: 'Eligibility and process for refunds',
            onTap: () => Navigator.of(context).pushNamed('/refund-policy'),
          ),
          LegalTile(
            icon: Icons.cancel_outlined,
            iconColor: const Color(0xFFF59E0B),
            title: 'Cancellation Policy',
            subtitle: 'Rules for cancelling orders and rides',
            onTap: () => Navigator.of(context).pushNamed('/cancellation-policy'),
          ),
          LegalTile(
            icon: Icons.card_membership_outlined,
            iconColor: const Color(0xFF8B5CF6),
            title: 'Subscription Terms',
            subtitle: 'Billing, renewals, and cancellation for 7Dash+',
            onTap: () => Navigator.of(context).pushNamed('/subscription-terms'),
          ),
          const SizedBox(height: 8),
          _header(context, 'Partners & Drivers', Icons.handshake_outlined),
          LegalTile(
            icon: Icons.delivery_dining,
            iconColor: const Color(0xFFEF4444),
            title: 'Driver Safety Policy',
            subtitle: 'Safety standards for all delivery and ride partners',
            onTap: () => Navigator.of(context).pushNamed('/driver-safety-policy'),
          ),
          LegalTile(
            icon: Icons.storefront_outlined,
            iconColor: const Color(0xFFF97316),
            title: 'Restaurant & Provider Terms',
            subtitle: 'Partner agreement for restaurants and service providers',
            onTap: () => Navigator.of(context).pushNamed('/provider-terms'),
          ),
          const SizedBox(height: 8),
          _header(context, 'Account', Icons.manage_accounts_outlined),
          LegalTile(
            icon: Icons.headset_mic_outlined,
            iconColor: const Color(0xFF0EA5E9),
            title: 'Contact Support',
            subtitle: 'Get help from the 7Dash team',
            onTap: () => Navigator.of(context).pushNamed('/contact-support'),
          ),
          LegalTile(
            icon: Icons.delete_forever_outlined,
            iconColor: const Color(0xFFEF4444),
            title: 'Data Deletion Request',
            subtitle: 'Request removal of your personal data',
            onTap: () => Navigator.of(context).pushNamed('/data-deletion-request'),
          ),
          const SizedBox(height: 8),
          _header(context, 'App Information', Icons.info_outline),
          LegalTile(
            icon: Icons.info_outline,
            iconColor: const Color(0xFF6B7280),
            title: 'About 7Dash',
            subtitle: 'App version, company info, and open-source notices',
            onTap: () => Navigator.of(context).pushNamed('/about'),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
