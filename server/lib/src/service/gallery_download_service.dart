import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import '../network/eh_client.dart';
import '../network/jh_public_client.dart';
import '../service/event_bus.dart';
import '../utils/archive_util.dart';
import 'download_runtime_settings.dart';
import 'download_rate_limiter.dart';
import 'super_resolution_service.dart';

T _safeEnum<T extends Enum>(List<T> values, int index, T fallback) {
  return (index >= 0 && index < values.length) ? values[index] : fallback;
}

enum GalleryDownloadStatus {
  none,
  downloading,
  paused,
  completed,
  failed,
}

class GalleryDownloadTask {
  final int gid;
  final String token;
  final String title;
  final String category;
  final int pageCount;
  final String galleryUrl;
  String coverUrl;
  final String uploader;
  GalleryDownloadStatus status;
  int completedCount;
  String group;
  int priority;
  final bool downloadOriginalImage;
  final String tagSearchText;
  final String publishTime;
  final String insertTime;
  int? supersedesGid;
  int? supersededByGid;
  String lastError;
  String errorCategory;
  CancelToken? _cancelToken;

  GalleryDownloadTask({
    required this.gid,
    required this.token,
    required this.title,
    required this.category,
    required this.pageCount,
    required this.galleryUrl,
    required this.coverUrl,
    required this.uploader,
    this.status = GalleryDownloadStatus.none,
    this.completedCount = 0,
    this.group = 'default',
    this.priority = 0,
    this.downloadOriginalImage = false,
    this.tagSearchText = '',
    required this.publishTime,
    required this.insertTime,
    this.supersedesGid,
    this.supersededByGid,
    this.lastError = '',
    this.errorCategory = '',
  });

  Map<String, dynamic> toJson() => {
        'gid': gid,
        'token': token,
        'title': title,
        'category': category,
        'pageCount': pageCount,
        'galleryUrl': galleryUrl,
        'coverUrl': coverUrl,
        'uploader': uploader,
        'status': status.index,
        'completedCount': completedCount,
        'group': group,
        'group_name': group,
        'priority': priority,
        'downloadOriginalImage': downloadOriginalImage,
        'is_original': downloadOriginalImage ? 1 : 0,
        'tagSearchText': tagSearchText,
        'tag_search_text': tagSearchText,
        'publishTime': publishTime,
        'publish_time': publishTime,
        'insertTime': insertTime,
        if (supersedesGid != null) 'supersedesGid': supersedesGid,
        if (supersededByGid != null) 'supersededByGid': supersededByGid,
        if (lastError.isNotEmpty) 'lastError': lastError,
        if (errorCategory.isNotEmpty) 'errorCategory': errorCategory,
      };
}

/// Parses `/g/{gid}/{token}/` from absolute or site-relative URL.
({int gid, String token})? parseGalleryGidToken(String raw, String siteOrigin) {
  var s = raw.trim();
  if (s.startsWith('/')) s = '$siteOrigin$s';
  final m = RegExp(r'/g/(\d+)/([^/]+)').firstMatch(s);
  if (m == null) return null;
  final gid = int.tryParse(m.group(1)!);
  if (gid == null) return null;
  return (gid: gid, token: m.group(2)!);
}

class GalleryDownloadService {
  final EHClient _client;
  final ServerConfig _config;
  final EventBus _eventBus;
  final SuperResolutionService? _superResolutionService;

