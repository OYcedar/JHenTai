import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../service/local_gallery_service.dart';

class LocalRoutes {
  final LocalGalleryService _service;

  LocalRoutes(this._service);

  Router get router {
    final router = Router();

    router.get('/list', _listGalleries);
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
