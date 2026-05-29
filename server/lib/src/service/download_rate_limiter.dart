import '../core/database.dart';

const webDownloadSpeedLimitMaximumKey = 'web_download_speed_limit_maximum';
const webDownloadSpeedLimitPeriodSecondsKey =
    'web_download_speed_limit_period_seconds';

class DownloadRateLimiter {
  DateTime _windowStart = DateTime.now();
  int _usedInWindow = 0;
  Future<void> _tail = Future.value();

  Future<void> waitForSlot() {
    final next = _tail.then((_) => _waitForSlotLocked());
    _tail = next.catchError((_) {});
    return next;
  }

  Future<void> _waitForSlotLocked() async {
    final maximum =
        int.tryParse(db.readConfig(webDownloadSpeedLimitMaximumKey) ?? '') ??
            99;
    final periodSeconds = int.tryParse(
            db.readConfig(webDownloadSpeedLimitPeriodSecondsKey) ?? '') ??
        1;
    if (maximum >= 99 || maximum <= 0 || periodSeconds <= 0) {
      return;
    }

    final period = Duration(seconds: periodSeconds);
    var now = DateTime.now();
    final elapsed = now.difference(_windowStart);
    if (elapsed >= period || elapsed.isNegative) {
      _windowStart = now;
      _usedInWindow = 0;
    }

    if (_usedInWindow >= maximum) {
      final wait = period - now.difference(_windowStart);
      if (!wait.isNegative) {
        await Future<void>.delayed(wait);
      }
      now = DateTime.now();
      _windowStart = now;
      _usedInWindow = 0;
    }

    _usedInWindow++;
  }
}
