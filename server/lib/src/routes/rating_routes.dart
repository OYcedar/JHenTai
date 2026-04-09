import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

class RatingRoutes {
  final EHClient _client;

  RatingRoutes(this._client);

  Router get router {
    final router = Router();

    router.post('/rate', _rateGallery);

    return router;
  }

  Future<Response> _rateGallery(Request request) async {
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
    final rating = (body['rating'] as num?)?.toDouble();

    if (gid == null || token == null || apiuid == null || apikey == null || rating == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'gid, token, apiuid, apikey, and rating are required'}),
      );
    }

    final result = await _client.rateGallery(gid, token, apiuid, apikey, rating);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
