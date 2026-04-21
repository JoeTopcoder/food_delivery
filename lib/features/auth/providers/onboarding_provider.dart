import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/onboarding_role.dart';

String _stepKey(OnboardingRole role) => 'onboarding_step_${role.dbRole}';

class OnboardingProgressNotifier
    extends FamilyAsyncNotifier<int, OnboardingRole> {
  @override
  Future<int> build(OnboardingRole arg) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stepKey(arg)) ?? 0;
  }

  Future<void> setStep(int step) async {
    final role = arg;
    state = AsyncData(step);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stepKey(role), step);
  }

  Future<void> reset() async {
    final role = arg;
    state = const AsyncData(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stepKey(role));
  }
}

final onboardingProvider =
    AsyncNotifierProviderFamily<
      OnboardingProgressNotifier,
      int,
      OnboardingRole
    >(OnboardingProgressNotifier.new);
