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
import '../utils/archive_util.dart';

class ImageRoutes {
  final ServerConfig _config;
  late final String _downloadDirCanonical = p.canonicalize(_config.downloadDir);
  final Map<int, String> _archiveDirCache = {};
  final Map<int, String> _galleryDirCache = {};

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
    final gidNum = int.tryParse(gid);
    if (gidNum == null) return Response.notFound('Missing gid');
    final galleryDir = _resolveGalleryDir(gidNum);
    if (galleryDir == null) return Response.notFound('Gallery not found');
    final filePath = p.join(galleryDir, filename);
    return _serveFile(filePath, request);
  }

  Future<Response> _serveArchiveImage(
      Request request, String gid, String filename) async {
    final gidNum = int.tryParse(gid);
    if (gidNum == null) return Response.notFound('Missing gid');
    final archiveDir = _resolveArchiveDir(gidNum);
    if (archiveDir == null) {
      return Response.notFound('Archive not found');
    }
    final filePath = p.join(archiveDir, filename);
    return _serveFile(filePath, request);
  }

  /// 解析归档解压目录：优先缓存，再通过公共解析器兼容 Web 与 App 布局。
  String? _resolveArchiveDir(int gid) {
    final cached = _archiveDirCache[gid];
    if (cached != null && Directory(cached).existsSync()) return cached;
    final resolved = resolveArchiveDir(_config.downloadDir, gid);
    if (resolved != null) _archiveDirCache[gid] = resolved;
    return resolved;
  }

  /// 解析画廊下载目录：优先缓存，再按新格式 `<gid> - <标题>`
  /// 扫描，最后回退旧格式 `gallery/<gid>`。
  String? _resolveGalleryDir(int gid) {
    final cached = _galleryDirCache[gid];
    if (cached != null && Directory(cached).existsSync()) return cached;
    final resolved = resolveGalleryDir(_config.downloadDir, gid);
    if (resolved != null) _galleryDirCache[gid] = resolved;
    return resolved;
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
    if (resolved == _downloadDirCanonical ||
        resolved.startsWith('$_downloadDirCanonical/')) {
      return true;
    }
    return isPathUnderLocalGalleryScanPath(filePath, _config);
  }
}
