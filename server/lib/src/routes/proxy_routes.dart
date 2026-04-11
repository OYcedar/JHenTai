import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/log.dart';
import '../debug_flags.dart';
import '../network/eh_client.dart';

const _allowedHosts = {
  'e-hentai.org',
  'exhentai.org',
  'forums.e-hentai.org',
  'upld.e-hentai.org',
  'api.e-hentai.org',
  'ul.ehgt.org',
  'ehgt.org',
  'gt.ehgt.org',
};

bool _isAllowedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return _allowedHosts.contains(host) ||
      host.endsWith('.e-hentai.org') ||
      host.endsWith('.exhentai.org') ||
      host.endsWith('.ehgt.org') ||
      host.endsWith('.hath.network');
}

String _urlPreview(String url, {int max = 140}) {
  if (url.length <= max) return url;
  return '${url.substring(0, max)}…(len=${url.length})';
}

class ProxyRoutes {
  final EHClient _client;

  ProxyRoutes(this._client);

  Router get router {
    final router = Router();

    router.get('/get', _proxyGet);
    router.post('/post', _proxyPost);
    router.get('/image', _proxyImage);
    router.post('/image', _proxyImagePost);

    return router;
  }

  Future<Response> _proxyGet(Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing url parameter'}));
    }

    if (!_isAllowedUrl(url)) {
      return Response.forbidden(jsonEncode({'error': 'URL host not in allowlist'}));
    }

    final queryParams = Map<String, dynamic>.from(request.url.queryParameters)..remove('url');

    try {
      final result = await _client.proxyGet(url, queryParams: queryParams.isNotEmpty ? queryParams : null);
      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Proxy request failed: $e'}),
      );
    }
  }

  Future<Response> _proxyPost(Request request) async {
    Map<String, dynamic> body;
    try {
      final bodyStr = await request.readAsString();
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing url'}));
    }

    if (!_isAllowedUrl(url)) {
      return Response.forbidden(jsonEncode({'error': 'URL host not in allowlist'}));
    }

    final data = body['data'];
    final queryParams = body['queryParams'] as Map<String, dynamic>?;
    final contentType = body['contentType'] as String?;

    try {
      final result = await _client.proxyPost(
        url,
        data: data,
        queryParams: queryParams,
        contentType: contentType,
      );
      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Proxy request failed: $e'}),
      );
    }
  }

  /// Proxies an image URL through the server to bypass CORS for the frontend.
  Future<Response> _proxyImage(Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      log.warning('[proxy/image] GET missing url query');
      return Response.badRequest(body: 'Missing url parameter');
    }

    if (!_isAllowedUrl(url)) {
      log.warning('[proxy/image] GET host blocked: ${_urlPreview(url)}');
      return Response.forbidden('URL host not in allowlist');
    }

    final sw = Stopwatch()..start();
    try {
      final imageBytes = await _client.downloadBytes(url);
      sw.stop();
      if (jhImageProxyDebugEnabled()) {
        log.info(
          '[proxy/image] GET ok bytes=${imageBytes.length} ${sw.elapsedMilliseconds}ms '
          '${_urlPreview(url)}',
        );
      }
      final contentType = _guessImageContentType(url);
      return Response.ok(
        imageBytes,
        headers: {
          'Content-Type': contentType,
          'Cache-Control': 'public, max-age=86400',
        },
      );
    } catch (e, st) {
      sw.stop();
      log.warning(
        '[proxy/image] GET failed ${sw.elapsedMilliseconds}ms ${_urlPreview(url)}: $e\n$st',
      );
      return Response.internalServerError(body: 'Failed to proxy image: $e');
    }
  }

  /// Same as [_proxyImage] but reads the target URL from JSON body so long CDN URLs are not in the query string
  /// (avoids reverse-proxy `414` / small header buffers, e.g. Unraid + Nginx).
  Future<Response> _proxyImagePost(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      log.warning('[proxy/image] POST invalid JSON: $e');
      return Response.badRequest(body: 'Invalid JSON body');
    }

    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      log.warning('[proxy/image] POST missing url in body');
      return Response.badRequest(body: 'Missing url');
    }

    if (!_isAllowedUrl(url)) {
      log.warning('[proxy/image] POST host blocked: ${_urlPreview(url)}');
      return Response.forbidden('URL host not in allowlist');
    }

    final sw = Stopwatch()..start();
    try {
      final imageBytes = await _client.downloadBytes(url);
      sw.stop();
      if (jhImageProxyDebugEnabled()) {
        log.info(
          '[proxy/image] POST ok bytes=${imageBytes.length} ${sw.elapsedMilliseconds}ms '
          '${_urlPreview(url)}',
        );
      }
      final contentType = _guessImageContentType(url);
      return Response.ok(
        imageBytes,
        headers: {
          'Content-Type': contentType,
          'Cache-Control': 'public, max-age=86400',
        },
      );
    } catch (e, st) {
      sw.stop();
      log.warning(
        '[proxy/image] POST failed ${sw.elapsedMilliseconds}ms ${_urlPreview(url)}: $e\n$st',
      );
      return Response.internalServerError(body: 'Failed to proxy image: $e');
    }
  }

  String _guessImageContentType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'image/png';
    if (lower.contains('.gif')) return 'image/gif';
    if (lower.contains('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
