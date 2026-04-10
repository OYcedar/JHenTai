import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../service/gallery_download_service.dart';
import '../service/archive_download_service.dart';

class DownloadRoutes {
  final GalleryDownloadService _galleryService;
  final ArchiveDownloadService _archiveService;
  final ServerConfig _config;

  DownloadRoutes(this._galleryService, this._archiveService, this._config);

  Router get router {
    final router = Router();

    // Gallery downloads
    router.get('/gallery/list', _listGalleryDownloads);
    router.post('/gallery/start', _startGalleryDownload);
    router.post('/gallery/upgrade', _upgradeGalleryDownload);
    router.patch('/gallery/<gid>', _patchGalleryDownload);
    router.post('/gallery/<gid>/pause', _pauseGalleryDownload);
    router.post('/gallery/<gid>/resume', _resumeGalleryDownload);
    router.delete('/gallery/<gid>', _deleteGalleryDownload);
    router.get('/gallery/<gid>/images', _listGalleryImages);

    // Archive downloads
    router.get('/archive/list', _listArchiveDownloads);
    router.post('/archive/start', _startArchiveDownload);
    router.patch('/archive/<gid>', _patchArchiveDownload);
    router.post('/archive/<gid>/pause', _pauseArchiveDownload);
    router.post('/archive/<gid>/resume', _resumeArchiveDownload);
    router.delete('/archive/<gid>', _deleteArchiveDownload);
    router.get('/archive/<gid>/images', _listArchiveImages);

    return router;
  }

  // --- Gallery ---

  Future<Response> _listGalleryDownloads(Request request) async {
    final tasks = _galleryService.tasks.map((t) => t.toJson()).toList();
    return Response.ok(
      jsonEncode({'tasks': tasks}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _startGalleryDownload(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final title = body['title'] as String?;
    final galleryUrl = body['galleryUrl'] as String?;

    if (gid == null || token == null || title == null || galleryUrl == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing required fields: gid, token, title, galleryUrl'}));
    }

    await _galleryService.startDownload(
      gid: gid,
      token: token,
      title: title,
      category: body['category'] as String? ?? '',
      pageCount: body['pageCount'] as int? ?? 0,
      galleryUrl: galleryUrl,
      coverUrl: body['coverUrl'] as String? ?? '',
      uploader: body['uploader'] as String? ?? '',
      group: body['group'] as String? ?? 'default',
      priority: (body['priority'] as num?)?.toInt() ?? 0,
    );

    return Response.ok(
      jsonEncode({'success': true, 'gid': gid}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _upgradeGalleryDownload(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final fromGid = (body['fromGid'] as num?)?.toInt();
    final newerVersionUrl = body['newerVersionUrl'] as String?;
    if (fromGid == null || newerVersionUrl == null || newerVersionUrl.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing fromGid or newerVersionUrl'}),
      );
    }
    final r = await _galleryService.upgradeFromCompleted(fromGid: fromGid, newerVersionUrl: newerVersionUrl);
    if (!r.ok) {
      return Response(
        400,
        body: jsonEncode({'success': false, 'error': r.error}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'success': true, 'newGid': r.newGid}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _patchGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final priority = body['priority'];
    final group = body['group'] as String?;
    _galleryService.updateTaskMeta(
      id,
      priority: priority is num ? priority.toInt() : null,
      group: group,
    );
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _pauseGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _galleryService.pauseDownload(id);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _resumeGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _galleryService.resumeDownload(id);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deleteGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    final deleteFiles = request.url.queryParameters['deleteFiles'] != 'false';
    await _galleryService.deleteDownload(id, deleteFiles: deleteFiles);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  // --- Archive ---

  Future<Response> _listArchiveDownloads(Request request) async {
    final tasks = _archiveService.tasks.map((t) => t.toJson()).toList();
    return Response.ok(
      jsonEncode({'tasks': tasks}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _startArchiveDownload(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final title = body['title'] as String?;
    final galleryUrl = body['galleryUrl'] as String?;
    final archivePageUrl = body['archivePageUrl'] as String?;

    if (gid == null || token == null || title == null || galleryUrl == null || archivePageUrl == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing required fields: gid, token, title, galleryUrl, archivePageUrl'}),
      );
    }

    await _archiveService.startDownload(
      gid: gid,
      token: token,
      title: title,
      category: body['category'] as String? ?? '',
      pageCount: body['pageCount'] as int? ?? 0,
      galleryUrl: galleryUrl,
      archivePageUrl: archivePageUrl,
      coverUrl: body['coverUrl'] as String? ?? '',
      uploader: body['uploader'] as String? ?? '',
      size: body['size'] as String? ?? '',
      isOriginal: body['isOriginal'] as bool? ?? false,
      group: body['group'] as String? ?? 'default',
      priority: (body['priority'] as num?)?.toInt() ?? 0,
    );

    return Response.ok(
      jsonEncode({'success': true, 'gid': gid}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _patchArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final priority = body['priority'];
    final group = body['group'] as String?;
    _archiveService.updateTaskMeta(
      id,
      priority: priority is num ? priority.toInt() : null,
      group: group,
    );
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _pauseArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _archiveService.pauseDownload(id);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _resumeArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _archiveService.resumeDownload(id);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deleteArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    final deleteFiles = request.url.queryParameters['deleteFiles'] != 'false';
    await _archiveService.deleteDownload(id, deleteFiles: deleteFiles);
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _listGalleryImages(Request request, String gid) async {
    final dir = Directory(p.join(_config.downloadDir, 'gallery', gid));
    return _listImageFiles(dir);
  }

  Future<Response> _listArchiveImages(Request request, String gid) async {
    final dir = Directory(p.join(_config.downloadDir, 'archive', gid));
    return _listImageFiles(dir);
  }

  Future<Response> _listImageFiles(Directory dir) async {
    if (!dir.existsSync()) {
      return Response.ok(
        jsonEncode({'images': <String>[]}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
    final files = dir.listSync()
        .whereType<File>()
        .where((f) => imageExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList();
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return Response.ok(
      jsonEncode({'images': files.map((f) => p.basename(f.path)).toList()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
