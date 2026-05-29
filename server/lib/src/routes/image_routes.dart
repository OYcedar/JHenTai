import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../console_diag.dart';
import '../core/log.dart';
import '../debug_flags.dart';
import '../service/local_gallery_runtime_settings.dart';

class ImageRoutes {
  final ServerConfig _config;

  ImageRoutes(this._config);

  Router get router {
    final router = Router();
    router.get('/file', _serveImage);
    router.get('/gallery/<gid>/<filename>', _serveGalleryImage);
    router.get('/archive/<gid>/<filename>', _serveArchiveImage);
    return router;
  }

  Future<Response> _serveImage(Request request) async {
    final filePath = request.url.queryParameters['path'];
    if (filePath == null || filePath.isEmpty) {
      return Response.notFound('Missing path');
    }

    return _serveFile(filePath, request);
  }

  Future<Response> _serveGalleryImage(
      Request request, String gid, String filename) async {
    final filePath = p.join(_config.downloadDir, 'gallery', gid, filename);
    return _serveFile(filePath, request);
  }

  Future<Response> _serveArchiveImage(
      Request request, String gid, String filename) async {
    final filePath = p.join(_config.downloadDir, 'archive', gid, filename);
    return _serveFile(filePath, request);
  }

  Response _serveFile(String filePath, Request request) {
    if (!_isAllowedPath(filePath)) {
      final m = '[api/image] forbidden path not under allowed roots: $filePath';
      log.warning(m);
      jhStderrLine(m);
      return Response.forbidden('Access denied');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      final m = '[api/image] file not found: $filePath';
      log.warning(m);
      jhStderrLine(m);
      return Response.notFound('File not found');
    }

    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final length = file.lengthSync();
    final maxBytes =
        int.tryParse(request.url.queryParameters['maxBytes'] ?? '');
    if (maxBytes != null && maxBytes > 0 && length > maxBytes) {
      final m =
          '[api/image] file exceeds maxBytes=$maxBytes bytes=$length: $filePath';
      log.info(m);
      jhStderrLine(m);
      return Response(413, body: 'Image exceeds maxBytes');
    }
    if (jhImageProxyDebugEnabled()) {
      final m = '[api/image] ok $filePath bytes=$length type=$mimeType';
      log.info(m);
      jhStderrLine(m);
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': length.toString(),
        'Cache-Control': 'public, max-age=86400',
      },
    );
  }

  bool _isAllowedPath(String filePath) {
    final resolved = p.canonicalize(filePath);
    final downloadDir = p.canonicalize(_config.downloadDir);
    if (resolved == downloadDir || resolved.startsWith('$downloadDir/')) {
      return true;
    }
    return isPathUnderLocalGalleryScanPath(filePath, _config);
  }
}
