import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../service/archive_download_service.dart';
import '../service/download_issue_summary.dart';
import '../service/gallery_download_service.dart';
import '../utils/archive_util.dart';

class DownloadRoutes {
  static const int _maxImageListCacheEntries = 128;
  final GalleryDownloadService _galleryService;
  final ArchiveDownloadService _archiveService;
  final ServerConfig _config;
  final Map<String, _ImageListCacheEntry> _imageListCache = {};

  DownloadRoutes(this._galleryService, this._archiveService, this._config);

  Router get router {
    final router = Router();

    router.get('/issues', _downloadIssues);

    // Gallery downloads
    router.get('/gallery/list', _listGalleryDownloads);
    router.post('/gallery/start', _startGalleryDownload);
    router.post('/gallery/upgrade', _upgradeGalleryDownload);
    router.post('/gallery/restore', _restoreGalleryDownloads);
    router.post('/gallery/retry-failed', _retryFailedGalleryDownloads);
    router.patch('/gallery/<gid>', _patchGalleryDownload);
    router.post('/gallery/<gid>/pause', _pauseGalleryDownload);
    router.post('/gallery/<gid>/resume', _resumeGalleryDownload);
    router.post('/gallery/<gid>/redownload', _reDownloadGallery);
    router.post(
        '/gallery/<gid>/image/<serialNo>/redownload', _reDownloadGalleryImage);
    router.delete('/gallery/<gid>', _deleteGalleryDownload);
    router.get('/gallery/<gid>/images', _listGalleryImages);

    // Archive downloads
    router.get('/archive/list', _listArchiveDownloads);
    router.post('/archive/start', _startArchiveDownload);
    router.post('/archive/restore', _restoreArchiveDownloads);
    router.post('/archive/retry-failed', _retryFailedArchiveDownloads);
    router.post('/archive/reunlock-failed', _reUnlockFailedArchiveDownloads);
    router.patch('/archive/<gid>', _patchArchiveDownload);
    router.post('/archive/<gid>/parse-source', _changeArchiveParseSource);
    router.post('/archive/<gid>/pause', _pauseArchiveDownload);
    router.post('/archive/<gid>/resume', _resumeArchiveDownload);
    router.post('/archive/<gid>/reunlock', _reUnlockArchive);
    router.delete('/archive/<gid>', _deleteArchiveDownload);
    router.get('/archive/<gid>/images', _listArchiveImages);

    return router;
  }

  // --- Gallery ---

