import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

class AuthRoutes {
  final EHClient _client;

  AuthRoutes(this._client);

  Router get router {
    final router = Router();

    router.post('/login', _login);
    router.post('/logout', _logout);
    router.get('/status', _status);
    router.post('/cookies', _setCookies);
    router.get('/cookies', _getCookies);
    router.put('/site', _setSite);

    return router;
  }

  Future<Response> _login(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final userName = body['userName'] as String?;
    final passWord = body['passWord'] as String?;

    if (userName == null || passWord == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing credentials'}));
    }

    final result = await _client.login(userName, passWord);
    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _logout(Request request) async {
    await _client.logout();
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _status(Request request) async {
    return Response.ok(
      jsonEncode({
        'loggedIn': _client.cookieManager.hasLoggedIn,
        'site': _client.site,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _setCookies(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final cookieStr = body['cookies'] as String?;

    if (cookieStr == null || cookieStr.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing cookies'}));
    }

    final cookies = cookieStr.split(';').map((pair) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2) {
        return Cookie(parts[0].trim(), parts.sublist(1).join('=').trim());
      }
      return null;
    }).whereType<Cookie>().toList();

    await _client.cookieManager.storeCookies(cookies);

    return Response.ok(
      jsonEncode({
        'success': true,
        'loggedIn': _client.cookieManager.hasLoggedIn,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getCookies(Request request) async {
    final cookies = _client.cookieManager.cookies
        .map((c) => {'name': c.name, 'value': c.value})
        .toList();
    return Response.ok(
      jsonEncode({'cookies': cookies}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _setSite(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final site = body['site'] as String?;

    if (site != 'EH' && site != 'EX') {
      return Response.badRequest(body: jsonEncode({'error': 'site must be EH or EX'}));
    }

    _client.site = site!;
    return Response.ok(
      jsonEncode({'success': true, 'site': site}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
