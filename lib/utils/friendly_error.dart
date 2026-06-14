/// Converts raw exceptions/errors into user-friendly messages.
String friendlyError(Object? error) {
  final msg = error.toString().toLowerCase();

  // Network / DNS
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('no address associated') ||
      msg.contains('connection refused') ||
      msg.contains('network is unreachable') ||
      msg.contains('no internet') ||
      msg.contains('errno = 7')) {
    return 'No internet connection. Please check your network and try again.';
  }

  // Timeout
  if (msg.contains('timed out') || msg.contains('timeout')) {
    return 'Request timed out. Please try again.';
  }

  // Auth
  if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please verify your email before signing in.';
  }
  if (msg.contains('google sign-in was cancelled') ||
      msg.contains('sign_in_canceled')) {
    return 'Google sign-in was cancelled.';
  }
  if (msg.contains('google sign-in is not fully configured')) {
    return 'Google sign-in config is incomplete. Add your app SHA key in Firebase and check Supabase Google provider settings.';
  }
  if (msg.contains('google token was rejected by supabase') ||
      msg.contains('unacceptable audience in id_token')) {
    return 'Google client IDs do not match between Firebase and Supabase.';
  }
  if (msg.contains('google provider is disabled in supabase auth')) {
    return 'Enable Google provider in Supabase Auth settings and try again.';
  }
  if (msg.contains('user already registered') ||
      msg.contains('already been registered') ||
      msg.contains('already registered') ||
      msg.contains('email already')) {
    return 'An account with this email already exists.';
  }
  if (msg.contains('rate limit') ||
      msg.contains('too many requests') ||
      msg.contains('only request this after') ||
      msg.contains('for your security')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (msg.contains('signup') && msg.contains('disabled')) {
    return 'Sign-ups are currently disabled. Please contact support.';
  }
  if (msg.contains('email') && msg.contains('invalid')) {
    return 'Please enter a valid email address.';
  }
  if (msg.contains('database error') || msg.contains('unexpected_failure')) {
    return 'A server error occurred. Please try again.';
  }
  if (msg.contains('weak password') || msg.contains('password')) {
    if (msg.contains('at least')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
  }
  if (msg.contains('jwt expired') ||
      msg.contains('token expired') ||
      msg.contains('refresh_token_not_found') ||
      msg.contains('session expired') ||
      msg.contains('sign out and sign back in') ||
      msg.contains('legacy_jwt') ||
      msg.contains('invalid jwt') ||
      msg.contains('unauthorized_legacy')) {
    return 'Your session has expired. Please sign out and sign in again.';
  }
  if (msg.contains('please sign in first')) {
    return 'Please sign in (or confirm your email) to continue.';
  }
  if (msg.contains('not authorized') ||
      msg.contains('permission denied') ||
      msg.contains('insufficient_privilege')) {
    return 'You don\'t have permission to do that.';
  }

  // Payment / card declines
  if (msg.contains('insufficient funds') || msg.contains('insufficient_funds'))
    return 'Your card has insufficient funds. Please add funds or use a different card.';
  if (msg.contains('card was declined') || msg.contains('card_declined') || msg.contains('do_not_honor'))
    return 'Your card was declined. Please try a different card.';
  if (msg.contains('expired card') || msg.contains('card_expired'))
    return 'Your card is expired. Please use a different card.';
  if (msg.contains('lost_card') || msg.contains('stolen_card'))
    return 'Your card could not be processed. Please use a different card.';

  // Supabase / Postgres
  if (msg.contains('duplicate key') || msg.contains('unique constraint')) {
    return 'This record already exists.';
  }
  if (msg.contains('foreign key') || msg.contains('violates foreign key')) {
    return 'This item is linked to other data and can\'t be changed.';
  }
  if (msg.contains('row-level security') || msg.contains('rls')) {
    return 'Access denied. Please try signing in again.';
  }

  // Server
  if (msg.contains('500') || msg.contains('internal server error')) {
    return 'Something went wrong on our end. Please try again later.';
  }
  if (msg.contains('502') ||
      msg.contains('bad gateway') ||
      msg.contains('503') ||
      msg.contains('service unavailable')) {
    return 'The server is temporarily unavailable. Please try again shortly.';
  }
  if (msg.contains('404') || msg.contains('not found')) {
    return 'The requested item was not found.';
  }

  // Extract edge function error messages (they're wrapped in Exception('...')
  // Pattern: Exception: message
  final errorStr = error.toString();
  if (errorStr.startsWith('Exception: ')) {
    final actualMsg = errorStr.replaceFirst('Exception: ', '').trim();
    // If it's a specific edge function error, pass it through
    if (actualMsg.isNotEmpty && actualMsg.length < 150) {
      return actualMsg;
    }
  }

  // Generic fallback
  return 'Something went wrong. Please try again.';
}
