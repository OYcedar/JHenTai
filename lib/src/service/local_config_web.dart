import 'dart:convert';

import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/local_config_models.dart';
import 'package:web/web.dart' as web;

LocalConfigService localConfigService = LocalConfigService();

/// Web/Docker UI: persist style and other settings in `localStorage` (no SQLite).
class LocalConfigService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String defaultSubConfigKey = '';
  static const _storageKey = 'jh_local_config_store';

  final Map<String, String> _cache = {};

  String _compositeKey(String configKey, String subKey) => '$configKey\x00$subKey';

  void _loadCache() {
    if (_cache.isNotEmpty) return;
    final raw = web.window.localStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is String) {
          _cache[k] = v;
        }
      });
    } catch (_) {}
  }

  void _persist() {
    web.window.localStorage.setItem(_storageKey, jsonEncode(_cache));
  }

  @override
  Future<void> doInitBean() async {
    _loadCache();
  }

  @override
  Future<void> doAfterBeanReady() async {}

  Future<int> write({required ConfigEnum configKey, String subConfigKey = defaultSubConfigKey, required String value}) async {
    _loadCache();
    _cache[_compositeKey(configKey.key, subConfigKey)] = value;
    _persist();
    return 1;
  }

  Future<void> batchWrite(List<LocalConfig> localConfigs) async {
    _loadCache();
    for (final c in localConfigs) {
      _cache[_compositeKey(c.configKey.key, c.subConfigKey)] = c.value;
    }
    _persist();
  }

  Future<String?> read({required ConfigEnum configKey, String subConfigKey = defaultSubConfigKey}) async {
    _loadCache();
    return _cache[_compositeKey(configKey.key, subConfigKey)];
  }

  Future<List<LocalConfig>> readWithAllSubKeys({required ConfigEnum configKey}) async {
    _loadCache();
    final prefix = '${configKey.key}\x00';
    final out = <LocalConfig>[];
    for (final e in _cache.entries) {
      if (e.key.startsWith(prefix)) {
        final sub = e.key.substring(prefix.length);
        out.add(LocalConfig(
          configKey: configKey,
          subConfigKey: sub,
          value: e.value,
          utime: '',
        ));
      }
    }
    return out;
  }

  Future<bool> delete({required ConfigEnum configKey, String subConfigKey = defaultSubConfigKey}) async {
    _loadCache();
    final k = _compositeKey(configKey.key, subConfigKey);
    final removed = _cache.remove(k) != null;
    if (removed) {
      _persist();
    }
    return removed;
  }
}
