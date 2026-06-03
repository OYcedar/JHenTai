import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../service/archive_bot_service.dart';

class ArchiveBotRoutes {
  ArchiveBotRoutes(this._service);

  final ArchiveBotService _service;

  Router get router {
    final router = Router();

    router.get('/settings', _settings);
    router.put('/settings', _updateSettings);
    router.post('/balance', _balance);
    router.post('/check-in', _checkIn);
    router.post('/resolve', _resolve);

    return router;
  }

  Response _json(dynamic data, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _guard(Future<Map<String, dynamic>> Function() run) async {
    try {
      return _json(await run());
    } on ArchiveBotException catch (e) {
      return _json({'success': false, 'error': e.message}, status: 400);
    } catch (e) {
      return _json({'success': false, 'error': '$e'}, status: 400);
    }
  }

  Response _settings(Request request) {
    return _json({'settings': _service.settings().toPublicJson()});
  }

  Future<Response> _updateSettings(Request request) {
    return _guard(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final settings = _service.saveSettings(Map<String, dynamic>.from(body));
      return {'success': true, 'settings': settings.toPublicJson()};
    });
  }

  Future<Response> _balance(Request request) {
    return _guard(_service.requestBalance);
  }

  Future<Response> _checkIn(Request request) {
    return _guard(_service.requestCheckIn);
  }

  Future<Response> _resolve(Request request) {
    return _guard(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final gid = (body['gid'] as num?)?.toInt();
      final token = body['token']?.toString() ?? '';
      if (gid == null || token.isEmpty) {
        throw const ArchiveBotException('Missing gid or token');
      }
      return _service.requestResolve(
        gid: gid,
        token: token,
        reParse: body['reParse'] != false,
      );
    });
  }
}