  final Map<int, GalleryDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};
  final DownloadRateLimiter _rateLimiter = DownloadRateLimiter();

  int get _maxConcurrent => effectiveMaxConcurrentGalleryDownloads(_config);

  List<GalleryDownloadTask> get tasks => _tasks.values.toList();
  int get activeDownloadCount => _activeDownloads.length;

  GalleryDownloadService(this._client, this._config, this._eventBus,
      {SuperResolutionService? superResolutionService})
      : _superResolutionService = superResolutionService;

  Future<void> init() async {
    _loadTasksFromDatabase();
    log.info('Loaded ${_tasks.length} gallery download tasks');

    final toResume = _tasks.values
        .where((t) => t.status == GalleryDownloadStatus.downloading)
        .toList();
    for (final task in toResume) {
      log.info('Resuming gallery download: ${task.gid} (${task.title})');
    }
    if (toResume.isNotEmpty) {
      _processQueue();
    }
  }

  void reloadFromDatabase() {
    for (final task in _tasks.values) {
      task._cancelToken?.cancel('reload');
    }
    _activeDownloads.clear();
    _loadTasksFromDatabase();
    log.info('Reloaded ${_tasks.length} gallery download tasks');
  }

  void _loadTasksFromDatabase() {
    _tasks.clear();
    final rows = db.selectAllGalleryDownloads();
    for (final row in rows) {
      final task = GalleryDownloadTask(
        gid: row['gid'] as int,
        token: row['token'] as String,
        title: row['title'] as String,
        category: row['category'] as String,
        pageCount: row['page_count'] as int,
        galleryUrl: row['gallery_url'] as String,
        coverUrl: row['cover_url'] as String? ?? '',
        uploader: row['uploader'] as String? ?? '',
        status: _safeEnum(GalleryDownloadStatus.values,
            row['download_status'] as int, GalleryDownloadStatus.failed),
        completedCount: row['completed_count'] as int? ?? 0,
        group: row['group_name'] as String? ?? 'default',
        priority: row['priority'] as int? ?? 0,
        downloadOriginalImage:
            (row['download_original_image'] as int? ?? 0) == 1,
        tagSearchText: row['tag_search_text'] as String? ?? '',
        publishTime: row['publish_time'] as String? ?? '',
        insertTime:
            row['insert_time'] as String? ?? DateTime.now().toIso8601String(),
        supersedesGid: row['supersedes_gid'] as int?,
        supersededByGid: row['superseded_by_gid'] as int?,
      );
      _tasks[task.gid] = task;
    }
  }

  Future<void> startDownload({
    required int gid,
    required String token,
    required String title,
    required String category,
    required int pageCount,
    required String galleryUrl,
    String coverUrl = '',
    String uploader = '',
    String group = 'default',
    int priority = 0,
    bool downloadOriginalImage = false,
    String tagSearchText = '',
    String? publishTime,
    int? supersedesGid,
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.status == GalleryDownloadStatus.paused ||
          existing.status == GalleryDownloadStatus.failed) {
        existing.status = GalleryDownloadStatus.downloading;
        existing.lastError = '';
        existing.errorCategory = '';
        db.updateGalleryDownloadStatus(
            gid, GalleryDownloadStatus.downloading.index);
        _processQueue();
      }
      return;
    }

    final now = DateTime.now().toIso8601String();
    final task = GalleryDownloadTask(
      gid: gid,
      token: token,
      title: title,
      category: category,
      pageCount: pageCount,
      galleryUrl: galleryUrl,
      coverUrl: coverUrl,
      uploader: uploader,
      status: GalleryDownloadStatus.downloading,
      group: group,
      priority: priority,
      downloadOriginalImage: downloadOriginalImage,
      tagSearchText: tagSearchText,
      publishTime:
          publishTime != null && publishTime.isNotEmpty ? publishTime : now,
      insertTime: now,
      supersedesGid: supersedesGid,
    );

    _tasks[gid] = task;
    db.insertGalleryDownload({
      'gid': gid,
      'token': token,
      'title': title,
      'category': category,
      'page_count': pageCount,
      'gallery_url': galleryUrl,
      'cover_url': coverUrl,
      'uploader': uploader,
      'publish_time':
          publishTime != null && publishTime.isNotEmpty ? publishTime : now,
      'download_status': GalleryDownloadStatus.downloading.index,
      'insert_time': now,
      'group_name': group,
      'priority': priority,
      'download_original_image': downloadOriginalImage ? 1 : 0,
      'tag_search_text': tagSearchText,
      'supersedes_gid': supersedesGid,
    });

    _notifyProgress(task);
    _processQueue();
  }

  /// When [fromGid] is completed, start download for newer gallery URL; link rows in DB.
  Future<({bool ok, String? error, int? newGid})> upgradeFromCompleted({
    required int fromGid,
    required String newerVersionUrl,
  }) async {
    final old = _tasks[fromGid];
    if (old == null) {
      return (ok: false, error: 'Unknown gallery task', newGid: null);
    }
    if (old.status != GalleryDownloadStatus.completed) {
      return (
        ok: false,
        error: 'Only completed downloads can be upgraded',
        newGid: null
      );
    }

    final resolved = newerVersionUrl.startsWith('http')
        ? newerVersionUrl
        : '${_client.baseUrl}${newerVersionUrl.startsWith('/') ? '' : '/'}$newerVersionUrl';
    final parsed = parseGalleryGidToken(resolved, _client.baseUrl);
    if (parsed == null) {
      return (
        ok: false,
        error: 'Could not parse newer gallery URL',
        newGid: null
      );
    }
    final newGid = parsed.gid;
    final newToken = parsed.token;
    if (newGid == fromGid) {
      return (ok: false, error: 'New URL points to same gallery', newGid: null);
    }
    if (_tasks.containsKey(newGid)) {
      return (
        ok: false,
        error: 'New gallery already in download list',
        newGid: null
      );
    }

    final galleryUrl = '${_client.baseUrl}/g/$newGid/$newToken/';
    GalleryDetailResult detail;
    try {
      detail = await _client.fetchGalleryDetail(galleryUrl);
    } catch (e) {
      return (
        ok: false,
        error: 'Failed to fetch new gallery: $e',
        newGid: null
      );
    }

    db.updateGalleryDownloadMeta(fromGid, supersededByGid: newGid);
    old.supersededByGid = newGid;
    _notifyProgress(old);

    await startDownload(
      gid: newGid,
      token: newToken,
      title: detail.title,
      category: detail.category,
      pageCount: detail.pageCount,
      galleryUrl: galleryUrl,
      coverUrl: detail.coverUrl,
      uploader: detail.uploader,
      group: old.group,
      priority: old.priority,
      downloadOriginalImage: old.downloadOriginalImage,
      supersedesGid: fromGid,
    );

    return (ok: true, error: null, newGid: newGid);
  }

  void updateTaskMeta(int gid, {int? priority, String? group}) {
    final task = _tasks[gid];
    if (task == null) return;
    if (priority != null) {
      task.priority = priority;
      db.updateGalleryDownloadMeta(gid, priority: priority);
    }
    if (group != null) {
      task.group = group;
      db.updateGalleryDownloadMeta(gid, groupName: group);
    }
    _notifyProgress(task);
  }

  void pauseDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    task.status = GalleryDownloadStatus.paused;
    task._cancelToken?.cancel('paused');
    _activeDownloads.remove(gid);
    db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.paused.index);
    _notifyProgress(task);
    _processQueue();
  }

  void resumeDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    if (task.status != GalleryDownloadStatus.paused &&
        task.status != GalleryDownloadStatus.failed) return;
    task.status = GalleryDownloadStatus.downloading;
    task.lastError = '';
    task.errorCategory = '';
    db.updateGalleryDownloadStatus(
        gid, GalleryDownloadStatus.downloading.index);
    _notifyProgress(task);
    _processQueue();
  }

  Future<bool> reDownload(int gid) async {
    final old = _tasks[gid];
    if (old == null) return false;

    old.status = GalleryDownloadStatus.paused;
    old._cancelToken?.cancel('redownload');
    _activeDownloads.remove(gid);

    final token = old.token;
    final title = old.title;
    final category = old.category;
    final pageCount = old.pageCount;
    final galleryUrl = old.galleryUrl;
    final coverUrl = old.coverUrl;
    final uploader = old.uploader;
    final group = old.group;
    final priority = old.priority;
    final downloadOriginalImage = old.downloadOriginalImage;
    final supersedesGid = old.supersedesGid;

    _tasks.remove(gid);
    db.deleteGalleryDownload(gid);

    final dir = Directory(_galleryDir(old));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    await startDownload(
      gid: gid,
      token: token,
      title: title,
      category: category,
      pageCount: pageCount,
      galleryUrl: galleryUrl,
      coverUrl: coverUrl,
      uploader: uploader,
      group: group,
      priority: priority,
      downloadOriginalImage: downloadOriginalImage,
      supersedesGid: supersedesGid,
    );
    return true;
  }

  Future<bool> reDownloadImage(int gid, int serialNo) async {
    final task = _tasks[gid];
    if (task == null || serialNo < 0 || serialNo >= task.pageCount) {
      return false;
    }
    if (_activeDownloads.contains(gid)) {
      return false;
    }

    final imagePageUrls = await _imagePageUrlsForTask(task);
    if (serialNo >= imagePageUrls.length) {
      return false;
    }

    final previousStatus = task.status;
    final dir = Directory(_galleryDir(task));
    await dir.create(recursive: true);
    final existing = _findExistingImage(gid, serialNo);
    if (existing != null && await existing.exists()) {
      await existing.delete();
    }

    task.status = GalleryDownloadStatus.downloading;
    task.completedCount = _countExistingImages(dir);
    db.updateGalleryDownloadStatus(gid, task.status.index,
        completedCount: task.completedCount);
    _notifyProgress(task);

    try {
      await _downloadImagePage(task, serialNo, imagePageUrls[serialNo], dir);
      task.completedCount = _countExistingImages(dir);
      task.status = task.completedCount >= task.pageCount
          ? GalleryDownloadStatus.completed
          : previousStatus;
      db.updateGalleryDownloadStatus(gid, task.status.index,
          completedCount: task.completedCount);
      _notifyProgress(task);
      return true;
    } catch (e, s) {
      log.error(
          'Re-download image failed for gallery $gid page $serialNo', e, s);
      task.status = previousStatus == GalleryDownloadStatus.completed
          ? GalleryDownloadStatus.failed
          : previousStatus;
      db.updateGalleryDownloadStatus(gid, task.status.index,
          completedCount: task.completedCount);
      _notifyProgress(task, error: '$e');
      return false;
    }
  }

  Future<void> deleteDownload(int gid, {bool deleteFiles = true}) async {
    final task = _tasks.remove(gid);
    task?._cancelToken?.cancel('deleted');
    _activeDownloads.remove(gid);
    db.deleteGalleryDownload(gid);

    if (deleteFiles) {
      // 新格式 `<gid> - <标题>` 与旧格式 `gallery/<gid>` 都删。
      final dirs = <String>{p.join(_config.downloadDir, 'gallery', '$gid')};
      if (task != null) {
        dirs.add(_galleryDir(task));
      } else {
        final resolved = resolveGalleryDir(_config.downloadDir, gid);
        if (resolved != null) dirs.add(resolved);
      }
      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    }
    _eventBus.fire('download_removed', {'type': 'gallery', 'gid': gid});
    _processQueue();
  }

  Future<int> restoreDownloadsFromMetadata() async {
    // 新格式：下载根目录下 `<gid> - <标题>` 文件夹，内含 metadata（app 端包裹格式）。
    // 旧格式：`gallery/<gid>` 文件夹，内含 metadata.json。两者都恢复。
    final candidates = <Directory>[];
    final root = Directory(_config.downloadDir);
    if (root.existsSync()) {
      try {
        await for (final entity in root.list(followLinks: false)) {
          if (entity is Directory &&
              RegExp(r'^\d+ - ').hasMatch(p.basename(entity.path))) {
            candidates.add(entity);
          }
        }
      } catch (e) {
        log.warning('Restore gallery scan failed: ${root.path}: $e');
      }
    }
    final legacyRoot = Directory(p.join(_config.downloadDir, 'gallery'));
    if (legacyRoot.existsSync()) {
      try {
        await for (final entity in legacyRoot.list(followLinks: false)) {
          if (entity is Directory) candidates.add(entity);
        }
      } catch (e) {
        log.warning('Restore gallery scan failed: ${legacyRoot.path}: $e');
      }
    }

    var restored = 0;
    for (final entity in candidates) {
      final metaFile = File(p.join(entity.path, 'metadata'));
      final legacyMetaFile = File(p.join(entity.path, 'metadata.json'));
      final metaFileToUse = metaFile.existsSync()
          ? metaFile
          : (legacyMetaFile.existsSync() ? legacyMetaFile : null);
      if (metaFileToUse == null) continue;

      Map<String, dynamic> meta;
      try {
        final decoded = jsonDecode(await metaFileToUse.readAsString());
        if (decoded is! Map) continue;
        meta = decoded.cast<String, dynamic>();
      } catch (e) {
        log.warning(
            'Restore gallery metadata failed: ${metaFileToUse.path}: $e');
        continue;
      }

      // app 端包裹格式：{"gallery": {...}, "images": "..."}
      final gallery = meta['gallery'];
      if (gallery is Map) {
        meta = gallery.cast<String, dynamic>();
      }

      final gid = (meta['gid'] as num?)?.toInt() ??
          int.tryParse(p.basename(entity.path));
      if (gid == null || _tasks.containsKey(gid)) continue;

      final token = meta['token']?.toString() ?? '';
      final title = meta['title']?.toString() ?? '';
      final galleryUrl = meta['galleryUrl']?.toString() ?? '';
      if (token.isEmpty || title.isEmpty || galleryUrl.isEmpty) continue;

      final imagePageUrls = (meta['imagePageUrls'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      final pageCount =
          (meta['pageCount'] as num?)?.toInt() ?? imagePageUrls.length;
      final completedCount = _countExistingImages(entity);
      final status = pageCount > 0 && completedCount >= pageCount
          ? GalleryDownloadStatus.completed
          : GalleryDownloadStatus.paused;
      final insertTime = meta['insertTime']?.toString() ??
          (await metaFileToUse.stat()).modified.toIso8601String();

      final task = GalleryDownloadTask(
        gid: gid,
        token: token,
        title: title,
        category: meta['category']?.toString() ?? '',
        pageCount: pageCount,
        galleryUrl: galleryUrl,
        coverUrl: meta['coverUrl']?.toString() ?? '',
        uploader: meta['uploader']?.toString() ?? '',
        status: status,
        completedCount: completedCount,
        group: meta['group']?.toString() ??
            meta['groupName']?.toString() ??
            'default',
        priority: (meta['priority'] as num?)?.toInt() ?? 0,
        downloadOriginalImage: meta['downloadOriginalImage'] as bool? ?? false,
        publishTime: meta['publishTime']?.toString() ??
            meta['publish_time']?.toString() ??
            insertTime,
        insertTime: insertTime,
      );

      _tasks[gid] = task;
      db.insertGalleryDownload({
        'gid': gid,
        'token': token,
        'title': title,
        'category': task.category,
        'page_count': pageCount,
        'gallery_url': galleryUrl,
        'cover_url': task.coverUrl,
        'uploader': task.uploader,
        'publish_time': task.publishTime,
        'download_status': status.index,
        'insert_time': insertTime,
        'completed_count': completedCount,
        'group_name': task.group,
        'priority': task.priority,
        'download_original_image': task.downloadOriginalImage ? 1 : 0,
      });

      for (var i = 0; i < pageCount; i++) {
        final imageFile = _findExistingImage(gid, i);
        if (imageFile == null) continue;
        db.upsertGalleryImage({
          'gid': gid,
          'serial_no': i,
          'url': '',
          'image_url': '',
          'image_hash': '',
          'path': imageFile.path,
          'download_status': 1,
          'image_page_url': i < imagePageUrls.length ? imagePageUrls[i] : '',
        });
      }

      restored++;
      _notifyProgress(task);
    }

    if (restored > 0) _processQueue();
    return restored;
  }

  GalleryDownloadTask? _nextQueuedTask() {
    final activePriorities =
        effectiveDownloadAllGalleriesOfSamePriority(_config)
            ? const <int>{}
            : _activeDownloads
                .map((gid) => _tasks[gid]?.priority)
                .whereType<int>()
                .toSet();
    final candidates = _tasks.values
        .where((t) =>
            t.status == GalleryDownloadStatus.downloading &&
            !_activeDownloads.contains(t.gid) &&
            !activePriorities.contains(t.priority))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final c = b.priority.compareTo(a.priority);
      if (c != 0) return c;
      return a.insertTime.compareTo(b.insertTime);
    });
    return candidates.first;
  }

  void _processQueue() {
    while (_activeDownloads.length < _maxConcurrent) {
      final next = _nextQueuedTask();
      if (next == null) break;
      _activeDownloads.add(next.gid);
      _doDownload(next);
    }
  }

  Future<void> _doDownload(GalleryDownloadTask task) async {
    try {
      final dir = Directory(_galleryDir(task));
      await dir.create(recursive: true);

      final detail = await _client.fetchGalleryDetail(task.galleryUrl);
      List<String> imagePageUrls = detail.imagePageUrls;

      if (imagePageUrls.isEmpty) {
        log.warning('No image pages found for gallery ${task.gid}');
        task.status = GalleryDownloadStatus.failed;
        task.lastError = 'No image pages found';
        task.errorCategory = 'imagePage';
        db.updateGalleryDownloadStatus(
            task.gid, GalleryDownloadStatus.failed.index);
        _activeDownloads.remove(task.gid);
        _notifyProgress(task);
        return;
      }

      if (detail.pageCount > imagePageUrls.length) {
        final totalPages = (detail.pageCount / imagePageUrls.length).ceil();
        for (int page = 1; page < totalPages; page++) {
          final nextDetail =
              await _client.fetchGalleryDetail('${task.galleryUrl}?p=$page');
          imagePageUrls.addAll(nextDetail.imagePageUrls);
        }
      }

      task.coverUrl =
          detail.coverUrl.isNotEmpty ? detail.coverUrl : task.coverUrl;

      _saveMetadata(task, imagePageUrls);

      await _tryCopyPagesFromSupersededGallery(task, imagePageUrls);

      for (int i = 0; i < imagePageUrls.length; i++) {
        if (task.status != GalleryDownloadStatus.downloading) break;

        final imageFile = _findExistingImage(task.gid, i);
        if (imageFile != null) {
          task.completedCount = i + 1;
          db.updateGalleryDownloadStatus(task.gid, task.status.index,
              completedCount: task.completedCount);
          _notifyProgress(task);
          continue;
        }

        var downloaded = false;
        try {
          await _downloadImagePage(task, i, imagePageUrls[i], dir);
          task.completedCount = i + 1;
          db.updateGalleryDownloadStatus(task.gid, task.status.index,
              completedCount: task.completedCount);
          _notifyProgress(task);
          downloaded = true;
        } catch (_) {
          downloaded = false;
        }

        if (!downloaded && task.status == GalleryDownloadStatus.downloading) {
          log.warning(
              'Failed to download image $i after retries, marking gallery ${task.gid} as failed');
          task.status = GalleryDownloadStatus.failed;
          task.lastError = 'Failed to download image ${i + 1} after retries';
          task.errorCategory = 'imagePage';
          db.updateGalleryDownloadStatus(
              task.gid, GalleryDownloadStatus.failed.index);
          _notifyProgress(task,
              error: 'Failed to download image ${i + 1} after retries');
          return;
        }
      }

      if (task.status == GalleryDownloadStatus.downloading) {
        task.status = GalleryDownloadStatus.completed;
        task.lastError = '';
        task.errorCategory = '';
        db.updateGalleryDownloadStatus(
            task.gid, GalleryDownloadStatus.completed.index,
            completedCount: task.completedCount);
        _notifyProgress(task);
        log.info('Gallery ${task.gid} download completed');
        final superResolutionService = _superResolutionService;
        if (superResolutionService != null) {
          unawaited(superResolutionService.createJobIfAutoEnabled(
              sourceType: 'gallery', gid: task.gid));
        }
      }
    } catch (e, s) {
      log.error('Gallery download failed for ${task.gid}', e, s);
      task.status = GalleryDownloadStatus.failed;
      task.lastError = '$e';
      task.errorCategory = _classifyGalleryError('$e');
      db.updateGalleryDownloadStatus(
          task.gid, GalleryDownloadStatus.failed.index);
      _notifyProgress(task, error: '$e');
    } finally {
      _activeDownloads.remove(task.gid);
      _processQueue();
    }
  }

  Future<void> _downloadImagePage(
    GalleryDownloadTask task,
    int index,
    String imagePageUrl,
    Directory dir,
  ) async {
    int retries = 0;
    const maxRetries = 3;
    String? reloadKey;
    while (retries < maxRetries &&
        task.status == GalleryDownloadStatus.downloading) {
      try {
        task._cancelToken = CancelToken();
        var pageUrl = imagePageUrl;
        if (reloadKey != null) {
          final sep = pageUrl.contains('?') ? '&' : '?';
          pageUrl = '$pageUrl${sep}nl=$reloadKey';
        }
        final imagePage = await _client.fetchImagePage(
          pageUrl,
          preferOriginalImage: task.downloadOriginalImage,
        );

        if (imagePage.imageUrl.isEmpty) {
          reloadKey = imagePage.reloadKey;
          retries++;
          continue;
        }

        final ext = _getExtension(imagePage.imageUrl);
        final savePath = p.join(dir.path, '$index.$ext');

        await _rateLimiter.waitForSlot();
        cancelTokenThrowIfCancelled(task._cancelToken);
        await _client.downloadFile(
          imagePage.imageUrl,
          savePath,
          cancelToken: task._cancelToken,
        );

        db.upsertGalleryImage({
          'gid': task.gid,
          'serial_no': index,
          'url': '',
          'image_url': imagePage.imageUrl,
          'image_hash': imagePage.imageHash,
          'path': savePath,
          'download_status': 1,
          'image_page_url': imagePageUrl,
        });
        return;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        retries++;
        if (e.response?.statusCode == 509) {
          reloadKey = null;
          log.warning(
              'Image limit (509) on image $index for gallery ${task.gid}, retrying...');
          await Future.delayed(Duration(seconds: retries * 5));
        } else {
          if (retries >= maxRetries) {
            log.warning(
                'Failed to download image $index for gallery ${task.gid}');
          }
          await Future.delayed(Duration(seconds: retries));
        }
      } catch (e) {
        retries++;
        log.error('Error downloading image $index for gallery ${task.gid}', e);
        await Future.delayed(Duration(seconds: retries));
      }
    }
    throw StateError('Failed to download image ${index + 1}');
  }

  Future<List<String>> _imagePageUrlsForTask(GalleryDownloadTask task) async {
    final rows = db.selectGalleryImages(task.gid);
    final fromDb = <String>[];
    for (final row in rows) {
      final url = row['image_page_url'] as String? ?? '';
      if (url.isNotEmpty) fromDb.add(url);
    }
    if (fromDb.length >= task.pageCount) return fromDb;

    // app 端格式：metadata 文件，images 是 GalleryImage JSON 列表的编码字符串。
    final metaFile = File(p.join(_galleryDir(task), 'metadata'));
    if (await metaFile.exists()) {
      try {
        final decoded = jsonDecode(await metaFile.readAsString());
        if (decoded is Map) {
          final raw = decoded['images'];
          if (raw is String && raw.isNotEmpty) {
            final list = jsonDecode(raw);
            if (list is List) {
              final urls = [
                for (final item in list)
                  if (item is Map && item['url']?.toString().isNotEmpty == true)
                    item['url'].toString()
              ];
              if (urls.length >= task.pageCount) return urls;
            }
          }
        }
      } catch (_) {}
    }

    // fork 旧格式：metadata.json 的 imagePageUrls 字段。
    final legacyMetaFile = File(p.join(_galleryDir(task), 'metadata.json'));
    if (await legacyMetaFile.exists()) {
      try {
        final meta = jsonDecode(await legacyMetaFile.readAsString());
        final urls = (meta['imagePageUrls'] as List?)?.cast<String>() ?? [];
        if (urls.length >= task.pageCount) return urls;
      } catch (_) {}
    }

    final detail = await _client.fetchGalleryDetail(task.galleryUrl);
    final urls = <String>[...detail.imagePageUrls];
    if (detail.pageCount > urls.length && urls.isNotEmpty) {
      final totalPages = (detail.pageCount / urls.length).ceil();
      for (int page = 1; page < totalPages; page++) {
        final nextDetail =
            await _client.fetchGalleryDetail('${task.galleryUrl}?p=$page');
        urls.addAll(nextDetail.imagePageUrls);
      }
    }
    if (urls.isNotEmpty) {
      _saveMetadata(task, urls);
    }
    return urls;
  }

  String _galleryDir(GalleryDownloadTask task) =>
      galleryDirPath(_config.downloadDir, task.gid, task.title);

  /// Align with native [GalleryDownloadService._tryCopyImageInfosFromImageHashes]: JHenTai public hashes + old dir files.
  Future<void> _tryCopyPagesFromSupersededGallery(
    GalleryDownloadTask task,
    List<String> imagePageUrls,
  ) async {
    final oldGid = task.supersedesGid;
    if (oldGid == null) return;
    if (!effectiveGalleryUpgradeReuseImages(_config)) return;
    if (_config.jhApiSecret.isEmpty) {
      log.debug(
          'JH_JHENTAI_API_SECRET unset: skip upgrade hash reuse for gid ${task.gid}');
      return;
    }

    final jh = JhPublicClient(_config);
    final hashes =
        await jh.fetchGalleryImageHashes(gid: task.gid, token: task.token);
    if (hashes == null) return;
    if (hashes.length != imagePageUrls.length) {
      log.warning(
        'JH image hashes length ${hashes.length} != page count ${imagePageUrls.length} for gid ${task.gid}',
      );
      return;
    }

    final oldRows = db.selectGalleryImages(oldGid);
    final hashToSerial = <String, int>{};
    for (final row in oldRows) {
      final h = (row['image_hash'] as String?) ?? '';
      if (h.isEmpty) continue;
      hashToSerial.putIfAbsent(h, () => row['serial_no'] as int);
    }
    if (hashToSerial.isEmpty) {
      log.info(
        'Upgrade reuse: old gallery $oldGid has no image_hash in DB; skipped. '
        'Complete a fresh download of the old version to store per-page hashes.',
      );
      return;
    }

    final newDir = Directory(_galleryDir(task));
    await newDir.create(recursive: true);

    var copied = 0;
    for (var i = 0; i < imagePageUrls.length; i++) {
      if (task.status != GalleryDownloadStatus.downloading) return;
      final h = hashes[i];
      final oldSerial = hashToSerial[h];
      if (oldSerial == null) continue;

      final oldFile = _findExistingImage(oldGid, oldSerial);
      if (oldFile == null || !oldFile.existsSync()) continue;

      var ext = p.extension(oldFile.path).replaceFirst('.', '');
      if (ext.isEmpty) ext = 'jpg';
      final savePath = p.join(newDir.path, '$i.$ext');

      try {
        await oldFile.copy(savePath);
      } catch (e) {
        log.warning(
            'Upgrade reuse copy failed $oldGid#$oldSerial -> ${task.gid}#$i: $e');
        continue;
      }

      db.upsertGalleryImage({
        'gid': task.gid,
        'serial_no': i,
        'url': '',
        'image_url': '',
        'image_hash': h,
        'path': savePath,
        'download_status': 1,
        'image_page_url': imagePageUrls[i],
      });
      copied++;
    }
    if (copied > 0) {
      log.info(
          'Upgrade reuse: copied $copied / ${imagePageUrls.length} pages from gid $oldGid -> ${task.gid}');
    }
  }

  File? _findExistingImage(int gid, int index) {
    final task = _tasks[gid];
    final dir = Directory(task != null
        ? _galleryDir(task)
        : resolveGalleryDir(_config.downloadDir, gid) ??
            p.join(_config.downloadDir, 'gallery', '$gid'));
    if (!dir.existsSync()) return null;
    // 兼容旧版 5 位补零命名（00000.jpg）与 app 端普通命名（0.jpg）。
    final names = {index.toString().padLeft(5, '0'), index.toString()};
    try {
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => names.contains(p.basenameWithoutExtension(f.path)))
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  int _countExistingImages(Directory dir) {
    final pattern = RegExp(r'^\d+\.[^.]+$');
    try {
      return dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => pattern.hasMatch(p.basename(f.path)))
          .length;
    } catch (_) {
      return 0;
    }
  }

  void _saveMetadata(GalleryDownloadTask task, List<String> imagePageUrls) {
    // 与旧版移动端一致：文件夹 `<gid> - <标题>`，元数据文件 metadata，
    // 内容为 `{"gallery": {...}, "images": "..."}` 包裹格式，字段名沿用 app 端。
    final metaFile = File(p.join(_galleryDir(task), 'metadata'));
    metaFile.writeAsStringSync(jsonEncode({
      'gallery': {
        'gid': task.gid,
        'token': task.token,
        'title': task.title,
        'category': task.category,
        'pageCount': task.pageCount,
        'galleryUrl': task.galleryUrl,
        'oldVersionGalleryUrl': null,
        'uploader': task.uploader,
        'publishTime': task.publishTime,
        'downloadStatusIndex': task.status.index,
        'insertTime': task.insertTime,
        'downloadOriginalImage': task.downloadOriginalImage,
        'priority': task.priority,
        'sortOrder': 0,
        'groupName': task.group,
        'tags': '',
        'tagRefreshTime': null,
        // fork 扩展字段
        'coverUrl': task.coverUrl,
      },
      'images': jsonEncode([
        for (final url in imagePageUrls) {'url': url},
      ]),
    }));
  }

  String _getExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final ext = p.extension(path).replaceFirst('.', '');
      if ({'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}
          .contains(ext.toLowerCase())) {
        return ext;
      }
    } catch (_) {}
    return 'jpg';
  }

  void _notifyProgress(GalleryDownloadTask task, {String? error}) {
    final data = task.toJson();
    if (error != null) data['error'] = error;
    _eventBus.fire('gallery_download_progress', data);
  }

  String _classifyGalleryError(String error) {
    final text = error.toLowerCase();
    if (text.contains('509') || text.contains('image limit')) return 'quota';
    if (text.contains('hath.network') ||
        text.contains('proxy') ||
        text.contains('handshake') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timeout')) {
      return 'hath';
    }
    if (text.contains('image page') || text.contains('download image')) {
      return 'imagePage';
    }
    return 'unknown';
  }
}
