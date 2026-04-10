import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';

class SearchHistoryRoutes {
  Router get router {
    final router = Router();

    router.get('/list', _list);
    router.post('/record', _record);
    router.delete('/clear', _clear);
    router.delete('/<keyword>', _delete);

    return router;
  }

  Future<Response> _list(Request request) async {
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
    final items = db.selectSearchHistory(limit: limit);
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

    final keyword = body['keyword'] as String?;
    if (keyword == null || keyword.trim().isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'keyword is required'}));
    }

    db.recordSearch(keyword.trim());
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _clear(Request request) async {
    db.clearSearchHistory();
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _delete(Request request, String keyword) async {
    db.deleteSearchHistory(Uri.decodeComponent(keyword));
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
