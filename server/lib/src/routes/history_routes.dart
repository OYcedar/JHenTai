import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';

class HistoryRoutes {
  Router get router {
    final router = Router();

    router.get('/list', _list);
    router.post('/record', _record);
    router.delete('/clear', _clear);
    router.delete('/<gid>', _delete);

    return router;
  }

  Future<Response> _list(Request request) async {
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50;
    final offset = int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
    final items = db.selectHistory(limit: limit, offset: offset);
    return Response.ok(
      jsonEncode({'items': items}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _record(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String? ?? '';
    final title = body['title'] as String? ?? '';
    final coverUrl = body['coverUrl'] as String? ?? '';
    final category = body['category'] as String? ?? '';

    if (gid == null) {
      return Response.badRequest(body: jsonEncode({'error': 'gid is required'}));
    }

    db.upsertHistory(gid, token, title, coverUrl, category);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _clear(Request request) async {
    db.clearHistory();
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _delete(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    db.deleteHistory(id);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
