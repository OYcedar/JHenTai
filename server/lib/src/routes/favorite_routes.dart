import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

class FavoriteRoutes {
  final EHClient _client;

  FavoriteRoutes(this._client);

  Router get router {
    final router = Router();

    router.post('/add', _addFavorite);
    router.post('/remove', _removeFavorite);
    router.get('/names', _favoriteNames);
    router.get('/popup', _favoritePopup);

    return router;
  }

  Future<Response> _addFavorite(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final favcat = body['favcat'] as int? ?? 0;
    final favnote = body['favnote'] as String? ?? '';

    if (gid == null || token == null) {
      return Response.badRequest(body: jsonEncode({'error': 'gid and token are required'}));
    }

    final result = await _client.addFavorite(gid, token, favcat: favcat, favnote: favnote);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _favoriteNames(Request request) async {
    final folders = await _client.fetchFavoriteFolders();
    return Response.ok(
      jsonEncode({
        'names': folders.names,
        'counts': folders.counts,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _favoritePopup(Request request) async {
    final gid = int.tryParse(request.url.queryParameters['gid'] ?? '');
    final token = request.url.queryParameters['token'];
    if (gid == null || token == null || token.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'gid and token are required'}));
    }
    final note = await _client.fetchFavoritePopupNote(gid, token);
    return Response.ok(
      jsonEncode({'note': note}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _removeFavorite(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;

    if (gid == null || token == null) {
      return Response.badRequest(body: jsonEncode({'error': 'gid and token are required'}));
    }

    final result = await _client.removeFavorite(gid, token);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