  Future<Response> _downloadIssues(Request request) async {
    return Response.ok(
      jsonEncode(_downloadIssuesPayload()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _downloadIssuesPayload() {
    return DownloadIssueSummary.build(
      galleryTasks: _galleryService.tasks.map((task) => task.toJson()),
      archiveTasks: _archiveService.tasks.map((task) => task.toJson()),
    );
  }

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
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final title = body['title'] as String?;
    final galleryUrl = body['galleryUrl'] as String?;

    if (gid == null || token == null || title == null || galleryUrl == null) {
      return Response.badRequest(
          body: jsonEncode({
        'error': 'Missing required fields: gid, token, title, galleryUrl'
      }));
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
      downloadOriginalImage: body['downloadOriginalImage'] as bool? ?? false,
      tagSearchText: body['tagSearchText'] as String? ?? '',
      publishTime: body['publishTime'] as String? ?? '',
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
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final fromGid = (body['fromGid'] as num?)?.toInt();
    final newerVersionUrl = body['newerVersionUrl'] as String?;
    if (fromGid == null || newerVersionUrl == null || newerVersionUrl.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing fromGid or newerVersionUrl'}),
      );
    }
    final r = await _galleryService.upgradeFromCompleted(
        fromGid: fromGid, newerVersionUrl: newerVersionUrl);
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

  Future<Response> _restoreGalleryDownloads(Request request) async {
    final restored = await _galleryService.restoreDownloadsFromMetadata();
    return Response.ok(
      jsonEncode({'success': true, 'restoredGalleryCount': restored}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _retryFailedGalleryDownloads(Request request) async {
    final ids = _galleryService.tasks
        .where((task) => task.status == GalleryDownloadStatus.failed)
        .map((task) => task.gid)
        .toList();
    for (final gid in ids) {
      _galleryService.resumeDownload(gid);
    }
    return Response.ok(
      jsonEncode({
        'success': true,
        'retriedGalleryCount': ids.length,
        'issues': _downloadIssuesPayload(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _patchGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final priority = body['priority'];
    final group = body['group'] as String?;
    _galleryService.updateTaskMeta(
      id,
      priority: priority is num ? priority.toInt() : null,
      group: group,
    );
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _changeArchiveParseSource(
      Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final task = _archiveService.getTask(id);
    if (task == null) {
      return Response.notFound(
        jsonEncode({'success': false, 'error': 'Archive task not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (task.status == ArchiveStatus.completed) {
      return Response(
        409,
        body: jsonEncode({
          'success': false,
          'error': 'Completed archive tasks cannot change parse source',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final parseSource = ArchiveParseSource.fromValue(body['parseSource']);
    final ok = await _archiveService.changeParseSource(id, parseSource);
    if (!ok) {
      return Response(
        400,
        body: jsonEncode({'success': false, 'error': 'Change rejected'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({
        'success': true,
        'gid': id,
        'parseSource': parseSource.name,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _pauseGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _galleryService.pauseDownload(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _resumeGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _galleryService.resumeDownload(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _reDownloadGallery(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    final ok = await _galleryService.reDownload(id);
    _invalidateGalleryImageCache(id);
    if (!ok) {
      return Response.notFound(
        jsonEncode({'success': false, 'error': 'Gallery task not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _reDownloadGalleryImage(
      Request request, String gid, String serialNo) async {
    final id = int.tryParse(gid);
    final index = int.tryParse(serialNo);
    if (id == null || index == null || index < 0) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid gid or serialNo'}));
    }
    final ok = await _galleryService.reDownloadImage(id, index);
    _invalidateGalleryImageCache(id);
    if (!ok) {
      return Response.notFound(
        jsonEncode({
          'success': false,
          'error': 'Gallery task or image page not found',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deleteGalleryDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    final deleteFiles = request.url.queryParameters['deleteFiles'] != 'false';
    await _galleryService.deleteDownload(id, deleteFiles: deleteFiles);
    _invalidateGalleryImageCache(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
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
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }

    final gid = body['gid'] as int?;
    final token = body['token'] as String?;
    final title = body['title'] as String?;
    final galleryUrl = body['galleryUrl'] as String?;
    final archivePageUrl = body['archivePageUrl'] as String?;

    if (gid == null ||
        token == null ||
        title == null ||
        galleryUrl == null ||
        archivePageUrl == null) {
      return Response.badRequest(
        body: jsonEncode({
          'error':
              'Missing required fields: gid, token, title, galleryUrl, archivePageUrl'
        }),
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
      tagSearchText: body['tagSearchText'] as String? ?? '',
      publishTime: body['publishTime'] as String? ?? '',
      parseSource: ArchiveParseSource.fromValue(body['parseSource']),
    );

    return Response.ok(
      jsonEncode({'success': true, 'gid': gid}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _patchArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON body'}));
    }
    final priority = body['priority'];
    final group = body['group'] as String?;
    _archiveService.updateTaskMeta(
      id,
      priority: priority is num ? priority.toInt() : null,
      group: group,
    );
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _restoreArchiveDownloads(Request request) async {
    final restored = await _archiveService.restoreDownloadsFromMetadata();
    return Response.ok(
      jsonEncode({'success': true, 'restoredArchiveCount': restored}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _retryFailedArchiveDownloads(Request request) async {
    final ids = _archiveService.tasks
        .where((task) => task.status == ArchiveStatus.failed)
        .map((task) => task.gid)
        .toList();
    for (final gid in ids) {
      _archiveService.resumeDownload(gid);
    }
    return Response.ok(
      jsonEncode({
        'success': true,
        'retriedArchiveCount': ids.length,
        'issues': _downloadIssuesPayload(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _reUnlockFailedArchiveDownloads(Request request) async {
    final ids = _archiveService.tasks
        .where((task) => task.status == ArchiveStatus.failed)
        .map((task) => task.gid)
        .toList();
    var count = 0;
    for (final gid in ids) {
      if (await _archiveService.reUnlock(gid)) {
        count++;
      }
    }
    return Response.ok(
      jsonEncode({
        'success': true,
        'reUnlockedArchiveCount': count,
        'issues': _downloadIssuesPayload(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _pauseArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _archiveService.pauseDownload(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _resumeArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    _archiveService.resumeDownload(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _reUnlockArchive(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    final ok = await _archiveService.reUnlock(id);
    if (!ok) {
      return Response.notFound(
        jsonEncode({'success': false, 'error': 'Archive task not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deleteArchiveDownload(Request request, String gid) async {
    final id = int.tryParse(gid);
    if (id == null)
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    final deleteFiles = request.url.queryParameters['deleteFiles'] != 'false';
    await _archiveService.deleteDownload(id, deleteFiles: deleteFiles);
    _invalidateArchiveImageCache(id);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _listGalleryImages(Request request, String gid) async {
    final gidNum = int.tryParse(gid);
    if (gidNum == null) {
      return Response.ok(
        jsonEncode({'images': <String>[]}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final resolvedDir = resolveGalleryDir(_config.downloadDir, gidNum);
    return _listImageFiles(
        Directory(resolvedDir ?? p.join(_config.downloadDir, 'gallery', gid)));
  }

  Future<Response> _listArchiveImages(Request request, String gid) async {
    final gidNum = int.tryParse(gid);
    if (gidNum == null) {
      return Response.ok(
        jsonEncode({'images': <String>[]}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final resolvedDir = resolveArchiveDir(_config.downloadDir, gidNum);
    return _listImageFiles(
        Directory(resolvedDir ?? p.join(_config.downloadDir, 'archive', gid)));
  }

  Future<Response> _listImageFiles(Directory dir) async {
    if (!dir.existsSync()) {
      _imageListCache.remove(dir.path);
      return Response.ok(
        jsonEncode({'images': <String>[]}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final stat = dir.statSync();
    final cached = _imageListCache[dir.path];
    if (cached != null &&
        cached.modified == stat.modified &&
        cached.entityChanged == stat.changed) {
      cached.touch();
      return Response.ok(
        jsonEncode({'images': cached.images}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final imageExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.avif',
    };
    final files = dir
        .listSync()
        .whereType<File>()
        .where(
            (f) => imageExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList();
    files.sort(
      (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
    );

    final images = files.map((f) => p.basename(f.path)).toList();
    _imageListCache[dir.path] = _ImageListCacheEntry(
      modified: stat.modified,
      entityChanged: stat.changed,
      images: images,
    );
    _evictImageListCache();

    return Response.ok(
      jsonEncode({'images': images}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  void _invalidateGalleryImageCache(int gid) {
    final legacyPath = p.join(_config.downloadDir, 'gallery', '$gid');
    _imageListCache.remove(legacyPath);
    _imageListCache.removeWhere(
        (path, _) => path.startsWith(p.join(_config.downloadDir, '$gid - ')));
  }

  void _invalidateArchiveImageCache(int gid) {
    final legacyPath = p.join(_config.downloadDir, 'archive', '$gid');
    _imageListCache.remove(legacyPath);
    _imageListCache.removeWhere((path, _) =>
        path.startsWith(p.join(_config.downloadDir, 'Archive - $gid - ')));
  }

  void _evictImageListCache() {
    if (_imageListCache.length <= _maxImageListCacheEntries) return;
    final entries = _imageListCache.entries.toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final entry in entries) {
      if (_imageListCache.length <= _maxImageListCacheEntries) break;
      _imageListCache.remove(entry.key);
    }
  }
}

class _ImageListCacheEntry {
  _ImageListCacheEntry({
    required this.modified,
    required this.entityChanged,
    required this.images,
  });

  final DateTime modified;
  final DateTime entityChanged;
  final List<String> images;
  int lastUsed = DateTime.now().millisecondsSinceEpoch;

  void touch() {
    lastUsed = DateTime.now().millisecondsSinceEpoch;
  }
}
