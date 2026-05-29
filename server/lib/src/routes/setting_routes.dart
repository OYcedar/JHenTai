import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' hide Response;
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
    router.get('/cloud/alive', _cloudAlive);
    router.get('/cloud/configs', _cloudListConfigs);
    router.get('/cloud/config', _cloudGetConfigByShareCode);
    router.post('/cloud/config/delete', _cloudDeleteConfig);
    router.get('/export', _exportData);
    router.post('/import', _importData);
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

  Dio _cloudClient() => Dio(
        BaseOptions(
          baseUrl: _config.jhPublicApiBaseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

  Future<Response> _proxyCloudRequest(Future<dynamic> Function() run) async {
    try {
      final response = await run();
      final data = response.data;
      return Response.ok(
        data is String ? data : jsonEncode(data),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 502;
      final data = e.response?.data;
      final message = data is Map && data['message'] != null
          ? data['message'].toString()
          : (e.message ?? e.toString());
      return Response(
        status,
        body: jsonEncode({'code': status, 'message': message, 'data': null}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'code': 500, 'message': '$e', 'data': null}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  Future<Response> _cloudAlive(Request request) {
    return _proxyCloudRequest(() => _cloudClient().get('/alive'));
  }

  Future<Response> _cloudListConfigs(Request request) {
    final type = int.tryParse(request.url.queryParameters['type'] ?? '');
    return _proxyCloudRequest(
      () => _cloudClient().get(
        '/api/config/list',
        queryParameters: {if (type != null) 'type': type},
      ),
    );
  }

  Future<Response> _cloudGetConfigByShareCode(Request request) async {
    final shareCode = request.url.queryParameters['shareCode']?.trim() ?? '';
    if (shareCode.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing shareCode'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    return _proxyCloudRequest(
      () => _cloudClient().get(
        '/api/config/getByShareCode',
        queryParameters: {'shareCode': shareCode},
      ),
    );
  }

  Future<Response> _cloudDeleteConfig(Request request) {
    return _proxyCloudRequest(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final id = (body['id'] as num?)?.toInt();
      if (id == null) {
        throw ArgumentError('Missing id');
      }
      return _cloudClient().post(
        '/api/config/delete',
        queryParameters: {'id': id},
      );
    });
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
    if (request.url.queryParameters['format'] == 'app') {
      return _exportAppData();
    }

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

  Response _exportAppData() {
    final now = DateTime.now();
    final ctime = now.toUtc().millisecondsSinceEpoch;
    final configs = <Map<String, dynamic>>[];

    void addConfig(int type, Object config) {
      final encoded = jsonEncode(config);
      if (encoded == '[]' || encoded == '{}') {
        return;
      }
      configs.add({
        'id': -1,
        'shareCode': 'local',
        'identificationCode': 'local',
        'type': type,
        'version': '1.0.0',
        'config': encoded,
        'ctime': ctime,
      });
    }

    addConfig(1, _exportAppReadProgress());
    addConfig(2, _exportAppQuickSearch());
    addConfig(3, _exportAppBlockRules());
    addConfig(4, _exportAppSearchHistory());
    addConfig(5, _exportAppHistory());

    return Response.ok(
      const JsonEncoder.withIndent('  ').convert(configs),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition':
            'attachment; filename="JHenTaiConfig-${_formatExportTimestamp(now)}.json"',
      },
    );
  }

  Future<Response> _importData(Request request) async {
    dynamic body;
    try {
      body = jsonDecode(await request.readAsString());
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid JSON body'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    db.raw.execute('BEGIN TRANSACTION');
    late Map<String, int> imported;
    late String source;
    try {
      if (body is Map &&
          body['format'] == 'jhentai-web-export-v1' &&
          body['sections'] is Map) {
        imported = _importWebExportSections(
            Map<String, dynamic>.from(body['sections']));
        source = 'web';
      } else if (body is List) {
        imported = _importAppCloudConfigs(body);
        source = 'app';
      } else {
        db.raw.execute('ROLLBACK');
        return Response.badRequest(
          body: jsonEncode({'error': 'Unsupported import format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      db.raw.execute('COMMIT');
    } catch (e) {
      db.raw.execute('ROLLBACK');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to import data: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'success': true, 'source': source, 'imported': imported}),
      headers: {'Content-Type': 'application/json'},
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
      'galleryUpgradeReuseImages': _config.galleryUpgradeReuseImages,
      'jhPublicApiBaseUrl': _config.jhPublicApiBaseUrl,
      'jhAppId': _config.jhAppId,
      'jhApiSecretConfigured': _config.jhApiSecret.trim().isNotEmpty,
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

  Map<String, int> _importWebExportSections(Map<String, dynamic> sections) {
    final imported = _emptyImportCounts();
    final now = DateTime.now().toIso8601String();

    for (final row in _importRows(sections['config'])) {
      final key = _importString(row['key']);
      if (key.isEmpty || _reservedKeys.contains(key)) {
        continue;
      }
      final subKey = _importString(row['sub_key']);
      final value = row['value'];
      final valueStr = value is String ? value : jsonEncode(value);
      _writeConfigRow(
        key: key,
        subKey: subKey,
        value: valueStr,
        utime: _importString(row['utime'], fallback: now),
      );
      imported['config'] = imported['config']! + 1;
    }

    final existingRules = db
        .selectAllBlockRules()
        .map((rule) => _blockRuleFingerprint(rule))
        .toSet();
    for (final row in _importRows(sections['blockRules'])) {
      if (_insertBlockRuleIfNew(row, existingRules)) {
        imported['blockRules'] = imported['blockRules']! + 1;
      }
    }

    for (final row in _importRows(sections['history'])) {
      final gid = _importInt(row['gid']);
      if (gid == null) {
        continue;
      }
      _writeHistoryRow(
        gid: gid,
        token: _importString(row['token']),
        title: _importString(row['title']),
        coverUrl: _importString(row['cover_url']),
        category: _importString(row['category']),
        visitTime: _importString(row['visit_time'], fallback: now),
      );
      imported['history'] = imported['history']! + 1;
    }

    for (final row in _importRows(sections['searchHistory'])) {
      final keyword = _importString(row['keyword']).trim();
      if (keyword.isEmpty) {
        continue;
      }
      _writeSearchHistoryRow(
        keyword: keyword,
        useCount: _importInt(row['use_count']) ?? 1,
        lastUsed: _importString(row['last_used'], fallback: now),
      );
      imported['searchHistory'] = imported['searchHistory']! + 1;
    }

    for (final row in _importRows(sections['quickSearch'])) {
      final name = _importString(row['name']).trim();
      if (name.isEmpty) {
        continue;
      }
      final config = row['config'] is String
          ? row['config'] as String
          : jsonEncode(row['config']);
      db.upsertQuickSearch(
        name,
        config,
        sortOrder: _importInt(row['sort_order']) ?? 0,
      );
      imported['quickSearch'] = imported['quickSearch']! + 1;
    }

    return imported;
  }

  Map<String, int> _importAppCloudConfigs(List<dynamic> configs) {
    final imported = _emptyImportCounts();
    final existingRules = db
        .selectAllBlockRules()
        .map((rule) => _blockRuleFingerprint(rule))
        .toSet();
    for (final item in configs.whereType<Map>()) {
      final config = Map<String, dynamic>.from(item);
      final type = _importInt(config['type']);
      final raw = _importString(config['config']);
      if (type == null || raw.isEmpty) {
        continue;
      }
      final decoded = jsonDecode(raw);
      switch (type) {
        case 1:
          for (final row in _importRows(decoded)) {
            final subKey = _importString(row['subConfigKey']).trim();
            final value = _importString(row['value']).trim();
            if (subKey.isEmpty || value.isEmpty) {
              continue;
            }
            _writeConfigRow(
              key: 'read_progress_$subKey',
              value: value,
              utime: _importString(row['utime'],
                  fallback: DateTime.now().toIso8601String()),
            );
            imported['readProgress'] = imported['readProgress']! + 1;
          }
        case 2:
          if (decoded is Map) {
            var order = 0;
            for (final entry in decoded.entries) {
              final name = entry.key.toString().trim();
              if (name.isEmpty) {
                continue;
              }
              db.upsertQuickSearch(
                name,
                entry.value is String
                    ? entry.value as String
                    : jsonEncode(entry.value),
                sortOrder: order++,
              );
              imported['quickSearch'] = imported['quickSearch']! + 1;
            }
          }
        case 3:
          for (final row in _importRows(decoded)) {
            final rule = _convertAppBlockRule(row);
            if (rule != null && _insertBlockRuleIfNew(rule, existingRules)) {
              imported['blockRules'] = imported['blockRules']! + 1;
            }
          }
        case 4:
          if (decoded is List) {
            var offset = 0;
            final now = DateTime.now();
            for (final item in decoded) {
              final keyword = _importString(item).trim();
              if (keyword.isEmpty) {
                continue;
              }
              _writeSearchHistoryRow(
                keyword: keyword,
                useCount: 1,
                lastUsed:
                    now.subtract(Duration(seconds: offset++)).toIso8601String(),
              );
              imported['searchHistory'] = imported['searchHistory']! + 1;
            }
          }
        case 5:
          for (final row in _importRows(decoded)) {
            if (_importAppHistoryRow(row)) {
              imported['history'] = imported['history']! + 1;
            }
          }
      }
    }
    return imported;
  }

  List<Map<String, dynamic>> _exportAppReadProgress() {
    final rows = db.raw.select(
      '''
      SELECT key, value, utime
      FROM config
      WHERE key LIKE 'read_progress_%'
        AND key NOT LIKE 'read_progress_local_%'
      ORDER BY key ASC
      ''',
    );
    return rows.map((row) {
      final key = _importString(row['key']);
      return {
        'configKey': 'readIndexRecord',
        'subConfigKey': key.replaceFirst('read_progress_', ''),
        'value': _importString(row['value']),
        'utime': _importString(row['utime']),
      };
    }).toList();
  }

  Map<String, dynamic> _exportAppQuickSearch() {
    final out = <String, dynamic>{};
    for (final row in db.selectAllQuickSearches()) {
      final name = _importString(row['name']).trim();
      final raw = _importString(row['config']);
      if (name.isEmpty || raw.isEmpty) {
        continue;
      }
      try {
        out[name] = jsonDecode(raw);
      } catch (_) {
        out[name] = raw;
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _exportAppBlockRules() {
    return db
        .selectAllBlockRules()
        .map(_convertWebBlockRuleToApp)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<String> _exportAppSearchHistory() {
    return db.raw
        .select('SELECT keyword FROM search_history ORDER BY last_used DESC')
        .map((row) => _importString(row['keyword']).trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _exportAppHistory() {
    return db.raw
        .select('SELECT * FROM history ORDER BY visit_time DESC LIMIT 10000')
        .map((row) {
      final gid = _importInt(row['gid']) ?? 0;
      final token = _importString(row['token']);
      return {
        'gid': gid,
        'jsonBody': jsonEncode({
          'galleryUrl': 'https://e-hentai.org/g/$gid/$token/',
          'title': _importString(row['title']),
          'category': _importString(row['category']),
          'coverUrl': _importString(row['cover_url']),
          'pageCount': 0,
          'rating': 0.0,
          'language': '',
          'uploader': '',
          'publishTime': '',
          'isExpunged': false,
          'tags': <String>[],
        }),
        'lastReadTime': _importString(row['visit_time']),
      };
    }).toList();
  }

  Map<String, dynamic>? _convertWebBlockRuleToApp(Map<String, dynamic> row) {
    const targets = {
      'gallery': 0,
      'comment': 1,
    };
    const attributes = {
      'title': 0,
      'tag': 10,
      'uploader': 20,
      'gid': 30,
      'userName': 100,
      'userId': 110,
      'score': 120,
      'content': 130,
    };
    const patterns = {
      'equal': 0,
      'gt': 10,
      'gte': 20,
      'st': 30,
      'ste': 40,
      'like': 50,
      'notContain': 60,
      'regex': 70,
    };
    final expression = _importString(row['expression']);
    if (expression.isEmpty) {
      return null;
    }
    final target = targets[_importString(row['target'])];
    final attribute = attributes[_importString(row['attribute'])];
    final pattern = patterns[_importString(row['pattern'])];
    if (target == null || attribute == null || pattern == null) {
      return null;
    }
    return {
      'id': null,
      'groupId': _importString(row['group_id']),
      'target': target,
      'attribute': attribute,
      'pattern': pattern,
      'expression': expression,
    };
  }

  static String _formatExportTimestamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  Map<String, int> _emptyImportCounts() {
    return {
      'config': 0,
      'blockRules': 0,
      'history': 0,
      'searchHistory': 0,
      'quickSearch': 0,
      'readProgress': 0,
    };
  }

  void _writeConfigRow({
    required String key,
    String subKey = '',
    required String value,
    required String utime,
  }) {
    db.raw.execute(
      'INSERT OR REPLACE INTO config (key, sub_key, value, utime) VALUES (?, ?, ?, ?)',
      [key, subKey, value, utime],
    );
  }

  bool _insertBlockRuleIfNew(
    Map<String, dynamic> row,
    Set<String> existingRules,
  ) {
    final rule = {
      'group_id': _importString(row['group_id'] ?? row['groupId']),
      'target': _importString(row['target'], fallback: 'gallery'),
      'attribute': _importString(row['attribute'], fallback: 'title'),
      'pattern': _importString(row['pattern'], fallback: 'like'),
      'expression': _importString(row['expression']),
    };
    if ((rule['expression'] as String).isEmpty) {
      return false;
    }
    final fingerprint = _blockRuleFingerprint(rule);
    if (existingRules.contains(fingerprint)) {
      return false;
    }
    db.insertBlockRule(rule);
    existingRules.add(fingerprint);
    return true;
  }

  Map<String, dynamic>? _convertAppBlockRule(Map<String, dynamic> row) {
    const targets = {
      0: 'gallery',
      1: 'comment',
    };
    const attributes = {
      0: 'title',
      10: 'tag',
      20: 'uploader',
      30: 'gid',
      100: 'userName',
      110: 'userId',
      120: 'score',
      130: 'content',
    };
    const patterns = {
      0: 'equal',
      10: 'gt',
      20: 'gte',
      30: 'st',
      40: 'ste',
      50: 'like',
      60: 'notContain',
      70: 'regex',
    };
    final target = targets[_importInt(row['target'])];
    final attribute = attributes[_importInt(row['attribute'])];
    final pattern = patterns[_importInt(row['pattern'])];
    final expression = _importString(row['expression']);
    if (target == null ||
        attribute == null ||
        pattern == null ||
        expression.isEmpty) {
      return null;
    }
    return {
      'group_id': _importString(row['groupId']),
      'target': target,
      'attribute': attribute,
      'pattern': pattern,
      'expression': expression,
    };
  }

  void _writeSearchHistoryRow({
    required String keyword,
    required int useCount,
    required String lastUsed,
  }) {
    db.raw.execute(
      '''
      INSERT OR REPLACE INTO search_history
      (keyword, use_count, last_used)
      VALUES (?, ?, ?)
    ''',
      [keyword, useCount, lastUsed],
    );
  }

  void _writeHistoryRow({
    required int gid,
    required String token,
    required String title,
    required String coverUrl,
    required String category,
    required String visitTime,
  }) {
    db.raw.execute(
      '''
      INSERT OR REPLACE INTO history
      (gid, token, title, cover_url, category, visit_time)
      VALUES (?, ?, ?, ?, ?, ?)
    ''',
      [gid, token, title, coverUrl, category, visitTime],
    );
  }

  bool _importAppHistoryRow(Map<String, dynamic> row) {
    final gid = _importInt(row['gid']);
    final jsonBodyRaw = row['jsonBody'];
    if (gid == null || jsonBodyRaw is! String || jsonBodyRaw.isEmpty) {
      return false;
    }
    final body = jsonDecode(jsonBodyRaw);
    if (body is! Map) {
      return false;
    }
    final gallery = Map<String, dynamic>.from(body);
    final parsed = _parseGalleryUrl(_importString(gallery['galleryUrl']));
    _writeHistoryRow(
      gid: gid,
      token: parsed.token,
      title: _importString(gallery['title']),
      coverUrl: _importString(gallery['coverUrl']),
      category: _importString(gallery['category']),
      visitTime: _importString(
        row['lastReadTime'],
        fallback: DateTime.now().toIso8601String(),
      ),
    );
    return true;
  }

  ({int? gid, String token}) _parseGalleryUrl(String url) {
    final match = RegExp(r'/g/(\d+)/([^/?#]+)').firstMatch(url);
    if (match == null) {
      return (gid: null, token: '');
    }
    return (
      gid: int.tryParse(match.group(1) ?? ''),
      token: match.group(2) ?? ''
    );
  }

  List<Map<String, dynamic>> _importRows(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _importString(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    return value.toString();
  }

  int? _importInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  String _blockRuleFingerprint(Map<String, dynamic> rule) {
    return [
      _importString(rule['group_id']),
      _importString(rule['target']),
      _importString(rule['attribute']),
      _importString(rule['pattern']),
      _importString(rule['expression']),
    ].join('\u{1f}');
  }
}
