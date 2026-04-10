import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';

class QuickSearchRoutes {
  Router get router {
    final router = Router();

    router.get('/list', _list);
    router.post('/save', _save);
    router.delete('/<name>', _delete);

    return router;
  }

  Future<Response> _list(Request request) async {
    final items = db.selectAllQuickSearches();
    return Response.ok(
      jsonEncode({'items': items}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _save(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final name = body['name'] as String?;
    final config = body['config'] as String?;
    final sortOrder = body['sortOrder'] as int? ?? 0;

    if (name == null || name.trim().isEmpty || config == null) {
      return Response.badRequest(body: jsonEncode({'error': 'name and config are required'}));
    }

    db.upsertQuickSearch(name.trim(), config, sortOrder: sortOrder);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _delete(Request request, String name) async {
    db.deleteQuickSearch(Uri.decodeComponent(name));
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
