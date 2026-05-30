enum OnboardingRole { customer, driver, restaurant, serviceProvider }

extension OnboardingRoleX on OnboardingRole {
  String get dbRole {
    switch (this) {
      case OnboardingRole.customer:
        return 'customer';
      case OnboardingRole.driver:
        return 'driver';
      case OnboardingRole.restaurant:
        return 'restaurant';
      case OnboardingRole.serviceProvider:
        return 'service_provider';
    }
  }

  String get legacySafeRole {
    // DB constraint allows ('customer','driver','restaurant','admin','service_provider').
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
      case OnboardingRole.serviceProvider:
        return 'Car Service Provider';
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
      case OnboardingRole.serviceProvider:
        return '/onboarding/service-provider';
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
      case 'service_provider':
        return OnboardingRole.serviceProvider;
      default:
        return null;
    }
  }
}
