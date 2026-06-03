import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Row;

import '../config/server_config.dart';
import '../core/database.dart';
import '../network/eh_client.dart';
import '../service/archive_download_service.dart';
import '../service/download_issue_summary.dart';
import '../service/download_runtime_settings.dart';
import '../service/gallery_download_service.dart';
import '../service/super_resolution_service.dart';
import '../utils/site_setting_page_parser.dart';

class _ImportSectionSummary {
  int importable = 0;
  int skipped = 0;
  int replacing = 0;

  Map<String, dynamic> toJson() => {
        'importable': importable,
        'skipped': skipped,
        'replacing': replacing,
      };
}

class _ImportSummary {
  final sections = <String, _ImportSectionSummary>{
    'config': _ImportSectionSummary(),
    'blockRules': _ImportSectionSummary(),
    'history': _ImportSectionSummary(),
    'searchHistory': _ImportSectionSummary(),
    'quickSearch': _ImportSectionSummary(),
    'readProgress': _ImportSectionSummary(),
  };

  _ImportSectionSummary section(String key) => sections[key]!;

  int get importable =>
      sections.values.fold(0, (sum, section) => sum + section.importable);
  int get skipped =>
      sections.values.fold(0, (sum, section) => sum + section.skipped);
  int get replacing =>
      sections.values.fold(0, (sum, section) => sum + section.replacing);

  Map<String, dynamic> toJson() => {
        'importable': importable,
        'skipped': skipped,
        'replacing': replacing,
        'sections': {
          for (final entry in sections.entries) entry.key: entry.value.toJson(),
        },
      };
}

class _RestoreTableSpec {
  final String table;
  final String summaryKey;

  const _RestoreTableSpec(this.table, this.summaryKey);
}

class SettingRoutes {
  final ServerConfig _config;
  final EHClient _client;
  final GalleryDownloadService _galleryDownloadService;
  final ArchiveDownloadService _archiveDownloadService;
  final SuperResolutionService _superResolutionService;
  static const _reservedKeys = {'api_token', 'eh_cookies'};
  static const _restoreTables = [
    _RestoreTableSpec('config', 'config'),
    _RestoreTableSpec('history', 'history'),
    _RestoreTableSpec('search_history', 'searchHistory'),
    _RestoreTableSpec('quick_search', 'quickSearch'),
    _RestoreTableSpec('block_rule', 'blockRules'),
    _RestoreTableSpec('gallery_download', 'galleryDownloads'),
    _RestoreTableSpec('gallery_image', 'galleryImages'),
    _RestoreTableSpec('archive_download', 'archiveDownloads'),
    _RestoreTableSpec('tag_translation', 'tagTranslations'),
    _RestoreTableSpec('tag_count', 'tagCounts'),
  ];

  SettingRoutes(
    this._config,
    this._client,
    this._galleryDownloadService,
    this._archiveDownloadService,
    this._superResolutionService,
  );

