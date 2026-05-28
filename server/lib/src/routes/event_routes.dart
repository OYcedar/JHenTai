import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

class EventRoutes {
  final EHClient _ehClient;

  EventRoutes(this._ehClient);

  Router get router {
    final router = Router();
    router.get('/check', _check);
    return router;
  }

  Future<Response> _check(Request request) async {
    final result = await _ehClient.checkEvents();
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
