import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/onboarding_role.dart';

const _selectedRoleKey = 'selected_role_intent';

class RoleIntentNotifier extends AsyncNotifier<OnboardingRole?> {
  @override
  Future<OnboardingRole?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingRoleX.fromString(prefs.getString(_selectedRoleKey));
  }

  Future<void> setRole(OnboardingRole role) async {
    state = AsyncData(role);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedRoleKey, role.dbRole);
  }

  Future<void> clearRole() async {
    state = const AsyncData(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedRoleKey);
  }
}

final roleProvider = AsyncNotifierProvider<RoleIntentNotifier, OnboardingRole?>(
  RoleIntentNotifier.new,
);