  Router get router {
    final router = Router();

    router.get('/', _getSettings);
    router.put('/', _updateSettings);
    router.get('/profiles', _listProfiles);
    router.put('/profile', _selectProfile);
    router.get('/cloud/alive', _cloudAlive);
    router.get('/cloud/configs', _cloudListConfigs);
    router.get('/cloud/config', _cloudGetConfigByShareCode);
    router.post('/cloud/config/upload', _cloudUploadConfigs);
    router.post('/cloud/config/delete', _cloudDeleteConfig);
    router.get('/export', _exportData);
    router.post('/import', _importData);
    router.get('/cache/page', _getPageCache);
    router.delete('/cache/page', _clearPageCache);
    router.get('/network/timeouts', _getNetworkTimeouts);
    router.put('/network/timeouts', _updateNetworkTimeouts);
    router.get('/setup-checklist', _getSetupChecklist);
    router.get('/diagnostics', _getDiagnostics);
    router.get('/maintenance', _getMaintenance);
    router.get('/maintenance/update-check', _checkMaintenanceUpdate);
    router.get('/troubleshooting', _getTroubleshooting);
    router.post('/troubleshooting/probe', _probeTroubleshooting);
    router.get('/backup/sqlite', _downloadSqliteBackup);
    router.post('/backup/sqlite/restore', _restoreSqliteBackup);
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

  Future<Response> _cloudUploadConfigs(Request request) {
    return _proxyCloudRequest(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final rawTypes = body['types'];
      final selectedTypes = rawTypes is List
          ? rawTypes
              .map((value) => (value as num?)?.toInt())
              .whereType<int>()
              .toSet()
          : <int>{};
      final configs = _exportAppConfigs()
          .where((config) =>
              selectedTypes.isEmpty ||
              selectedTypes.contains((config['type'] as num?)?.toInt()))
          .map((config) => {
                'type': config['type'],
                'version': config['version'],
                'config': config['config'],
              })
          .toList();
      if (configs.isEmpty) {
        throw ArgumentError('No config data to upload');
      }
      return _cloudClient().post(
        '/api/config/upload',
        options: Options(contentType: Headers.jsonContentType),
        data: {'configs': configs},
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
      'connectTimeout': db.readConfig('web_connect_timeout') ??
          _defaultNetworkTimeoutMs.toString(),
      'receiveTimeout': db.readConfig('web_receive_timeout') ??
          _defaultNetworkTimeoutMs.toString(),
    };
  }

  static const int _defaultNetworkTimeoutMs = 6000;
  static const int _minNetworkTimeoutMs = 1000;
  static const int _maxNetworkTimeoutMs = 600000;

  int _normalizeNetworkTimeout(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback)
        .clamp(_minNetworkTimeoutMs, _maxNetworkTimeoutMs)
        .toInt();
  }

  Map<String, int> _currentNetworkTimeouts() {
    final connect = _normalizeNetworkTimeout(
      db.readConfig('web_connect_timeout'),
      _client.connectTimeoutMs,
    );
    final receive = _normalizeNetworkTimeout(
      db.readConfig('web_receive_timeout'),
      _client.receiveTimeoutMs,
    );
    return {'connectTimeout': connect, 'receiveTimeout': receive};
  }

  Future<Response> _getNetworkTimeouts(Request request) async {
    return Response.ok(
      jsonEncode(_currentNetworkTimeouts()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _updateNetworkTimeouts(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid JSON'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final current = _currentNetworkTimeouts();
    final connect = _normalizeNetworkTimeout(
      body['connectTimeout'],
      current['connectTimeout']!,
    );
    final receive = _normalizeNetworkTimeout(
      body['receiveTimeout'],
      current['receiveTimeout']!,
    );
    db.writeConfig('web_connect_timeout', connect.toString());
    db.writeConfig('web_receive_timeout', receive.toString());
    _client.updateTimeouts(
      connectTimeout: connect,
      receiveTimeout: receive,
    );
    return Response.ok(
      jsonEncode({'connectTimeout': connect, 'receiveTimeout': receive}),
      headers: {'Content-Type': 'application/json'},
    );
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

  Future<Response> _getSetupChecklist(Request request) async {
    return Response.ok(
      jsonEncode(_setupChecklistPayload()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _setupChecklistPayload() {
    final diagnostics = _diagnosticsPayload();
    final maintenance = _maintenancePayload();
    final downloadIssues = _downloadIssuesPayload();
    final superResolution = _superResolutionSnapshot();
    final network = _networkRuntime();
    final runtime = _runtimeInfo();
    final checks = <Map<String, dynamic>>[];

    void add({
      required String id,
      required String group,
      required String label,
      required String status,
      required String detail,
      required String hint,
      String? route,
      String? copyText,
    }) {
      checks.add({
        'id': id,
        'group': group,
        'label': label,
        'status': status,
        'detail': detail,
        'hint': hint,
        if (route != null) 'route': route,
        if (copyText != null && copyText.isNotEmpty) 'copyText': copyText,
      });
    }

    final apiTokenConfigured = (db.readConfig('api_token') ?? '').isNotEmpty;
    add(
      id: 'api_token',
      group: 'service',
      label: 'API token',
      status: apiTokenConfigured ? 'ok' : 'warn',
      detail: apiTokenConfigured
          ? 'API token is configured for browser access.'
          : 'API token is not stored in the database yet.',
      hint:
          'Open the setup page with the token printed in Docker logs if this browser cannot access the API.',
      route: '/web/setup',
    );

    final cookies = db.readConfig('eh_cookies') ?? '';
    add(
      id: 'eh_login',
      group: 'account',
      label: 'EH login cookies',
      status: cookies.trim().isNotEmpty ? 'ok' : 'warn',
      detail: cookies.trim().isNotEmpty
          ? 'EH cookies are stored.'
          : 'EH cookies are not configured.',
      hint:
          'Set EH cookies in Account settings before browsing ExHentai or downloading protected galleries.',
      route: '/web/settings/account',
    );

    final diagnosticChecks =
        (diagnostics['checks'] as List? ?? const []).whereType<Map>();
    for (final check in diagnosticChecks) {
      final id = check['id']?.toString() ?? '';
      if (!{
        'http_api',
        'data_dir',
        'download_dir',
        'log_dir',
        'temp_dir',
        'database',
      }.contains(id)) {
        continue;
      }
      add(
        id: 'diagnostics_$id',
        group: check['group']?.toString() ?? 'storage',
        label: check['label']?.toString() ?? id,
        status: check['status']?.toString() ?? 'warn',
        detail: check['detail']?.toString() ?? '',
        hint: check['hint']?.toString() ?? '',
        route: '/web/settings/diagnostics',
      );
    }

    final dockerTag = runtime['dockerTag']?.toString() ?? 'local/dev';
    final forkRevision = runtime['forkRevision']?.toString() ?? 'local/dev';
    final pinned = dockerTag != 'latest' && dockerTag != 'local/dev';
    add(
      id: 'docker_version',
      group: 'maintenance',
      label: 'Docker image tag',
      status: pinned ? 'ok' : 'warn',
      detail: 'Current tag: $dockerTag, fork revision: $forkRevision',
      hint:
          'Use an explicit x.y.z-hhh tag in compose updates; avoid relying on latest for long-running NAS deployments.',
      route: '/web/settings/maintenance',
    );

    add(
      id: 'sqlite_backup',
      group: 'maintenance',
      label: 'SQLite backup',
      status: 'warn',
      detail:
          'SQLite backup can be downloaded from the maintenance center before updates or restores.',
      hint:
          'Download a fresh SQLite backup before changing image versions, restoring data, or experimenting with imports.',
      route: '/web/settings/maintenance',
    );

    final hathProxy = network['hathProxySource']?.toString() ?? 'direct';
    final proxyConfigured = hathProxy != 'direct';
    add(
      id: 'proxy_runtime',
      group: 'network',
      label: 'Proxy routing',
      status: proxyConfigured ? 'ok' : 'skipped',
      detail: 'H@H route: $hathProxy',
      hint:
          'If gallery pages work but H@H images fail, configure JH_HATH_PROXY or test H@H from the troubleshooting workbench.',
      route: '/web/settings/network',
    );

    final srCaps = superResolution['capabilities'] is Map
        ? Map<String, dynamic>.from(superResolution['capabilities'] as Map)
        : const <String, dynamic>{};
    final srModels = srCaps['models'] is Map
        ? Map<String, dynamic>.from(srCaps['models'] as Map)
        : const <String, dynamic>{};
    final installedModels = srModels.values
        .where((item) => item is Map && item['installed'] == true)
        .length;
    final srGpu = srCaps['gpu'] is Map
        ? Map<String, dynamic>.from(srCaps['gpu'] as Map)
        : const <String, dynamic>{};
    add(
      id: 'super_resolution',
      group: 'superResolution',
      label: 'Image super resolution',
      status: srCaps['status'] == 'ok' && installedModels > 0 ? 'ok' : 'warn',
      detail:
          'Runtime: ${srCaps['status'] ?? 'warn'}, installed models: $installedModels',
      hint:
          'Pass /dev/dri into the container and install at least one model before enabling automatic super-resolution.',
      route: '/web/settings/super-resolution',
      copyText: srGpu['composeSnippet']?.toString(),
    );

    final downloadSummary = downloadIssues['summary'] is Map
        ? Map<String, dynamic>.from(downloadIssues['summary'] as Map)
        : const <String, dynamic>{};
    final failedTotal = (downloadSummary['failedTotal'] as num?)?.toInt() ?? 0;
    add(
      id: 'download_failures',
      group: 'downloads',
      label: 'Download failures',
      status: failedTotal == 0 ? 'ok' : 'warn',
      detail: failedTotal == 0
          ? 'No failed download tasks are currently reported.'
          : '$failedTotal failed download tasks need attention.',
      hint:
          'Open Downloads or the troubleshooting workbench to retry failed tasks and test H@H/proxy routing.',
      route:
          failedTotal == 0 ? '/web/downloads' : '/web/settings/troubleshooting',
    );

    final errorCount = checks.where((item) => item['status'] == 'error').length;
    final warningCount =
        checks.where((item) => item['status'] == 'warn').length;
    final status = errorCount > 0
        ? 'error'
        : warningCount > 0
            ? 'warn'
            : 'ok';
    return {
      'status': status,
      'generatedAt': DateTime.now().toIso8601String(),
      'summary': {
        'errorCount': errorCount,
        'warningCount': warningCount,
        'total': checks.length,
      },
      'checks': checks,
      'maintenance': maintenance,
      'network': network,
    };
  }

  Future<Response> _getDiagnostics(Request request) async {
    return Response.ok(
      jsonEncode(_diagnosticsPayload()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _diagnosticsPayload() {
    final checks = <Map<String, dynamic>>[];
    void addCheck({
      required String id,
      required String group,
      required String label,
      required String status,
      required String detail,
      required String hint,
    }) {
      checks.add({
        'id': id,
        'group': group,
        'label': label,
        'status': status,
        'detail': detail,
        'hint': hint,
      });
    }

    addCheck(
      id: 'http_api',
      group: 'service',
      label: 'HTTP API',
      status: 'ok',
      detail: 'API is responding',
      hint: 'If the web UI cannot reach the API, check reverse proxy rules.',
    );

    for (final item in [
      ('data_dir', 'Data directory', _config.dataDir, true),
      ('download_dir', 'Download directory', _config.downloadDir, true),
      (
        'local_gallery_dir',
        'Local gallery directory',
        _config.localGalleryDir,
        true
      ),
      ('log_dir', 'Log directory', _config.logDir, true),
      ('temp_dir', 'Temp directory', _config.tempDir, true),
      ('config_dir', 'Config directory', _config.configDir, true),
    ]) {
      addCheck(
        id: item.$1,
        group: 'storage',
        label: item.$2,
        status: _directoryStatus(item.$3, requireWritable: item.$4),
        detail: _directoryDetail(item.$3, requireWritable: item.$4),
        hint: _directoryHint(item.$3, requireWritable: item.$4),
      );
    }

    if (_config.extraScanPaths.isEmpty) {
      addCheck(
        id: 'extra_scan_paths',
        group: 'localGallery',
        label: 'Extra scan paths',
        status: 'ok',
        detail: 'No extra scan paths configured',
        hint:
            'Configure JH_EXTRA_SCAN_PATHS only when additional folders are mounted.',
      );
    } else {
      for (var i = 0; i < _config.extraScanPaths.length; i++) {
        final path = _config.extraScanPaths[i];
        addCheck(
          id: 'extra_scan_path_$i',
          group: 'localGallery',
          label: 'Extra scan path ${i + 1}',
          status: _directoryStatus(path, requireWritable: false),
          detail: _directoryDetail(path, requireWritable: false),
          hint: _directoryHint(path, requireWritable: false),
        );
      }
    }

    final databaseCheck = _databaseCheck();
    addCheck(
      id: 'database',
      group: 'database',
      label: 'SQLite database',
      status: databaseCheck['status']!,
      detail: databaseCheck['detail']!,
      hint: databaseCheck['hint']!,
    );

    final logs = _logsSummary();
    addCheck(
      id: 'logs',
      group: 'logs',
      label: 'Server logs',
      status: logs['status'] as String,
      detail: logs['detail'] as String,
      hint: logs['hint'] as String,
    );

    final errorCount = checks.where((c) => c['status'] == 'error').length;
    final warningCount = checks.where((c) => c['status'] == 'warn').length;
    final status = errorCount > 0
        ? 'error'
        : warningCount > 0
            ? 'warn'
            : 'ok';

    return {
      'status': status,
      'generatedAt': DateTime.now().toIso8601String(),
      'checks': checks,
      'summary': {
        'errorCount': errorCount,
        'warningCount': warningCount,
      },
      'network': _networkRuntime(),
      'logs': logs,
    };
  }

  Future<Response> _getMaintenance(Request request) async {
    return Response.ok(
      jsonEncode(_maintenancePayload()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _maintenancePayload() {
    final logs = _logsSummary();
    final pageCache = _pageCacheStats();
    final databaseFile = File(_config.databasePath);
    final databaseBytes =
        databaseFile.existsSync() ? databaseFile.statSync().size : 0;
    final checks = [
      _pathStatus('dataDir', _config.dataDir, writable: true),
      _pathStatus('downloadDir', _config.downloadDir, writable: true),
      _pathStatus('localGalleryDir', _config.localGalleryDir, writable: true),
      _pathStatus('logDir', _config.logDir, writable: true),
      _pathStatus('tempDir', _config.tempDir, writable: true),
    ];
    final warningCount = checks.where((item) => item['status'] != 'ok').length;
    return {
      'status': warningCount > 0 ? 'warn' : 'ok',
      'generatedAt': DateTime.now().toIso8601String(),
      'runtime': _runtimeInfo(),
      'paths': {
        'dataDir': _config.dataDir,
        'downloadDir': _config.downloadDir,
        'localGalleryDir': _config.localGalleryDir,
        'logDir': _config.logDir,
        'tempDir': _config.tempDir,
      },
      'storage': {
        'databaseBytes': databaseBytes,
        'logsBytes': logs['totalSize'] ?? 0,
        'pageCacheBytes': pageCache['size'] ?? 0,
        'pageCacheCount': pageCache['count'] ?? 0,
      },
      'checks': checks,
      'logs': logs,
    };
  }

  Future<Response> _getTroubleshooting(Request request) async {
    final diagnostics = _diagnosticsPayload();
    final maintenance = _maintenancePayload();
    final superResolution = _superResolutionSnapshot();
    final downloadIssues = _downloadIssuesPayload();
    final recentProblems = _recentProblemLogs();
    final issues = _troubleshootingIssues(
      diagnostics,
      maintenance,
      superResolution,
      downloadIssues,
      recentProblems,
    );
    final issueCount = _troubleshootingIssueCount(
      diagnostics,
      maintenance,
      superResolution,
      downloadIssues,
      recentProblems,
    );
    return Response.ok(
      jsonEncode({
        'status': issueCount > 0 ? 'warn' : 'ok',
        'generatedAt': DateTime.now().toIso8601String(),
        'summary': {'issueCount': issueCount},
        'issues': issues,
        'diagnostics': diagnostics,
        'maintenance': maintenance,
        'downloads': downloadIssues,
        'network': _networkRuntime(),
        'logs': {
          ..._logsSummary(),
          'recentProblems': recentProblems,
        },
        'superResolution': superResolution,
        'actions': _troubleshootingActions(superResolution),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _probeTroubleshooting(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }
    final probes = (body['probes'] as List? ?? const [])
        .map((item) => item.toString())
        .toSet();
    final imageUrl = body['imageUrl']?.toString().trim();
    final results = <String, dynamic>{};
    if (probes.contains('network')) {
      results['network'] = await _probeNetwork();
    }
    if (probes.contains('hath')) {
      results['hath'] = await _probeHath(imageUrl);
    }
    if (probes.contains('superResolution')) {
      results['superResolution'] = _probeSuperResolution();
    }
    if (probes.contains('downloads')) {
      results['downloads'] = _downloadIssuesPayload();
    }
    return Response.ok(
      jsonEncode({
        'success': true,
        'generatedAt': DateTime.now().toIso8601String(),
        'results': results,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _superResolutionSnapshot() {
    final capabilities = _superResolutionService.capabilities();
    final jobs = _superResolutionService.listJobs();
    final failedJobs = jobs
        .where((job) => job['status'] == 'failed')
        .take(8)
        .map((job) => {
              'id': job['id'],
              'sourceType': job['sourceType'],
              'gid': job['gid'],
              'title': job['title'],
              'status': job['status'],
              'error': _sanitizeLogText(job['error']?.toString() ?? ''),
              'updatedAt': job['updatedAt'],
            })
        .toList();
    return {
      'capabilities': capabilities,
      'settings': _superResolutionService.settings(),
      'jobs': {
        'total': jobs.length,
        'running': jobs.where((job) => job['status'] == 'running').length,
        'pending': jobs.where((job) => job['status'] == 'pending').length,
        'failed': jobs.where((job) => job['status'] == 'failed').length,
        'failedRecent': failedJobs,
      },
    };
  }

  Map<String, dynamic> _downloadIssuesPayload() {
    return DownloadIssueSummary.build(
      galleryTasks: _galleryDownloadService.tasks.map((task) => task.toJson()),
      archiveTasks: _archiveDownloadService.tasks.map((task) => task.toJson()),
    );
  }

  int _troubleshootingIssueCount(
    Map<String, dynamic> diagnostics,
    Map<String, dynamic> maintenance,
    Map<String, dynamic> superResolution,
    Map<String, dynamic> downloadIssues,
    List<Map<String, dynamic>> recentProblems,
  ) {
    final diagnosticSummary = diagnostics['summary'] is Map
        ? Map<String, dynamic>.from(diagnostics['summary'] as Map)
        : const <String, dynamic>{};
    final diagnosticIssues =
        ((diagnosticSummary['errorCount'] as num?)?.toInt() ?? 0) +
            ((diagnosticSummary['warningCount'] as num?)?.toInt() ?? 0);
    final maintenanceIssues = maintenance['status'] == 'ok' ? 0 : 1;
    final srCaps = superResolution['capabilities'] is Map
        ? Map<String, dynamic>.from(superResolution['capabilities'] as Map)
        : const <String, dynamic>{};
    final srIssues = srCaps['status'] == 'ok' ? 0 : 1;
    final downloadSummary = downloadIssues['summary'] is Map
        ? Map<String, dynamic>.from(downloadIssues['summary'] as Map)
        : const <String, dynamic>{};
    final downloadIssueCount =
        (downloadSummary['failedTotal'] as num?)?.toInt() ?? 0;
    return diagnosticIssues +
        maintenanceIssues +
        srIssues +
        downloadIssueCount +
        recentProblems.length.clamp(0, 5).toInt();
  }

  List<Map<String, dynamic>> _troubleshootingIssues(
    Map<String, dynamic> diagnostics,
    Map<String, dynamic> maintenance,
    Map<String, dynamic> superResolution,
    Map<String, dynamic> downloadIssues,
    List<Map<String, dynamic>> recentProblems,
  ) {
    final issues = <Map<String, dynamic>>[];
    final checks =
        (diagnostics['checks'] as List? ?? const []).whereType<Map>();
    for (final check in checks) {
      final status = check['status']?.toString() ?? 'ok';
      if (status == 'ok') continue;
      issues.add({
        'id': 'diagnostics_${check['id']}',
        'group': check['group']?.toString() ?? 'storage',
        'status': status,
        'title': check['label']?.toString() ?? 'Deployment check',
        'detail': check['detail']?.toString() ?? '',
        'hint': check['hint']?.toString() ?? '',
        'route': '/web/settings/diagnostics',
        'probe': check['group'] == 'network' ? 'network' : null,
      });
    }

    final downloadGroups =
        (downloadIssues['groups'] as List? ?? const []).whereType<Map>();
    for (final group in downloadGroups) {
      final category = group['category']?.toString() ?? 'unknown';
      issues.add({
        'id': 'downloads_$category',
        'group': category == 'hath'
            ? 'hath'
            : (category == 'archiveBot' ? 'network' : 'downloads'),
        'status': 'warn',
        'titleKey': group['titleKey'],
        'detailKey': group['detailKey'],
        'count': group['count'],
        'route': category == 'archiveBot'
            ? '/web/settings/download'
            : '/web/downloads',
        'probe': category == 'hath' ? 'hath' : 'downloads',
        'actions': group['actions'],
      });
    }

    final srCaps = superResolution['capabilities'] is Map
        ? Map<String, dynamic>.from(superResolution['capabilities'] as Map)
        : const <String, dynamic>{};
    if (srCaps['status'] != 'ok') {
      final warnings = (srCaps['warnings'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .join(' ');
      final gpu = srCaps['gpu'] is Map
          ? Map<String, dynamic>.from(srCaps['gpu'] as Map)
          : const <String, dynamic>{};
      issues.add({
        'id': 'super_resolution_runtime',
        'group': 'superResolution',
        'status': 'warn',
        'titleKey': 'superResolution.title',
        'detail': warnings,
        'route': '/web/settings/super-resolution',
        'probe': 'superResolution',
        if ((gpu['composeSnippet']?.toString() ?? '').isNotEmpty)
          'copyText': gpu['composeSnippet'].toString(),
      });
    }
    final srModels = srCaps['models'] is Map
        ? Map<String, dynamic>.from(srCaps['models'] as Map)
        : const <String, dynamic>{};
    for (final entry in srModels.entries) {
      final model = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : const <String, dynamic>{};
      if (model['installed'] == true && model['executable'] != true) {
        issues.add({
          'id': 'super_resolution_model_permission_${entry.key}',
          'group': 'superResolution',
          'status': 'warn',
          'title': 'Super-resolution model is not executable',
          'detail':
              '${model['label'] ?? entry.key} is installed but cannot be executed.',
          'route': '/web/settings/super-resolution',
          'actions': [
            {
              'id': 'repair_model_permission',
              'model': entry.key,
              'labelKey': 'superResolution.repairPermission',
              'confirm': false,
            }
          ],
        });
      }
    }

    if (maintenance['status'] != 'ok') {
      issues.add({
        'id': 'maintenance_paths',
        'group': 'storage',
        'status': 'warn',
        'titleKey': 'settings.maintenanceCenter',
        'detailKey': 'settings.maintenanceCenterSummary',
        'route': '/web/settings/maintenance',
      });
    }

    if (recentProblems.isNotEmpty) {
      issues.add({
        'id': 'recent_problem_logs',
        'group': 'logs',
        'status': 'warn',
        'titleKey': 'settings.troubleshootingRecentProblems',
        'detail': recentProblems.first['line']?.toString() ?? '',
        'route': '/web/settings/advanced',
      });
    }

    return issues.take(24).toList();
  }

  List<Map<String, dynamic>> _troubleshootingActions(
      Map<String, dynamic> superResolution) {
    final caps = superResolution['capabilities'] is Map
        ? Map<String, dynamic>.from(superResolution['capabilities'] as Map)
        : const <String, dynamic>{};
    final gpu = caps['gpu'] is Map
        ? Map<String, dynamic>.from(caps['gpu'] as Map)
        : const <String, dynamic>{};
    return [
      {
        'id': 'open_network',
        'label': 'Open network settings',
        'route': '/web/settings/network',
      },
      {
        'id': 'open_logs',
        'label': 'Open server logs',
        'route': '/web/settings/advanced',
      },
      {
        'id': 'open_super_resolution',
        'label': 'Open image super resolution',
        'route': '/web/settings/super-resolution',
      },
      if ((gpu['composeSnippet']?.toString() ?? '').isNotEmpty)
        {
          'id': 'copy_gpu_compose',
          'label': 'Copy GPU compose snippet',
          'text': gpu['composeSnippet'].toString(),
        },
    ];
  }

  List<Map<String, dynamic>> _recentProblemLogs({int maxItems = 20}) {
    final result = <Map<String, dynamic>>[];
    final pattern = RegExp(
      r'(error|warn|warning|exception|failed|HandshakeException|super_resolution:auto)',
      caseSensitive: false,
    );
    for (final file in _logFiles()) {
      List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        continue;
      }
      for (final line in lines.reversed) {
        if (!pattern.hasMatch(line)) continue;
        result.add({
          'file': p.basename(file.path),
          'line': _sanitizeLogText(line),
        });
        if (result.length >= maxItems) return result;
      }
    }
    return result;
  }

  String? _latestHathUrlFromLogs() {
    final urlPattern = RegExp(
        r'https?://[^\s"' '<>]+\.hath\.network/[^\s"' '<>]+',
        caseSensitive: false);
    for (final file in _logFiles()) {
      List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        continue;
      }
      for (final line in lines.reversed) {
        final match = urlPattern.firstMatch(line);
        if (match != null) return match.group(0);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _probeNetwork() async {
    final started = DateTime.now();
    try {
      final response = await _client.probeUrl('https://e-hentai.org/');
      final statusCode = (response['statusCode'] as num?)?.toInt() ?? 0;
      final ok = statusCode >= 200 && statusCode < 500;
      return {
        'status': ok ? 'ok' : 'error',
        'target': 'https://e-hentai.org/',
        'statusCode': statusCode,
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'detail': ok
            ? 'EH front domain is reachable through current route.'
            : _sanitizeLogText(response['error']?.toString() ??
                'Unexpected status code: $statusCode'),
        'route': _networkRuntime()['ehProxySource'],
      };
    } catch (e) {
      return {
        'status': 'error',
        'target': 'https://e-hentai.org/',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'detail': _sanitizeLogText('$e'),
        'route': _networkRuntime()['ehProxySource'],
      };
    }
  }

  Future<Map<String, dynamic>> _probeHath(String? imageUrl) async {
    final target = (imageUrl != null && imageUrl.isNotEmpty)
        ? imageUrl
        : _latestHathUrlFromLogs();
    if (target == null || target.isEmpty) {
      return {
        'status': 'skipped',
        'detail':
            'No H@H image URL was provided or found in recent logs. Paste a failing image URL to test this path.',
        'route': _networkRuntime()['hathProxySource'],
      };
    }
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.host.toLowerCase().endsWith('.hath.network')) {
      return {
        'status': 'skipped',
        'target': _sanitizeLogText(target),
        'detail': 'Target is not a *.hath.network URL.',
        'route': _networkRuntime()['hathProxySource'],
      };
    }
    final started = DateTime.now();
    try {
      final response = await _client.probeUrl(target);
      final statusCode = (response['statusCode'] as num?)?.toInt() ?? 0;
      final ok = statusCode >= 200 && statusCode < 500;
      return {
        'status': ok ? 'ok' : 'error',
        'target': _sanitizeLogText(target),
        'statusCode': statusCode,
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'detail': ok
            ? 'H@H image host is reachable through current route.'
            : _sanitizeLogText(response['error']?.toString() ??
                'Unexpected status code: $statusCode'),
        'route': _networkRuntime()['hathProxySource'],
      };
    } catch (e) {
      return {
        'status': 'error',
        'target': _sanitizeLogText(target),
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'detail': _sanitizeLogText('$e'),
        'route': _networkRuntime()['hathProxySource'],
      };
    }
  }

  Map<String, dynamic> _probeSuperResolution() {
    final caps = _superResolutionService.capabilities();
    final gpu = caps['gpu'] is Map
        ? Map<String, dynamic>.from(caps['gpu'] as Map)
        : const <String, dynamic>{};
    final runtime = caps['runtime'] is Map
        ? Map<String, dynamic>.from(caps['runtime'] as Map)
        : const <String, dynamic>{};
    final models = caps['models'] is Map
        ? Map<String, dynamic>.from(caps['models'] as Map)
        : const <String, dynamic>{};
    final installedModels = models.values.where((model) {
      return model is Map && model['installed'] == true;
    }).length;
    final devices = (gpu['devices'] as List? ?? const []).whereType<Map>();
    final blockedDevices = devices.where((device) {
      return device['readable'] != true || device['writable'] != true;
    }).length;
    final issues = <String>[
      if (runtime['supportedPrebuiltBinary'] != true)
        'Current architecture is not the amd64 prebuilt path.',
      if (gpu['hasDevDri'] != true && gpu['nvidiaVisible'] != true)
        'No /dev/dri or NVIDIA device is visible inside the container.',
      if (blockedDevices > 0)
        '$blockedDevices GPU device entries are not readable/writable.',
      if (installedModels == 0) 'No super-resolution model is installed.',
    ];
    return {
      'status': issues.isEmpty ? 'ok' : 'warn',
      'detail': issues.isEmpty
          ? 'Super-resolution runtime looks ready.'
          : issues.join(' '),
      'capabilities': caps,
      'composeSnippet': gpu['composeSnippet']?.toString() ?? '',
    };
  }

  String _sanitizeLogText(String value) {
    var text = value;
    text = text.replaceAll(
      RegExp(r'\b[a-fA-F0-9]{64}\b'),
      '<redacted-token>',
    );
    text = text.replaceAll(
      RegExp(r'(?i)(cookie|set-cookie|eh_cookies)[=:][^\s,;]+'),
      r'$1=<redacted>',
    );
    text = text.replaceAllMapped(
      RegExp(r'([a-z][a-z0-9+.-]*://)([^/@\s:]+):([^/@\s]+)@',
          caseSensitive: false),
      (match) => '${match.group(1)}<redacted>@',
    );
    return text.length > 600 ? '${text.substring(0, 600)}...' : text;
  }

  Future<Response> _checkMaintenanceUpdate(Request request) async {
    final runtime = _runtimeInfo();
    final currentTag = runtime['dockerTag']?.toString() ?? 'local/dev';
    if (currentTag == 'local/dev') {
      return Response.ok(
        jsonEncode({
          'status': 'warn',
          'currentTag': currentTag,
          'latestTag': null,
          'updateAvailable': false,
          'message':
              'Current runtime does not expose a Docker image tag. Build/publish images with JH_DOCKER_TAG metadata.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final response = await dio.get(
        'https://hub.docker.com/v2/repositories/hemumoe/jhentai/tags',
        queryParameters: {'page_size': 100},
      );
      final results = response.data is Map ? response.data['results'] : null;
      if (results is! List) {
        throw StateError('Unexpected Docker Hub response');
      }
      final tags = results
          .whereType<Map>()
          .map((item) => item['name']?.toString() ?? '')
          .where(_isVersionTag)
          .toList();
      tags.sort(_compareVersionTags);
      final latestTag = tags.isEmpty ? null : tags.last;
      final updateAvailable =
          latestTag != null && _compareVersionTags(currentTag, latestTag) < 0;
      return Response.ok(
        jsonEncode({
          'status': latestTag == null ? 'warn' : 'ok',
          'currentTag': currentTag,
          'latestTag': latestTag,
          'updateAvailable': updateAvailable,
          'message': latestTag == null
              ? 'No versioned Docker Hub tags were found.'
              : updateAvailable
                  ? 'A newer Docker image is available.'
                  : 'Current Docker image is up to date.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.ok(
        jsonEncode({
          'status': 'warn',
          'currentTag': currentTag,
          'latestTag': null,
          'updateAvailable': false,
          'message': 'Failed to check Docker Hub: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _downloadSqliteBackup(Request request) async {
    await Directory(_config.tempDir).create(recursive: true);
    final now = DateTime.now();
    final filename = 'jhentai-sqlite-backup-${_backupTimestamp(now)}.sqlite';
    final backupPath = p.join(
      _config.tempDir,
      '$filename.tmp-${now.microsecondsSinceEpoch}',
    );
    final backupFile = File(backupPath);
    try {
      final result = await Process.run(
        'sqlite3',
        [_config.databasePath, '.backup $backupPath'],
      );
      if (result.exitCode != 0) {
        throw StateError(
          (result.stderr?.toString().trim().isNotEmpty ?? false)
              ? result.stderr.toString().trim()
              : 'sqlite3 exited with ${result.exitCode}',
        );
      }
      final bytes = await backupFile.readAsBytes();
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': 'attachment; filename="$filename"',
        },
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create SQLite backup: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    } finally {
      try {
        if (backupFile.existsSync()) backupFile.deleteSync();
      } catch (_) {}
    }
  }

  Future<Response> _restoreSqliteBackup(Request request) async {
    final dryRun = request.url.queryParameters['dryRun'] == 'true';
    final activeDownloads = _activeDownloadsSummary();
    if (!dryRun &&
        ((activeDownloads['gallery'] ?? 0) > 0 ||
            (activeDownloads['archive'] ?? 0) > 0)) {
      return Response(
        409,
        body: jsonEncode({
          'error':
              'Active downloads are running. Pause or wait for them before restoring a SQLite backup.',
          'activeDownloads': activeDownloads,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    await Directory(_config.tempDir).create(recursive: true);
    final uploadedPath = p.join(
      _config.tempDir,
      'restore-upload-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final uploadedFile = File(uploadedPath);
    try {
      final sink = uploadedFile.openWrite();
      await for (final chunk in request.read()) {
        sink.add(chunk);
      }
      await sink.close();
      if (!uploadedFile.existsSync() || uploadedFile.lengthSync() == 0) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Empty SQLite backup file'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = dryRun
          ? _analyzeAttachedSqliteBackup(uploadedPath)
          : await _restoreAttachedSqliteBackup(uploadedPath);
      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': dryRun
              ? 'Failed to analyze SQLite backup: $e'
              : 'Failed to restore SQLite backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } finally {
      try {
        if (uploadedFile.existsSync()) uploadedFile.deleteSync();
      } catch (_) {}
    }
  }

  Map<String, int> _activeDownloadsSummary() => {
        'gallery': _galleryDownloadService.activeDownloadCount,
        'archive': _archiveDownloadService.activeDownloadCount,
      };

  Map<String, dynamic> _analyzeAttachedSqliteBackup(String backupPath) {
    _attachRestoreDatabase(backupPath);
    try {
      final summary = _restoreSummary();
      return {
        'success': true,
        'dryRun': true,
        'summary': summary,
        'warnings': _restoreWarnings(summary),
        'preserved': {
          'apiToken': true,
          'pageCache': true,
        },
        'restoredSensitive': {
          'ehCookies': true,
        },
      };
    } finally {
      _detachRestoreDatabase();
    }
  }

  Future<Map<String, dynamic>> _restoreAttachedSqliteBackup(
      String backupPath) async {
    _attachRestoreDatabase(backupPath);
    var committed = false;
    try {
      final summary = _restoreSummary();
      final apiToken = db.readConfig('api_token');
      db.raw.execute('BEGIN TRANSACTION');
      for (final spec in _restoreTables) {
        _restoreTable(spec, preserveApiToken: apiToken);
      }
      final normalized = _normalizeRestoredDownloadStatuses();
      if (apiToken != null && apiToken.isNotEmpty) {
        db.writeConfig('api_token', apiToken);
      }
      db.raw.execute('COMMIT');
      committed = true;

      await _client.cookieManager.reloadFromStorage();
      final restoredSite = db.readConfig('site');
      if (restoredSite == 'EH' || restoredSite == 'EX') {
        _client.site = restoredSite!;
      } else {
        _client.site = 'EH';
      }
      _galleryDownloadService.reloadFromDatabase();
      _archiveDownloadService.reloadFromDatabase();

      return {
        'success': true,
        'dryRun': false,
        'summary': summary,
        'warnings': _restoreWarnings(summary),
        'preserved': {
          'apiToken': true,
          'pageCache': true,
        },
        'restoredSensitive': {
          'ehCookies': true,
        },
        'normalized': normalized,
        'message': 'SQLite backup restored successfully.',
      };
    } finally {
      if (!committed) {
        try {
          db.raw.execute('ROLLBACK');
        } catch (_) {}
      }
      _detachRestoreDatabase();
    }
  }

  void _attachRestoreDatabase(String backupPath) {
    final escapedPath = backupPath.replaceAll("'", "''");
    db.raw.execute("ATTACH DATABASE '$escapedPath' AS restore_src");
    try {
      db.raw.select('SELECT COUNT(*) AS count FROM restore_src.sqlite_master');
      for (final spec in _restoreTables) {
        if (!_restoreTableExists(spec.table)) {
          throw StateError('Backup is missing required table: ${spec.table}');
        }
      }
    } catch (_) {
      _detachRestoreDatabase();
      rethrow;
    }
  }

  void _detachRestoreDatabase() {
    try {
      db.raw.execute('DETACH DATABASE restore_src');
    } catch (_) {}
  }

  Map<String, int> _restoreSummary() {
    final summary = <String, int>{};
    for (final spec in _restoreTables) {
      final row = db.raw
          .select('SELECT COUNT(*) AS count FROM restore_src.${spec.table}')
          .first;
      summary[spec.summaryKey] = (row['count'] as num?)?.toInt() ?? 0;
    }
    return summary;
  }

  List<String> _restoreWarnings(Map<String, int> summary) {
    final warnings = <String>[
      'Current API token will be preserved.',
      'EH login cookies will be restored from the backup.',
      'Page cache will not be restored.',
      'Downloading tasks in the backup will be changed to paused.',
    ];
    if ((summary['galleryDownloads'] ?? 0) == 0 &&
        (summary['archiveDownloads'] ?? 0) == 0) {
      warnings.add('Backup does not contain download tasks.');
    }
    return warnings;
  }

  bool _restoreTableExists(String table) {
    final row = db.raw.select(
      'SELECT COUNT(*) AS count FROM restore_src.sqlite_master WHERE type = ? AND name = ?',
      ['table', table],
    ).first;
    return ((row['count'] as num?)?.toInt() ?? 0) > 0;
  }

  List<String> _tableColumns(String database, String table) {
    return db.raw
        .select('SELECT name FROM $database.pragma_table_info(?)', [table])
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  void _restoreTable(_RestoreTableSpec spec,
      {required String? preserveApiToken}) {
    final sourceColumns = _tableColumns('restore_src', spec.table).toSet();
    final targetColumns = _tableColumns('main', spec.table);
    final columns = targetColumns
        .where((column) => sourceColumns.contains(column))
        .toList();
    if (columns.isEmpty) {
      throw StateError('Backup table ${spec.table} has no compatible columns.');
    }
    final columnSql = columns.map(_quoteIdentifier).join(', ');
    final sourceColumnSql = columns.map(_quoteIdentifier).join(', ');
    db.raw.execute('DELETE FROM ${_quoteIdentifier(spec.table)}');
    if (spec.table == 'config') {
      db.raw.execute(
        'INSERT INTO ${_quoteIdentifier(spec.table)} ($columnSql) '
        'SELECT $sourceColumnSql FROM restore_src.${_quoteIdentifier(spec.table)} '
        "WHERE key != 'api_token'",
      );
      if (preserveApiToken != null && preserveApiToken.isNotEmpty) {
        db.writeConfig('api_token', preserveApiToken);
      }
      return;
    }
    db.raw.execute(
      'INSERT INTO ${_quoteIdentifier(spec.table)} ($columnSql) '
      'SELECT $sourceColumnSql FROM restore_src.${_quoteIdentifier(spec.table)}',
    );
  }

  Map<String, int> _normalizeRestoredDownloadStatuses() {
    db.raw.execute(
      'UPDATE gallery_download SET download_status = ? WHERE download_status = ?',
      [
        GalleryDownloadStatus.paused.index,
        GalleryDownloadStatus.downloading.index,
      ],
    );
    final galleryRows = db.raw.updatedRows;
    db.raw.execute(
      'UPDATE archive_download SET archive_status = ? WHERE archive_status IN (?, ?, ?, ?, ?)',
      [
        ArchiveStatus.paused.index,
        ArchiveStatus.unlocking.index,
        ArchiveStatus.parsingUrl.index,
        ArchiveStatus.downloading.index,
        ArchiveStatus.downloaded.index,
        ArchiveStatus.unpacking.index,
      ],
    );
    final archiveRows = db.raw.updatedRows;
    return {
      'galleryDownloadsPaused': galleryRows,
      'archiveDownloadsPaused': archiveRows,
    };
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  Map<String, dynamic> _runtimeInfo() {
    final appVersion = _envValue('JH_APP_VERSION')?.trim();
    final dockerTag = _envValue('JH_DOCKER_TAG')?.trim();
    final forkRevision = _envValue('JH_FORK_REVISION')?.trim();
    final effectiveTag =
        dockerTag == null || dockerTag.isEmpty ? 'local/dev' : dockerTag;
    return {
      'appVersion':
          appVersion == null || appVersion.isEmpty ? 'local/dev' : appVersion,
      'dockerTag': effectiveTag,
      'forkRevision': forkRevision == null || forkRevision.isEmpty
          ? 'local/dev'
          : forkRevision,
      'imageChannel': effectiveTag == 'local/dev'
          ? 'local/dev'
          : (effectiveTag == 'latest' ? 'latest' : 'pinned'),
    };
  }

  Map<String, dynamic> _pathStatus(
    String id,
    String path, {
    required bool writable,
  }) {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) {
        return {
          'id': id,
          'path': path,
          'status': 'warn',
          'message': 'Path does not exist',
        };
      }
      dir.listSync(followLinks: false).take(1).toList();
      if (writable && !_canWriteDirectory(dir)) {
        return {
          'id': id,
          'path': path,
          'status': 'warn',
          'message': 'Path exists but is not writable',
        };
      }
      return {
        'id': id,
        'path': path,
        'status': 'ok',
        'message': writable ? 'Readable and writable' : 'Readable',
      };
    } catch (e) {
      return {
        'id': id,
        'path': path,
        'status': 'warn',
        'message': '$e',
      };
    }
  }

  Map<String, int> _pageCacheStats() {
    final row = db.raw.select('''
      SELECT
        COUNT(*) AS count,
        COALESCE(SUM(LENGTH(content)), 0) AS content_bytes,
        COALESCE(SUM(LENGTH(headers)), 0) AS header_bytes
      FROM dio_cache
    ''').first;
    final contentBytes = (row['content_bytes'] as num?)?.toInt() ?? 0;
    final headerBytes = (row['header_bytes'] as num?)?.toInt() ?? 0;
    return {
      'count': (row['count'] as num?)?.toInt() ?? 0,
      'size': contentBytes + headerBytes,
    };
  }

  static bool _isVersionTag(String value) {
    return RegExp(r'^\d+\.\d+\.\d+-[0-9a-f]{3}$').hasMatch(value);
  }

  static int _compareVersionTags(String a, String b) {
    final pa = _parseVersionTag(a);
    final pb = _parseVersionTag(b);
    for (var i = 0; i < 3; i++) {
      final diff = pa.$1[i].compareTo(pb.$1[i]);
      if (diff != 0) return diff;
    }
    return pa.$2.compareTo(pb.$2);
  }

  static (List<int>, int) _parseVersionTag(String value) {
    final match =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)-([0-9a-f]{3})$').firstMatch(value);
    if (match == null) {
      return ([0, 0, 0], -1);
    }
    return (
      [
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ],
      int.parse(match.group(4)!, radix: 16),
    );
  }

  static String _backupTimestamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  String _directoryStatus(String path, {required bool requireWritable}) {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) return 'error';
      dir.listSync(followLinks: false).take(1).toList();
      if (requireWritable && !_canWriteDirectory(dir)) return 'error';
      return 'ok';
    } catch (_) {
      return 'error';
    }
  }

  String _directoryDetail(String path, {required bool requireWritable}) {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) return '$path does not exist';
      dir.listSync(followLinks: false).take(1).toList();
      if (requireWritable && !_canWriteDirectory(dir)) {
        return '$path exists but is not writable';
      }
      return requireWritable
          ? '$path exists and is writable'
          : '$path exists and is readable';
    } catch (e) {
      return '$path cannot be accessed: $e';
    }
  }

  String _directoryHint(String path, {required bool requireWritable}) {
    return requireWritable
        ? 'Check Docker volume mount, owner, and write permission for $path.'
        : 'Check Docker volume mount and read permission for $path.';
  }

  bool _canWriteDirectory(Directory dir) {
    final file = File(p.join(
      dir.path,
      '.jhentai-write-test-${DateTime.now().microsecondsSinceEpoch}',
    ));
    try {
      file.writeAsStringSync('ok', flush: true);
      file.deleteSync();
      return true;
    } catch (_) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  Map<String, String> _databaseCheck() {
    try {
      final row = db.raw.select('SELECT COUNT(*) AS count FROM config').first;
      final count = (row['count'] as num?)?.toInt() ?? 0;
      return {
        'status': 'ok',
        'detail': '${_config.databasePath} is readable ($count config rows)',
        'hint': 'No action needed.',
      };
    } catch (e) {
      return {
        'status': 'error',
        'detail': 'Database check failed: $e',
        'hint': 'Check data directory permission and sqlite file integrity.',
      };
    }
  }

  Map<String, dynamic> _logsSummary() {
    try {
      final logs = _logFiles();
      final totalSize = logs.fold<int>(0, (sum, file) {
        try {
          return sum + file.statSync().size;
        } catch (_) {
          return sum;
        }
      });
      DateTime? latest;
      for (final file in logs) {
        try {
          final modified = file.statSync().modified;
          if (latest == null || modified.isAfter(latest)) latest = modified;
        } catch (_) {}
      }
      return {
        'status': 'ok',
        'count': logs.length,
        'totalSize': totalSize,
        'latestModified': latest?.toIso8601String(),
        'detail': logs.isEmpty
            ? 'No log files found'
            : '${logs.length} log files, $totalSize bytes',
        'hint': 'Use the advanced settings log viewer when troubleshooting.',
      };
    } catch (e) {
      return {
        'status': 'warn',
        'count': 0,
        'totalSize': 0,
        'latestModified': null,
        'detail': 'Log summary failed: $e',
        'hint': 'Check log directory permission.',
      };
    }
  }

  Future<Response> _getPageCache(Request request) async {
    final stats = _pageCacheStats();
    return Response.ok(
      jsonEncode({
        'count': stats['count'] ?? 0,
        'size': stats['size'] ?? 0,
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
    final configs = _exportAppConfigs(now: now);

    return Response.ok(
      const JsonEncoder.withIndent('  ').convert(configs),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition':
            'attachment; filename="JHenTaiConfig-${_formatExportTimestamp(now)}.json"',
      },
    );
  }

  List<Map<String, dynamic>> _exportAppConfigs({DateTime? now}) {
    final time = now ?? DateTime.now();
    final ctime = time.toUtc().millisecondsSinceEpoch;
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

    return configs;
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

    final dryRun = request.url.queryParameters['dryRun'] == 'true';
    late Map<String, int> imported;
    late String source;
    late _ImportSummary summary;
    try {
      if (body is Map &&
          body['format'] == 'jhentai-web-export-v1' &&
          body['sections'] is Map) {
        final sections = Map<String, dynamic>.from(body['sections']);
        summary = _analyzeWebExportSections(sections);
        source = 'web';
        if (!dryRun) {
          db.raw.execute('BEGIN TRANSACTION');
          imported = _importWebExportSections(sections);
          db.raw.execute('COMMIT');
        }
      } else if (body is List) {
        summary = _analyzeAppCloudConfigs(body);
        source = 'app';
        if (!dryRun) {
          db.raw.execute('BEGIN TRANSACTION');
          imported = _importAppCloudConfigs(body);
          db.raw.execute('COMMIT');
        }
      } else {
        return Response.badRequest(
          body: jsonEncode({'error': 'Unsupported import format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      if (!dryRun) {
        try {
          db.raw.execute('ROLLBACK');
        } catch (_) {}
      }
      return Response.internalServerError(
        body: jsonEncode({
          'error': dryRun
              ? 'Failed to analyze data: $e'
              : 'Failed to import data: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (dryRun) {
      return Response.ok(
        jsonEncode({
          'success': true,
          'dryRun': true,
          'source': source,
          'summary': summary.toJson(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'success': true,
        'source': source,
        'imported': imported,
        'summary': summary.toJson(),
      }),
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
      'maxConcurrentGalleryDownloads':
          effectiveMaxConcurrentGalleryDownloads(_config),
      'maxConcurrentArchiveDownloads':
          effectiveMaxConcurrentArchiveDownloads(_config),
      'downloadAllGalleriesOfSamePriority':
          effectiveDownloadAllGalleriesOfSamePriority(_config),
      'galleryUpgradeReuseImages': effectiveGalleryUpgradeReuseImages(_config),
      'deleteArchiveFileAfterDownload':
          effectiveDeleteArchiveFileAfterDownload(),
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

  _ImportSummary _analyzeWebExportSections(Map<String, dynamic> sections) {
    final summary = _ImportSummary();
    final existingRules = db
        .selectAllBlockRules()
        .map((rule) => _blockRuleFingerprint(rule))
        .toSet();

    for (final row in _importRows(sections['config'])) {
      final section = summary.section('config');
      final key = _importString(row['key']);
      if (key.isEmpty || _reservedKeys.contains(key)) {
        section.skipped++;
        continue;
      }
      final subKey = _importString(row['sub_key']);
      section.importable++;
      if (_configRowExists(key, subKey)) {
        section.replacing++;
      }
    }

    for (final row in _importRows(sections['blockRules'])) {
      final section = summary.section('blockRules');
      final rule = _normalizedBlockRule(row);
      if (rule == null) {
        section.skipped++;
        continue;
      }
      final fingerprint = _blockRuleFingerprint(rule);
      if (existingRules.contains(fingerprint)) {
        section.skipped++;
        continue;
      }
      existingRules.add(fingerprint);
      section.importable++;
    }

    for (final row in _importRows(sections['history'])) {
      final section = summary.section('history');
      final gid = _importInt(row['gid']);
      if (gid == null) {
        section.skipped++;
        continue;
      }
      section.importable++;
      if (_rowExists('history', 'gid', gid)) {
        section.replacing++;
      }
    }

    for (final row in _importRows(sections['searchHistory'])) {
      final section = summary.section('searchHistory');
      final keyword = _importString(row['keyword']).trim();
      if (keyword.isEmpty) {
        section.skipped++;
        continue;
      }
      section.importable++;
      if (_rowExists('search_history', 'keyword', keyword)) {
        section.replacing++;
      }
    }

    for (final row in _importRows(sections['quickSearch'])) {
      final section = summary.section('quickSearch');
      final name = _importString(row['name']).trim();
      if (name.isEmpty) {
        section.skipped++;
        continue;
      }
      section.importable++;
      if (_rowExists('quick_search', 'name', name)) {
        section.replacing++;
      }
    }

    return summary;
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

  _ImportSummary _analyzeAppCloudConfigs(List<dynamic> configs) {
    final summary = _ImportSummary();
    final existingRules = db
        .selectAllBlockRules()
        .map((rule) => _blockRuleFingerprint(rule))
        .toSet();

    for (final item in configs.whereType<Map>()) {
      final config = Map<String, dynamic>.from(item);
      final type = _importInt(config['type']);
      final raw = _importString(config['config']);
      if (type == null || raw.isEmpty) {
        summary.section('config').skipped++;
        continue;
      }
      final decoded = jsonDecode(raw);
      switch (type) {
        case 1:
          for (final row in _importRows(decoded)) {
            final section = summary.section('readProgress');
            final subKey = _importString(row['subConfigKey']).trim();
            final value = _importString(row['value']).trim();
            if (subKey.isEmpty || value.isEmpty) {
              section.skipped++;
              continue;
            }
            final key = 'read_progress_$subKey';
            section.importable++;
            if (_configRowExists(key, '')) {
              section.replacing++;
            }
          }
        case 2:
          final section = summary.section('quickSearch');
          if (decoded is! Map) {
            section.skipped++;
            continue;
          }
          for (final entry in decoded.entries) {
            final name = entry.key.toString().trim();
            if (name.isEmpty) {
              section.skipped++;
              continue;
            }
            section.importable++;
            if (_rowExists('quick_search', 'name', name)) {
              section.replacing++;
            }
          }
        case 3:
          for (final row in _importRows(decoded)) {
            final section = summary.section('blockRules');
            final rule = _convertAppBlockRule(row);
            if (rule == null) {
              section.skipped++;
              continue;
            }
            final fingerprint = _blockRuleFingerprint(rule);
            if (existingRules.contains(fingerprint)) {
              section.skipped++;
              continue;
            }
            existingRules.add(fingerprint);
            section.importable++;
          }
        case 4:
          final section = summary.section('searchHistory');
          if (decoded is! List) {
            section.skipped++;
            continue;
          }
          for (final item in decoded) {
            final keyword = _importString(item).trim();
            if (keyword.isEmpty) {
              section.skipped++;
              continue;
            }
            section.importable++;
            if (_rowExists('search_history', 'keyword', keyword)) {
              section.replacing++;
            }
          }
        case 5:
          for (final row in _importRows(decoded)) {
            final section = summary.section('history');
            final gid = _importInt(row['gid']);
            final jsonBodyRaw = row['jsonBody'];
            if (gid == null || jsonBodyRaw is! String || jsonBodyRaw.isEmpty) {
              section.skipped++;
              continue;
            }
            final body = jsonDecode(jsonBodyRaw);
            if (body is! Map) {
              section.skipped++;
              continue;
            }
            section.importable++;
            if (_rowExists('history', 'gid', gid)) {
              section.replacing++;
            }
          }
        default:
          summary.section('config').skipped++;
      }
    }

    return summary;
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
    final rule = _normalizedBlockRule(row);
    if (rule == null) {
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

  Map<String, dynamic>? _normalizedBlockRule(Map<String, dynamic> row) {
    final rule = {
      'group_id': _importString(row['group_id'] ?? row['groupId']),
      'target': _importString(row['target'], fallback: 'gallery'),
      'attribute': _importString(row['attribute'], fallback: 'title'),
      'pattern': _importString(row['pattern'], fallback: 'like'),
      'expression': _importString(row['expression']),
    };
    if ((rule['expression'] as String).isEmpty) {
      return null;
    }
    return rule;
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

  bool _configRowExists(String key, String subKey) {
    return db.raw.select(
      'SELECT 1 FROM config WHERE key = ? AND sub_key = ? LIMIT 1',
      [key, subKey],
    ).isNotEmpty;
  }

  bool _rowExists(String table, String column, Object value) {
    return db.raw.select(
      'SELECT 1 FROM $table WHERE $column = ? LIMIT 1',
      [value],
    ).isNotEmpty;
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
