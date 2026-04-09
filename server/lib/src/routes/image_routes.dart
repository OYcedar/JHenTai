import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';

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

    return _serveFile(filePath);
  }

  Future<Response> _serveGalleryImage(Request request, String gid, String filename) async {
    final filePath = p.join(_config.downloadDir, 'gallery', gid, filename);
    return _serveFile(filePath);
  }

  Future<Response> _serveArchiveImage(Request request, String gid, String filename) async {
    final filePath = p.join(_config.downloadDir, 'archive', gid, filename);
    return _serveFile(filePath);
  }

  Response _serveFile(String filePath) {
    if (!_isAllowedPath(filePath)) {
      return Response.forbidden('Access denied');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      return Response.notFound('File not found');
    }

    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final length = file.lengthSync();

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
    if (resolved.startsWith(p.canonicalize(_config.downloadDir))) return true;
    if (resolved.startsWith(p.canonicalize(_config.localGalleryDir))) return true;
    for (final extra in _config.extraScanPaths) {
      if (resolved.startsWith(p.canonicalize(extra))) return true;
    }
    return false;
  }
}
