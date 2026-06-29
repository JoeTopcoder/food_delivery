import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../config/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About 7Dash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        children: [
          // App logo area
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.delivery_dining, color: AppTheme.primaryColor, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  '7Dash',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version ${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Food. Fast. Delivered.',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          _InfoCard(
            isDark: isDark,
            children: [
              _Row(label: 'Company', value: AppConstants.businessLegalName),
              const Divider(height: 1),
              _Row(label: 'Support Email', value: AppConstants.supportEmailAddress),
              const Divider(height: 1),
              _Row(label: 'App Version', value: AppConstants.appVersion),
            ],
          ),
          const SizedBox(height: 20),

          _SectionLabel(label: 'Legal'),
          _InfoCard(
            isDark: isDark,
            children: [
              _NavRow(
                label: 'Privacy Policy',
                onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
              ),
              const Divider(height: 1),
              _NavRow(
                label: 'Terms & Conditions',
                onTap: () => Navigator.of(context).pushNamed('/terms'),
              ),
              const Divider(height: 1),
              _NavRow(
                label: 'Legal Center',
                onTap: () => Navigator.of(context).pushNamed('/legal'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _SectionLabel(label: 'Acknowledgments'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                '7Dash is built with Flutter and is powered by Supabase, Stripe, and other open-source technologies. We are grateful to the communities behind these projects.\n\nThis app may collect and process personal data as described in our Privacy Policy.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: isDark
                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
                      : const Color(0xFF374151),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Center(
            child: Text(
              '© 2026 SevenDash Technologies Limited.\nAll rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  const _InfoCard({required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
