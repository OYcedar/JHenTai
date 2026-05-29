import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../network/eh_client.dart';
import '../service/tag_translation_service.dart';

class TagRoutes {
  final TagTranslationService _service;
  final EHClient? _ehClient;

  TagRoutes(this._service, [this._ehClient]);

  Router get router {
    final router = Router();

    router.post('/refresh', _refresh);
    router.get('/status', _status);
    router.get('/translate', _translate);
    router.post('/batch', _batch);
    router.get('/search', _search);
    router.post('/vote', _vote);
    router.post('/add', _add);

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
      return Response.badRequest(
          body: jsonEncode({'error': 'namespace and key are required'}));
    }
    final result = db.getTagTranslation(namespace, key);
    return Response.ok(
      jsonEncode(
          result ?? {'namespace': namespace, 'key': key, 'tag_name': key}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _batch(Request request) async {
    List<dynamic> tags;
    try {
      final body = jsonDecode(await request.readAsString());
      tags = body['tags'] as List? ?? [];
    } catch (_) {
      return Response.badRequest(
          body: jsonEncode({
        'error': 'Invalid JSON, expected {tags: [{namespace, key}, ...]}'
      }));
    }

    final input = tags
        .map((t) => <String, String>{
              'namespace': (t['namespace'] ?? '').toString(),
              'key': (t['key'] ?? '').toString(),
            })
        .toList();

    final results = db.batchGetTagTranslations(input);

    final resultMap = <String, String>{};
    for (final r in results) {
      resultMap['${r['namespace']}:${r['key']}'] =
          r['tag_name'] as String? ?? r['key'] as String;
    }

    return Response.ok(
      jsonEncode({'translations': resultMap}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _search(Request request) async {
    final query = request.url.queryParameters['q'] ?? '';
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
    if (query.isEmpty) {
      return Response.ok(jsonEncode({'results': []}),
          headers: {'Content-Type': 'application/json'});
    }
    final results = db.searchTagTranslations(query, limit: limit);
    final ehClient = _ehClient;
    if (results.length < limit && ehClient != null) {
      final onlineLimit = limit - results.length;
      try {
        final online = await ehClient
            .fetchTagSuggestions(_lastTagSearchPart(query), limit: onlineLimit);
        final seen = results
            .map((r) => '${r['namespace']}:${r['key']}'.toLowerCase())
            .toSet();
        for (final row in online) {
          final id = '${row['namespace']}:${row['key']}'.toLowerCase();
          if (seen.add(id)) {
            results.add(row);
          }
          if (results.length >= limit) {
            break;
          }
        }
      } catch (_) {
        // Online EH suggestions are best-effort; local translation matches remain useful.
      }
    }
    return Response.ok(
      jsonEncode({'results': results}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  String _lastTagSearchPart(String query) {
    final parts = query.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? query.trim() : parts.last;
  }

  Future<Response> _vote(Request request) async {
    if (_ehClient == null) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'EHClient not available'}));
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid JSON'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final apiuid = body['apiuid'] as int?;
    final apikey = body['apikey'] as String?;
    final namespace = body['namespace'] as String?;
    final tag = body['tag'] as String?;
    final vote = body['vote'] as int?;

    if (gid == null ||
        token == null ||
        apiuid == null ||
        apikey == null ||
        namespace == null ||
        tag == null ||
        vote == null) {
      return Response.badRequest(
          body: jsonEncode({
            'error':
                'Missing required fields: gid, token, apiuid, apikey, namespace, tag, vote'
          }),
          headers: {'Content-Type': 'application/json'});
    }

    final result = await _ehClient!.voteTag(
      apiuid: apiuid,
      apikey: apikey,
      gid: gid,
      token: token,
      namespace: namespace,
      tag: tag,
      vote: vote,
    );

    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _add(Request request) async {
    if (_ehClient == null) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'EHClient not available'}));
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid JSON'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final apiuid = body['apiuid'] as int?;
    final apikey = body['apikey'] as String?;
    final tags = body['tags'] as String?;

    if (gid == null ||
        token == null ||
        apiuid == null ||
        apikey == null ||
        tags == null ||
        tags.trim().isEmpty) {
      return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required fields: gid, token, apiuid, apikey, tags'
          }),
          headers: {'Content-Type': 'application/json'});
    }

    final result = await _ehClient!.addTags(
      apiuid: apiuid,
      apikey: apikey,
      gid: gid,
      token: token,
      tags: tags.trim(),
    );

    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
