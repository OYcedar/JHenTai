import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../config/server_config.dart';
import '../core/database.dart';
import '../network/eh_client.dart';
import '../utils/site_setting_page_parser.dart';

class SettingRoutes {
  final ServerConfig _config;
  final EHClient _client;
  static const _reservedKeys = {'api_token', 'eh_cookies'};

  SettingRoutes(this._config, this._client);

  Router get router {
    final router = Router();

    router.get('/', _getSettings);
    router.put('/', _updateSettings);
    router.get('/profiles', _listProfiles);
    router.put('/profile', _selectProfile);
    router.get('/export', _exportData);
    router.get('/cache/page', _getPageCache);
    router.delete('/cache/page', _clearPageCache);
    router.get('/logs', _listLogs);
    router.get('/logs/<name>', _readLog);
    router.delete('/logs', _clearLogs);
    router.get('/<key>', _getSetting);
    router.put('/<key>', _updateSetting);
    router.delete('/<key>', _deleteSetting);

    return router;
  }

  Future<Response> _listProfiles(Request request) async {
    try {
      final html = await _client.fetchUserConfigHtml();
      return Response.ok(
        jsonEncode(parseSiteSettingProfiles(html)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to load profiles: $e'}),
      );
    }
  }

  Future<Response> _selectProfile(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }
    final profile = (body['profile'] as num?)?.toInt();
    if (profile == null) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Missing profile'}));
    }
    await _client.cookieManager.storeCookies([Cookie('sp', '$profile')]);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Directory get _logDir => Directory(_config.logDir);

  static String? _envValue(String name) {
    final env = Platform.environment;
    return env[name] ?? env[name.toLowerCase()];
  }

  static bool _envEnabled(String? value, {required bool defaultValue}) {
    if (value == null || value.trim().isEmpty) return defaultValue;
    final v = value.trim().toLowerCase();
    if (v == '0' || v == 'false' || v == 'no') return false;
    if (v == '1' || v == 'true' || v == 'yes') return true;
    return defaultValue;
  }

