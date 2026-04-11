import 'package:web/web.dart' as web;

/// Verbose image logs in the browser console when
/// `localStorage.setItem('jh_image_debug', '1')` (then reload).
bool webImageClientDebugEnabled() {
  try {
    final v = web.window.localStorage.getItem('jh_image_debug') ?? '';
    final t = v.trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes' || t == 'on';
  } catch (_) {
    return false;
  }
}

void webImageClientLogVerbose(String message) {
  if (!webImageClientDebugEnabled()) return;
  // ignore: avoid_print
  print('[JH image] $message');
}

/// Always printed on load failures so you can diagnose without enabling debug.
void webImageClientLogError(String message) {
  // ignore: avoid_print
  print('[JH image] ERROR $message');
}
