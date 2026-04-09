import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import '../network/eh_client.dart';
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
  final String group;
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
  };
}

class GalleryDownloadService {
  final EHClient _client;
  final ServerConfig _config;
  final EventBus _eventBus;

  final Map<int, GalleryDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};
  static const int _maxConcurrent = 3;

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
      );
      _tasks[task.gid] = task;
    }
    log.info('Loaded ${_tasks.length} gallery download tasks');

    // Resume interrupted downloads
    final toResume = _tasks.values
        .where((t) => t.status == GalleryDownloadStatus.downloading)
        .toList();
    for (final task in toResume) {
      log.info('Resuming gallery download: ${task.gid} (${task.title})');
      _scheduleDownload(task);
    }
    if (toResume.isNotEmpty) {
      log.info('Resumed ${toResume.length} gallery downloads');
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
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.status == GalleryDownloadStatus.paused || existing.status == GalleryDownloadStatus.failed) {
        existing.status = GalleryDownloadStatus.downloading;
        db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.downloading.index);
        _scheduleDownload(existing);
      }
      return;
    }

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
      'publish_time': DateTime.now().toIso8601String(),
      'download_status': GalleryDownloadStatus.downloading.index,
      'group_name': group,
    });

    _notifyProgress(task);
    _scheduleDownload(task);
  }

  void pauseDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    task.status = GalleryDownloadStatus.paused;
    task._cancelToken?.cancel('paused');
    _activeDownloads.remove(gid);
    db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.paused.index);
    _notifyProgress(task);
  }

  void resumeDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    if (task.status != GalleryDownloadStatus.paused && task.status != GalleryDownloadStatus.failed) return;
    task.status = GalleryDownloadStatus.downloading;
    db.updateGalleryDownloadStatus(gid, GalleryDownloadStatus.downloading.index);
    _notifyProgress(task);
    _scheduleDownload(task);
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
  }

  void _scheduleDownload(GalleryDownloadTask task) {
    if (_activeDownloads.length >= _maxConcurrent) return;
    if (_activeDownloads.contains(task.gid)) return;
    _activeDownloads.add(task.gid);
    _doDownload(task);
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
              'image_url': imagePage.imageUrl,
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
          _notifyProgress(task);
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
      _notifyProgress(task);
    } finally {
      _activeDownloads.remove(task.gid);
      _processQueue();
    }
  }

  void _processQueue() {
    for (final task in _tasks.values) {
      if (task.status == GalleryDownloadStatus.downloading && !_activeDownloads.contains(task.gid)) {
        _scheduleDownload(task);
        if (_activeDownloads.length >= _maxConcurrent) break;
      }
    }
  }

  String _galleryDir(int gid) => p.join(_config.downloadDir, 'gallery', gid.toString());

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

  void _notifyProgress(GalleryDownloadTask task) {
    _eventBus.fire('gallery_download_progress', task.toJson());
  }
}
