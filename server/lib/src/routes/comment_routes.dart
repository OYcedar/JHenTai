import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

class CommentRoutes {
  final EHClient _client;

  CommentRoutes(this._client);

  Router get router {
    final router = Router();

    router.post('/post', _postComment);
    router.post('/vote', _voteComment);

    return router;
  }

  Future<Response> _postComment(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final comment = body['comment'] as String?;

    if (gid == null || token == null || comment == null || comment.trim().isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'gid, token, and comment are required'}));
    }

    final result = await _client.postComment(gid, token, comment);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _voteComment(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final apiuid = body['apiuid'] as int?;
    final apikey = body['apikey'] as String?;
    final commentId = body['commentId'] as int?;
    final vote = body['vote'] as int?;

    if (gid == null || token == null || apiuid == null || apikey == null || commentId == null || vote == null) {
      return Response.badRequest(body: jsonEncode({'error': 'gid, token, apiuid, apikey, commentId, and vote are required'}));
    }

    final result = await _client.voteComment(apiuid, apikey, gid, token, commentId, vote);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
