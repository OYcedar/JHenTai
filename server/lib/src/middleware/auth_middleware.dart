import 'dart:convert';
import 'dart:io';
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
      final masked = '${_token.substring(0, 8)}...${_token.substring(_token.length - 4)}';
      log.info('API token loaded: $masked');
    } else {
      _token = _generateToken();
      db.writeConfig(_apiTokenConfigKey, _token);
      log.info('========================================');
      log.info('Generated new API token: $_token');
      log.info('Use this token in the web UI setup page.');
      log.info('========================================');
    }
    await _printTokenToConsole(_token);
  }

  /// Logger output can be noisy or reordered in Docker; duplicate to raw stdout/stderr and flush.
  Future<void> _printTokenToConsole(String token) async {
    const line = '================================================================================';
    final buf = StringBuffer()
      ..writeln(line)
      ..writeln('JHenTai Web UI API token (copy entire line below, then paste in /web/setup):')
      ..writeln(token)
      ..writeln(line)
      ..writeln('[JHenTai] API token (one-line): $token');
    final text = buf.toString();
    stderr.write(text);
    stdout.write(text);
    await stderr.flush();
    await stdout.flush();
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
          if (_isImageRelatedPath(path)) {
            final q = request.url.queryParameters['token'];
            final qState = q == null
                ? 'absent'
                : (q.isEmpty ? 'empty' : (q == _token ? 'valid' : 'invalid'));
            log.warning(
              '[auth] $path rejected: need ?token=<api_token> matching server (queryToken=$qState) '
              'or Authorization: Bearer <api_token>',
            );
          }
          return Response.unauthorized(
            jsonEncode({'error': 'Missing or invalid Authorization header'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final providedToken = authHeader.substring(7);
        if (providedToken != _token) {
          if (_isImageRelatedPath(path)) {
            log.warning('[auth] image/proxy request forbidden (Bearer token mismatch). path=$path');
          }
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
    if (path.startsWith('ws/') ||
        path.startsWith('api/proxy/image') ||
        path.startsWith('api/image/')) {
      final qToken = request.url.queryParameters['token'];
      return qToken == _token;
    }
    return false;
  }

  bool _isImageRelatedPath(String path) {
    return path.startsWith('api/proxy/image') || path.startsWith('api/image/');
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