  static String _maskProxyValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final value = raw.trim();
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.host.isEmpty) return 'configured';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static bool _proxyHasCredentials(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final value = raw.trim();
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.host.isEmpty) return false;
    return uri.userInfo.isNotEmpty;
  }

  static Map<String, dynamic> _proxyEnvItem(String name) {
    final value = _envValue(name);
    return {
      'name': name,
      'configured': value != null && value.trim().isNotEmpty,
      'value': _maskProxyValue(value),
      'hasCredentials': _proxyHasCredentials(value),
    };
  }

  static Map<String, dynamic> _networkRuntime() {
    final httpProxy = _envValue('HTTP_PROXY');
    final httpsProxy = _envValue('HTTPS_PROXY');
    final hathProxy = _envValue('JH_HATH_PROXY');
    final noProxy = _envValue('NO_PROXY');
    return {
      'proxyEnv': [
        _proxyEnvItem('HTTP_PROXY'),
        _proxyEnvItem('HTTPS_PROXY'),
        _proxyEnvItem('JH_HATH_PROXY'),
        _proxyEnvItem('NO_PROXY'),
      ],
      'ehProxySource': (httpsProxy != null && httpsProxy.trim().isNotEmpty)
          ? 'HTTPS_PROXY'
          : (httpProxy != null && httpProxy.trim().isNotEmpty)
              ? 'HTTP_PROXY'
              : 'DIRECT',
      'hathProxySource': (hathProxy != null && hathProxy.trim().isNotEmpty)
          ? 'JH_HATH_PROXY'
          : (httpsProxy != null && httpsProxy.trim().isNotEmpty)
              ? 'HTTPS_PROXY'
              : (httpProxy != null && httpProxy.trim().isNotEmpty)
                  ? 'HTTP_PROXY'
                  : 'DIRECT',
      'hathProxyConfigured': hathProxy != null && hathProxy.trim().isNotEmpty,
      'noProxy': noProxy ?? '',
      'hathPreferIpv4': _envEnabled(
        _envValue('JH_HATH_PREFER_IPV4'),
        defaultValue: false,
      ),
      'imageProxyDebug': _envEnabled(
        _envValue('JH_IMAGE_PROXY_DEBUG'),
        defaultValue: false,
      ),
    };
  }

  List<File> _logFiles() {
    final dir = _logDir;
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.log')
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<Response> _listLogs(Request request) async {
    final logs = _logFiles().map((file) {
      final stat = file.statSync();
      return {
        'name': p.basename(file.path),
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
      };
    }).toList();
    final totalSize =
        logs.fold<int>(0, (sum, item) => sum + (item['size'] as int));

    return Response.ok(
      jsonEncode({'logs': logs, 'totalSize': totalSize}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _readLog(Request request, String name) async {
    final safeName = p.basename(Uri.decodeComponent(name));
    final file = File(p.join(_config.logDir, safeName));
    if (!file.existsSync() ||
        !_logFiles().any((f) => p.basename(f.path) == safeName)) {
      return Response.notFound(
        jsonEncode({'error': 'Log not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final text = await file.readAsString();
    return Response.ok(
      jsonEncode({'name': safeName, 'content': text}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _clearLogs(Request request) async {
    var deleted = 0;
    for (final file in _logFiles()) {
      try {
        await file.delete();
        deleted++;
      } catch (_) {}
    }
    return Response.ok(
      jsonEncode({'success': true, 'deleted': deleted}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getPageCache(Request request) async {
    final row = db.raw.select('''
      SELECT
        COUNT(*) AS count,
        COALESCE(SUM(LENGTH(content)), 0) AS content_bytes,
        COALESCE(SUM(LENGTH(headers)), 0) AS header_bytes
      FROM dio_cache
    ''').first;
    final contentBytes = (row['content_bytes'] as num?)?.toInt() ?? 0;
    final headerBytes = (row['header_bytes'] as num?)?.toInt() ?? 0;
    return Response.ok(
      jsonEncode({
        'count': (row['count'] as num?)?.toInt() ?? 0,
        'size': contentBytes + headerBytes,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _clearPageCache(Request request) async {
    final count =
        db.raw.select('SELECT COUNT(*) AS count FROM dio_cache').first;
    db.raw.execute('DELETE FROM dio_cache');
    return Response.ok(
      jsonEncode({
        'success': true,
        'deleted': (count['count'] as num?)?.toInt() ?? 0,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _exportData(Request request) async {
    List<Map<String, dynamic>> rows(String sql) =>
        db.raw.select(sql).map(_rowToMap).toList();

    final configRows = db.raw
        .select(
          '''
          SELECT key, sub_key, value, utime
          FROM config
          WHERE key NOT IN (${List.filled(_reservedKeys.length, '?').join(',')})
          ORDER BY key ASC, sub_key ASC
        ''',
          _reservedKeys.toList(),
        )
        .map(_rowToMap)
        .toList();

    final data = {
      'format': 'jhentai-web-export-v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sections': {
        'config': configRows,
        'blockRules': rows('SELECT * FROM block_rule ORDER BY id ASC'),
        'history': rows('SELECT * FROM history ORDER BY visit_time DESC'),
        'searchHistory':
            rows('SELECT * FROM search_history ORDER BY last_used DESC'),
        'quickSearch':
            rows('SELECT * FROM quick_search ORDER BY sort_order ASC'),
      },
      'counts': {
        'config': configRows.length,
        'blockRules': db.raw
            .select('SELECT COUNT(*) AS count FROM block_rule')
            .first['count'],
        'history': db.raw
            .select('SELECT COUNT(*) AS count FROM history')
            .first['count'],
        'searchHistory': db.raw
            .select('SELECT COUNT(*) AS count FROM search_history')
            .first['count'],
        'quickSearch': db.raw
            .select('SELECT COUNT(*) AS count FROM quick_search')
            .first['count'],
      },
    };

    return Response.ok(
      const JsonEncoder.withIndent('  ').convert(data),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition': 'attachment; filename="jhentai-web-export.json"',
      },
    );
  }

  Future<Response> _getSettings(Request request) async {
    final settingKeys = [
      'EHSetting',
      'networkSetting',
      'downloadSetting',
      'userSetting',
      'preferenceSetting',
      'styleSetting',
    ];

    final settings = <String, dynamic>{};
    for (final key in settingKeys) {
      final value = db.readConfig(key);
      if (value != null) {
        try {
          settings[key] = jsonDecode(value);
        } catch (_) {
          settings[key] = value;
        }
      }
    }

    settings['server'] = {
      'dataDir': _config.dataDir,
      'downloadDir': _config.downloadDir,
      'localGalleryDir': _config.localGalleryDir,
      'extraScanPaths': _config.extraScanPaths,
      'maxConcurrentGalleryDownloads': _config.maxConcurrentGalleryDownloads,
      'maxConcurrentArchiveDownloads': _config.maxConcurrentArchiveDownloads,
      'downloadAllGalleriesOfSamePriority':
          _config.downloadAllGalleriesOfSamePriority,
    };
    settings['network'] = _networkRuntime();

    return Response.ok(
      jsonEncode(settings),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _updateSettings(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    for (final entry in body.entries) {
      if (_reservedKeys.contains(entry.key)) continue;
      final value =
          entry.value is String ? entry.value : jsonEncode(entry.value);
      db.writeConfig(entry.key, value);
    }

    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getSetting(Request request, String key) async {
    final value = db.readConfig(key);
    if (value == null) {
      return Response.ok(
        jsonEncode({'key': key, 'value': null}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(value);
    } catch (_) {
      parsed = value;
    }

    return Response.ok(
      jsonEncode({'key': key, 'value': parsed}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _updateSetting(Request request, String key) async {
    if (_reservedKeys.contains(key)) {
      return Response.forbidden(
        jsonEncode({'error': 'Cannot modify reserved key: $key'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final value = body['value'];
    final valueStr = value is String ? value : jsonEncode(value);

    db.writeConfig(key, valueStr);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _deleteSetting(Request request, String key) async {
    if (_reservedKeys.contains(key)) {
      return Response.forbidden(
        jsonEncode({'error': 'Cannot delete reserved key: $key'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    db.deleteConfig(key);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _rowToMap(Row row) {
    final map = <String, dynamic>{};
    for (final key in row.keys) {
      map[key] = row[key];
    }
    return map;
  }
}
