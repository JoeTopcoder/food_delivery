import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../utils/app_theme.dart';
import '../../config/app_constants.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme Section ──
          _SectionHeader(title: l10n.themeMode, icon: Icons.palette_outlined),
          const SizedBox(height: 8),
          _ThemeCard(
            currentTheme: currentTheme,
            isDark: isDark,
            onChanged: (mode) {
              ref.read(themeModeProvider.notifier).setThemeMode(mode);
            },
            l10n: l10n,
          ),
          const SizedBox(height: 24),

          // ── Language Section ──
          _SectionHeader(title: l10n.language, icon: Icons.language_outlined),
          const SizedBox(height: 8),
          _LanguageCard(
            currentLocale: currentLocale,
            isDark: isDark,
            onChanged: (locale) {
              if (locale == null) {
                ref.read(localeProvider.notifier).clearLocale();
              } else {
                ref.read(localeProvider.notifier).setLocale(locale);
              }
            },
            l10n: l10n,
          ),
          const SizedBox(height: 24),

          // ── Legal & Support Section ──
          _SectionHeader(title: 'Legal & Support', icon: Icons.gavel_outlined),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _LegalTile(
                    icon: Icons.account_balance_outlined,
                    label: 'Legal Center',
                    onTap: () => Navigator.of(context).pushNamed('/legal'),
                  ),
                  const Divider(height: 1),
                  _LegalTile(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
                  ),
                  const Divider(height: 1),
                  _LegalTile(
                    icon: Icons.description_outlined,
                    label: 'Terms & Conditions',
                    onTap: () => Navigator.of(context).pushNamed('/terms'),
                  ),
                  const Divider(height: 1),
                  _LegalTile(
                    icon: Icons.headset_mic_outlined,
                    label: 'Contact Support',
                    onTap: () => Navigator.of(context).pushNamed('/contact-support'),
                  ),
                  const Divider(height: 1),
                  _LegalTile(
                    icon: Icons.delete_sweep_outlined,
                    label: 'Delete Account',
                    onTap: () => Navigator.of(context).pushNamed('/delete-account'),
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${AppConstants.appDisplayName} v${AppConstants.appVersion}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ThemeMode currentTheme;
  final bool isDark;
  final ValueChanged<ThemeMode> onChanged;
  final AppLocalizations l10n;

  const _ThemeCard({
    required this.currentTheme,
    required this.isDark,
    required this.onChanged,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _ThemeOption(
              icon: Icons.light_mode_outlined,
              label: l10n.light,
              selected: currentTheme == ThemeMode.light,
              onTap: () => onChanged(ThemeMode.light),
            ),
            const Divider(height: 1),
            _ThemeOption(
              icon: Icons.dark_mode_outlined,
              label: l10n.dark,
              selected: currentTheme == ThemeMode.dark,
              onTap: () => onChanged(ThemeMode.dark),
            ),
            const Divider(height: 1),
            _ThemeOption(
              icon: Icons.settings_brightness_outlined,
              label: l10n.system,
              selected: currentTheme == ThemeMode.system,
              onTap: () => onChanged(ThemeMode.system),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: selected ? AppTheme.primaryColor : null),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? AppTheme.primaryColor : null,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final Locale? currentLocale;
  final bool isDark;
  final ValueChanged<Locale?> onChanged;
  final AppLocalizations l10n;

  const _LanguageCard({
    required this.currentLocale,
    required this.isDark,
    required this.onChanged,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final languages = <_LangOption>[
      _LangOption(
        locale: const Locale('en'),
        label: l10n.english,
        flag: '🇺🇸',
      ),
      _LangOption(
        locale: const Locale('es'),
        label: l10n.spanish,
        flag: '🇪🇸',
      ),
      _LangOption(locale: const Locale('fr'), label: l10n.french, flag: '🇫🇷'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (int i = 0; i < languages.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _LanguageOption(
                flag: languages[i].flag,
                label: languages[i].label,
                selected:
                    currentLocale?.languageCode ==
                    languages[i].locale.languageCode,
                onTap: () => onChanged(languages[i].locale),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LangOption {
  final Locale locale;
  final String label;
  final String flag;

  const _LangOption({
    required this.locale,
    required this.label,
    required this.flag,
  });
}

class _LanguageOption extends StatelessWidget {
  final String flag;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? AppTheme.primaryColor : null,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _LegalTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFEF4444) : AppTheme.primaryColor;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: isDestructive ? const Color(0xFFEF4444) : null,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
      dense: true,
    );
  }
}
