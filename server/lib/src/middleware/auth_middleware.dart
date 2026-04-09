import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

import '../core/database.dart';
import '../core/log.dart';

const String _apiTokenConfigKey = 'api_token';

class AuthMiddleware {
  late String _token;

  Future<void> init() async {
    final stored = db.readConfig(_apiTokenConfigKey);
    if (stored != null && stored.isNotEmpty) {
      _token = stored;
    } else {
      _token = _generateToken();
      db.writeConfig(_apiTokenConfigKey, _token);
      log.info('========================================');
      log.info('Generated new API token: $_token');
      log.info('Use this token in the web UI setup page.');
      log.info('========================================');
    }
  }

  String get token => _token;

  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.url.path;

        if (_isExempt(request, path)) {
          return innerHandler(request);
        }

        final authHeader = request.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response.unauthorized(
            jsonEncode({'error': 'Missing or invalid Authorization header'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final providedToken = authHeader.substring(7);
        if (providedToken != _token) {
          return Response.forbidden(
            jsonEncode({'error': 'Invalid API token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        return innerHandler(request);
      };
    };
  }

  bool _isExempt(Request request, String path) {
    if (!path.startsWith('api/') && !path.startsWith('ws/')) {
      return true;
    }
    if (path == 'api/health') return true;
    if (path == 'api/auth/token/verify') return true;
    return false;
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
