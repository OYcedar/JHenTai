import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';

class SettingRoutes {
  final ServerConfig _config;
  static const _reservedKeys = {'api_token', 'eh_cookies'};

  SettingRoutes(this._config);

  Router get router {
    final router = Router();

    router.get('/', _getSettings);
    router.put('/', _updateSettings);
    router.get('/logs', _listLogs);
    router.get('/logs/<name>', _readLog);
    router.delete('/logs', _clearLogs);
    router.get('/<key>', _getSetting);
    router.put('/<key>', _updateSetting);
    router.delete('/<key>', _deleteSetting);

    return router;
  }

  Directory get _logDir => Directory(_config.logDir);

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
    };

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
}
