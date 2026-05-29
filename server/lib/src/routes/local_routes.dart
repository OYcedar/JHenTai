import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../service/local_gallery_service.dart';
import '../service/local_gallery_runtime_settings.dart';

class LocalRoutes {
  final LocalGalleryService _service;

  LocalRoutes(this._service);

  Router get router {
    final router = Router();

    router.get('/list', _listGalleries);
    router.get('/roots', _listRoots);
    router.post('/roots', _addRoot);
    router.delete('/roots', _deleteRoot);
    router.post('/refresh', _refresh);
    router.get('/images', _getImages);
    router.delete('/gallery', _deleteGallery);

    return router;
  }

  Future<Response> _listGalleries(Request request) async {
    final galleries = _service.galleries.map((g) => g.toJson()).toList();
    return Response.ok(
      jsonEncode({
        'galleries': galleries,
        'scanning': _service.isScanning,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _listRoots(Request request) async {
    return Response.ok(
      jsonEncode({
        'roots': _service.allowedScanPaths,
        'extraRoots': webExtraLocalGalleryScanPaths(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _addRoot(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid JSON body'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final path = body['path']?.toString().trim() ?? '';
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing path'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (!await Directory(path).exists()) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Directory does not exist'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final paths = webExtraLocalGalleryScanPaths();
    if (!paths.contains(path)) {
      saveWebExtraLocalGalleryScanPaths([...paths, path]);
    }
    _service.refresh();
    return _listRoots(request);
  }

  Future<Response> _deleteRoot(Request request) async {
    final path = request.url.queryParameters['path']?.trim() ?? '';
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing path'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    removeWebExtraLocalGalleryScanPath(path);
    _service.refresh();
    return _listRoots(request);
  }

  Future<Response> _refresh(Request request) async {
    _service.refresh();
    return Response.ok(
      jsonEncode({'success': true, 'message': 'Scan started'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getImages(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Missing path parameter'}));
    }

    if (!_service.isPathAllowed(path)) {
      return Response.forbidden(
        jsonEncode({'error': 'Path is outside allowed scan directories'}),
      );
    }

    final images = _service.getGalleryImages(path);
    return Response.ok(
      jsonEncode({'images': images}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _deleteGallery(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing path parameter'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (!_service.isPathAllowed(path)) {
      return Response.forbidden(
        jsonEncode({'error': 'Path is outside allowed scan directories'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      await _service.deleteGallery(path);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete local gallery: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
