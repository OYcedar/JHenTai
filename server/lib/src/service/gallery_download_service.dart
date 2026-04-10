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
  final String insertTime;
  int? supersedesGid;
  int? supersededByGid;
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
    required this.insertTime,
    this.supersedesGid,
    this.supersededByGid,
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
    'insertTime': insertTime,
    if (supersedesGid != null) 'supersedesGid': supersedesGid,
    if (supersededByGid != null) 'supersededByGid': supersededByGid,
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

  final Map<int, GalleryDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};

  int get _maxConcurrent => _config.maxConcurrentGalleryDownloads;

  List<GalleryDownloadTask> get tasks => _tasks.values.toList();

  GalleryDownloadService(this._client, this._config, this._eventBus);

  Future<void> init() async {
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
        status: _safeEnum(GalleryDownloadStatus.values, row['download_status'] as int, GalleryDownloadStatus.failed),
        completedCount: row['completed_count'] as int? ?? 0,
        group: row['group_name'] as String? ?? 'default',
        priority: row['priority'] as int? ?? 0,
        insertTime: row['insert_time'] as String? ?? DateTime.now().toIso8601String(),
        supersedesGid: row['supersedes_gid'] as int?,
        supersededByGid: row['superseded_by_gid'] as int?,
      );
      _tasks[task.gid] = task;
    }
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
    int? supersedesGid,
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.status == GalleryDownloadStatus.paused || existing.status == GalleryDownloadStatus.failed) {
        existing.status = GalleryDownloadStatus.downloading;
        db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.downloading.index);
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
      'publish_time': now,
      'download_status': GalleryDownloadStatus.downloading.index,
      'insert_time': now,
      'group_name': group,
      'priority': priority,
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
      return (ok: false, error: 'Only completed downloads can be upgraded', newGid: null);
    }

    final resolved = newerVersionUrl.startsWith('http')
        ? newerVersionUrl
        : '${_client.baseUrl}${newerVersionUrl.startsWith('/') ? '' : '/'}$newerVersionUrl';
    final parsed = parseGalleryGidToken(resolved, _client.baseUrl);
    if (parsed == null) {
      return (ok: false, error: 'Could not parse newer gallery URL', newGid: null);
    }
    final newGid = parsed.gid;
    final newToken = parsed.token;
    if (newGid == fromGid) {
      return (ok: false, error: 'New URL points to same gallery', newGid: null);
    }
    if (_tasks.containsKey(newGid)) {
      return (ok: false, error: 'New gallery already in download list', newGid: null);
    }

    final galleryUrl = '${_client.baseUrl}/g/$newGid/$newToken/';
    GalleryDetailResult detail;
    try {
      detail = await _client.fetchGalleryDetail(galleryUrl);
    } catch (e) {
      return (ok: false, error: 'Failed to fetch new gallery: $e', newGid: null);
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
    if (task.status != GalleryDownloadStatus.paused && task.status != GalleryDownloadStatus.failed) return;
    task.status = GalleryDownloadStatus.downloading;
    db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.downloading.index);
    _notifyProgress(task);
    _processQueue();
  }

  Future<void> deleteDownload(int gid, {bool deleteFiles = true}) async {
    final task = _tasks.remove(gid);
    task?._cancelToken?.cancel('deleted');
    _activeDownloads.remove(gid);
    db.deleteGalleryDownload(gid);

    if (deleteFiles) {
      final dir = Directory(_galleryDir(gid));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    _eventBus.fire('download_removed', {'type': 'gallery', 'gid': gid});
    _processQueue();
  }

  GalleryDownloadTask? _nextQueuedTask() {
    final candidates = _tasks.values
        .where((t) => t.status == GalleryDownloadStatus.downloading && !_activeDownloads.contains(t.gid))
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
      final dir = Directory(_galleryDir(task.gid));
      await dir.create(recursive: true);

      final detail = await _client.fetchGalleryDetail(task.galleryUrl);
      List<String> imagePageUrls = detail.imagePageUrls;

      if (imagePageUrls.isEmpty) {
        log.warning('No image pages found for gallery ${task.gid}');
        task.status = GalleryDownloadStatus.failed;
        db.updateGalleryDownloadStatus(task.gid, GalleryDownloadStatus.failed.index);
        _activeDownloads.remove(task.gid);
        _notifyProgress(task);
        return;
      }

      if (detail.pageCount > imagePageUrls.length) {
        final totalPages = (detail.pageCount / imagePageUrls.length).ceil();
        for (int page = 1; page < totalPages; page++) {
          final nextDetail = await _client.fetchGalleryDetail('${task.galleryUrl}?p=$page');
          imagePageUrls.addAll(nextDetail.imagePageUrls);
        }
      }

      task.coverUrl = detail.coverUrl.isNotEmpty ? detail.coverUrl : task.coverUrl;

      _saveMetadata(task, imagePageUrls);

      await _tryCopyPagesFromSupersededGallery(task, imagePageUrls);

      for (int i = 0; i < imagePageUrls.length; i++) {
        if (task.status != GalleryDownloadStatus.downloading) break;

        final imageFile = _findExistingImage(task.gid, i);
        if (imageFile != null) {
          task.completedCount = i + 1;
          db.updateGalleryDownloadStatus(task.gid, task.status.index, completedCount: task.completedCount);
          _notifyProgress(task);
          continue;
        }

        int retries = 0;
        const maxRetries = 3;
        bool downloaded = false;

        String? reloadKey;
        while (!downloaded && retries < maxRetries && task.status == GalleryDownloadStatus.downloading) {
          try {
            task._cancelToken = CancelToken();
            var pageUrl = imagePageUrls[i];
            if (reloadKey != null) {
              final sep = pageUrl.contains('?') ? '&' : '?';
              pageUrl = '$pageUrl${sep}nl=$reloadKey';
            }
            final imagePage = await _client.fetchImagePage(pageUrl);

            if (imagePage.imageUrl.isEmpty) {
              reloadKey = imagePage.reloadKey;
              retries++;
              continue;
            }

            final ext = _getExtension(imagePage.imageUrl);
            final savePath = p.join(dir.path, '${i.toString().padLeft(5, '0')}.$ext');

            await _client.downloadFile(
              imagePage.imageUrl,
              savePath,
              cancelToken: task._cancelToken,
            );

            db.upsertGalleryImage({
              'gid': task.gid,
              'serial_no': i,
              'url': '',
              'image_url': imagePage.imageUrl,
              'image_hash': imagePage.imageHash,
              'path': savePath,
              'download_status': 1,
              'image_page_url': imagePageUrls[i],
            });

            task.completedCount = i + 1;
            db.updateGalleryDownloadStatus(task.gid, task.status.index, completedCount: task.completedCount);
            _notifyProgress(task);
            downloaded = true;
          } on DioException catch (e) {
            if (e.type == DioExceptionType.cancel) break;
            retries++;
            if (e.response?.statusCode == 509) {
              reloadKey = null;
              log.warning('Image limit (509) on image $i for gallery ${task.gid}, retrying...');
              await Future.delayed(Duration(seconds: retries * 5));
            } else {
              if (retries >= maxRetries) {
                log.warning('Failed to download image $i for gallery ${task.gid}');
              }
              await Future.delayed(Duration(seconds: retries));
            }
          } catch (e) {
            retries++;
            log.error('Error downloading image $i for gallery ${task.gid}', e);
            await Future.delayed(Duration(seconds: retries));
          }
        }

        if (!downloaded && task.status == GalleryDownloadStatus.downloading) {
          log.warning('Failed to download image $i after $maxRetries retries, marking gallery ${task.gid} as failed');
          task.status = GalleryDownloadStatus.failed;
          db.updateGalleryDownloadStatus(task.gid, GalleryDownloadStatus.failed.index);
          _notifyProgress(task, error: 'Failed to download image ${i + 1} after $maxRetries retries');
          return;
        }
      }

      if (task.status == GalleryDownloadStatus.downloading) {
        task.status = GalleryDownloadStatus.completed;
        db.updateGalleryDownloadStatus(task.gid, GalleryDownloadStatus.completed.index, completedCount: task.completedCount);
        _notifyProgress(task);
        log.info('Gallery ${task.gid} download completed');
      }
    } catch (e, s) {
      log.error('Gallery download failed for ${task.gid}', e, s);
      task.status = GalleryDownloadStatus.failed;
      db.updateGalleryDownloadStatus(task.gid, GalleryDownloadStatus.failed.index);
      _notifyProgress(task, error: '$e');
    } finally {
      _activeDownloads.remove(task.gid);
      _processQueue();
    }
  }

  String _galleryDir(int gid) => p.join(_config.downloadDir, 'gallery', gid.toString());

  /// Align with native [GalleryDownloadService._tryCopyImageInfosFromImageHashes]: JHenTai public hashes + old dir files.
  Future<void> _tryCopyPagesFromSupersededGallery(
    GalleryDownloadTask task,
    List<String> imagePageUrls,
  ) async {
    final oldGid = task.supersedesGid;
    if (oldGid == null) return;
    if (!_config.galleryUpgradeReuseImages) return;
    if (_config.jhApiSecret.isEmpty) {
      log.debug('JH_JHENTAI_API_SECRET unset: skip upgrade hash reuse for gid ${task.gid}');
      return;
    }

    final jh = JhPublicClient(_config);
    final hashes = await jh.fetchGalleryImageHashes(gid: task.gid, token: task.token);
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

    final newDir = Directory(_galleryDir(task.gid));
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
      final savePath = p.join(newDir.path, '${i.toString().padLeft(5, '0')}.$ext');

      try {
        await oldFile.copy(savePath);
      } catch (e) {
        log.warning('Upgrade reuse copy failed $oldGid#$oldSerial -> ${task.gid}#$i: $e');
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
      log.info('Upgrade reuse: copied $copied / ${imagePageUrls.length} pages from gid $oldGid -> ${task.gid}');
    }
  }

  File? _findExistingImage(int gid, int index) {
    final dir = Directory(_galleryDir(gid));
    if (!dir.existsSync()) return null;
    final prefix = index.toString().padLeft(5, '0');
    try {
      return dir.listSync()
          .whereType<File>()
          .where((f) => p.basenameWithoutExtension(f.path) == prefix)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  void _saveMetadata(GalleryDownloadTask task, List<String> imagePageUrls) {
    final metaFile = File(p.join(_galleryDir(task.gid), 'metadata.json'));
    metaFile.writeAsStringSync(jsonEncode({
      'gid': task.gid,
      'token': task.token,
      'title': task.title,
      'category': task.category,
      'pageCount': task.pageCount,
      'galleryUrl': task.galleryUrl,
      'coverUrl': task.coverUrl,
      'uploader': task.uploader,
      'imagePageUrls': imagePageUrls,
    }));
  }

  String _getExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final ext = p.extension(path).replaceFirst('.', '');
      if ({'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}.contains(ext.toLowerCase())) {
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
}
