import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../core/database.dart';

class SettingRoutes {
  final ServerConfig _config;

  SettingRoutes(this._config);

  Router get router {
    final router = Router();

    router.get('/', _getSettings);
    router.put('/', _updateSettings);
    router.get('/<key>', _getSetting);
    router.put('/<key>', _updateSetting);
    router.delete('/<key>', _deleteSetting);

    return router;
  }

  Future<Response> _getSettings(Request request) async {
    final settingKeys = [
      'EHSetting', 'networkSetting', 'downloadSetting',
      'userSetting', 'preferenceSetting', 'styleSetting',
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
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    for (final entry in body.entries) {
      final value = entry.value is String ? entry.value : jsonEncode(entry.value);
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
      return Response.notFound(jsonEncode({'error': 'Setting not found'}));
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
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
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
    db.deleteConfig(key);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
