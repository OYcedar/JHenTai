import 'dart:io';

/// When true, log each successful image proxy and extra detail for `/api/image/*`.
/// Set env `JH_IMAGE_PROXY_DEBUG=1` (Docker / systemd / shell).
bool jhImageProxyDebugEnabled() {
  final v = Platform.environment['JH_IMAGE_PROXY_DEBUG']?.trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes' || v == 'on';
}
