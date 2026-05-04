enum OnboardingRole { customer, driver, restaurant }

extension OnboardingRoleX on OnboardingRole {
  String get dbRole {
    switch (this) {
      case OnboardingRole.customer:
        return 'customer';
      case OnboardingRole.driver:
        return 'driver';
      case OnboardingRole.restaurant:
        return 'restaurant';
    }
  }

  String get legacySafeRole {
    // Constraint allows ('customer','driver','restaurant','admin'); use
    // the canonical dbRole value.
    return dbRole;
  }

  String get label {
    switch (this) {
      case OnboardingRole.customer:
        return 'Order Food';
      case OnboardingRole.driver:
        return 'Earn as Driver';
      case OnboardingRole.restaurant:
        return 'Partner Restaurant';
    }
  }

  String get route {
    switch (this) {
      case OnboardingRole.customer:
        return '/onboarding/customer';
      case OnboardingRole.driver:
        return '/onboarding/driver';
      case OnboardingRole.restaurant:
        return '/onboarding/restaurant';
    }
  }

  static OnboardingRole? fromString(String? value) {
    switch (value) {
      case 'customer':
      case 'user':
        return OnboardingRole.customer;
      case 'driver':
        return OnboardingRole.driver;
      case 'restaurant':
        return OnboardingRole.restaurant;
      default:
        return null;
    }
  }
}
