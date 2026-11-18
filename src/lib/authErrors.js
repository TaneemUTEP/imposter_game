/** Convert Supabase auth/setup errors into short player-facing guidance. */
export function getAuthErrorMessage(error) {
  const code = String(error?.code || '').toLowerCase();
  const message = String(error?.message || '').toLowerCase();

  if (code === 'anonymous_provider_disabled' || message.includes('anonymous sign-ins are disabled')) {
    return 'Guest play is turned off in this game’s Supabase settings. Turn on Authentication → Sign In / Providers → Allow anonymous sign-ins, or open Profile to create or sign in to an email account.';
  }
  if (code === 'email_provider_disabled' || message.includes('email signups are disabled')) {
    return 'Email sign-up is turned off in the Supabase project. Enable the Email provider in Authentication → Sign In / Providers.';
  }
  if (code === 'email_not_confirmed') return 'Confirm your email from the message we sent, then sign in here.';
  if (message.includes('redirect url') && message.includes('not allowed')) return 'Email confirmation is not set up for this website yet. Add this site’s URL to Supabase Authentication → URL Configuration → Redirect URLs.';
  if (message.includes('invalid login credentials')) return 'That email and password did not match. Check them or choose “Create account”.';
  if (code === 'email_exists' || message.includes('user already registered')) return 'An account already uses that email. Choose “Sign in” instead.';
  if (message.includes('password should be at least')) return 'Choose a password with at least 8 characters.';
  if (code === 'over_email_send_rate_limit') return 'Too many verification emails were requested. Wait a little and try again.';
  if (error?.message === 'BACKEND_NOT_CONFIGURED') return 'Online rooms are not configured yet. Please try again later.';

  return error?.message || 'Something went wrong. Please try again.';
}
