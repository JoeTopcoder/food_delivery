import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class RestaurantOnboardingScreen extends ConsumerStatefulWidget {
  const RestaurantOnboardingScreen({super.key});

  @override
  ConsumerState<RestaurantOnboardingScreen> createState() =>
      _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState
    extends ConsumerState<RestaurantOnboardingScreen> {
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _menuImageUrl = TextEditingController();
  final _item1 = TextEditingController();
  final _item2 = TextEditingController();
  final _item3 = TextEditingController();

  bool _loading = false;
  bool _goLive = false;

  @override
  void dispose() {
    _business.dispose();
    _phone.dispose();
    _address.dispose();
    _menuImageUrl.dispose();
    _item1.dispose();
    _item2.dispose();
    _item3.dispose();
    super.dispose();
  }

  Future<void> _saveStep({required int nextStep, bool goLive = false}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId == null) throw Exception('Please sign in first to continue.');

      await ref.read(roleProvider.notifier).setRole(OnboardingRole.restaurant);
      await ref
          .read(onboardingServiceProvider)
          .saveRestaurantDraft(
            userId: userId,
            businessName: _business.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            onboardingStep: nextStep,
            goLive: goLive,
            menuImageUrl: _menuImageUrl.text.trim().isEmpty
                ? null
                : _menuImageUrl.text.trim(),
            quickItems: [
              {'name': _item1.text.trim(), 'price': 9.99},
              {'name': _item2.text.trim(), 'price': 12.99},
              {'name': _item3.text.trim(), 'price': 15.99},
            ],
          );

      await ref
          .read(onboardingProvider(OnboardingRole.restaurant).notifier)
          .setStep(nextStep);

      if (goLive) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/restaurant-dashboard', (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step =
        ref.watch(onboardingProvider(OnboardingRole.restaurant)).valueOrNull ??
        0;

    return Scaffold(
      appBar: AppBar(title: const Text('Restaurant Onboarding')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Go live in minutes',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Step ${step.clamp(0, 3) + 1} of 4'),
          const SizedBox(height: 20),

          if (step == 0) ...[
            TextField(
              controller: _business,
              decoration: const InputDecoration(labelText: 'Business name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Business phone'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : () => _saveStep(nextStep: 1),
              child: const Text('Save basics'),
            ),
          ],

          if (step == 1) ...[
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: 'Map autofill can be added here',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _saveStep(nextStep: 2),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _saveStep(nextStep: 2),
                    child: const Text('Save address'),
                  ),
                ),
              ],
            ),
          ],

          if (step == 2) ...[
            TextField(
              controller: _menuImageUrl,
              decoration: const InputDecoration(
                labelText: 'Menu image URL (optional)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _item1,
              decoration: const InputDecoration(labelText: 'Quick item 1'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _item2,
              decoration: const InputDecoration(labelText: 'Quick item 2'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _item3,
              decoration: const InputDecoration(labelText: 'Quick item 3'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _saveStep(nextStep: 3),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _saveStep(nextStep: 3),
                    child: const Text('Save menu starter'),
                  ),
                ),
              ],
            ),
          ],

          if (step >= 3) ...[
            SwitchListTile(
              title: const Text('Go Live now'),
              subtitle: const Text(
                'Owner info, Stripe and full menu can be completed later.',
              ),
              value: _goLive,
              onChanged: (v) => setState(() => _goLive = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _saveStep(nextStep: 4, goLive: _goLive),
              icon: const Icon(Icons.rocket_launch),
              label: Text(
                _goLive ? 'Go Live' : 'Save Draft and Continue Later',
              ),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => _saveStep(nextStep: 4, goLive: false),
              child: const Text('Skip owner info and Stripe for now'),
            ),
          ],
        ],
      ),
    );
  }
}
