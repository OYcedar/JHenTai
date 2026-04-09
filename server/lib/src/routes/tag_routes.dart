import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../service/tag_translation_service.dart';

class TagRoutes {
  final TagTranslationService _service;

  TagRoutes(this._service);

  Router get router {
    final router = Router();

    router.post('/refresh', _refresh);
    router.get('/status', _status);
    router.get('/translate', _translate);
    router.post('/batch', _batch);
    router.get('/search', _search);

    return router;
  }

  Future<Response> _refresh(Request request) async {
    final result = await _service.refresh();
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _status(Request request) async {
    return Response.ok(
      jsonEncode(_service.getStatus()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _translate(Request request) async {
    final namespace = request.url.queryParameters['namespace'] ?? '';
    final key = request.url.queryParameters['key'] ?? '';
    if (namespace.isEmpty || key.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'namespace and key are required'}));
    }
    final result = db.getTagTranslation(namespace, key);
    return Response.ok(
      jsonEncode(result ?? {'namespace': namespace, 'key': key, 'tag_name': key}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _batch(Request request) async {
    List<dynamic> tags;
    try {
      final body = jsonDecode(await request.readAsString());
      tags = body['tags'] as List? ?? [];
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON, expected {tags: [{namespace, key}, ...]}'}));
    }

    final input = tags.map((t) => <String, String>{
      'namespace': (t['namespace'] ?? '').toString(),
      'key': (t['key'] ?? '').toString(),
    }).toList();

    final results = db.batchGetTagTranslations(input);

    final resultMap = <String, String>{};
    for (final r in results) {
      resultMap['${r['namespace']}:${r['key']}'] = r['tag_name'] as String? ?? r['key'] as String;
    }

    return Response.ok(
      jsonEncode({'translations': resultMap}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _search(Request request) async {
    final query = request.url.queryParameters['q'] ?? '';
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
    if (query.isEmpty) {
      return Response.ok(jsonEncode({'results': []}), headers: {'Content-Type': 'application/json'});
    }
    final results = db.searchTagTranslations(query, limit: limit);
    return Response.ok(
      jsonEncode({'results': results}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
