import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import '../network/eh_client.dart';
import '../utils/archive_util.dart';
import 'event_bus.dart';

T _safeEnum<T extends Enum>(List<T> values, int index, T fallback) {
  return (index >= 0 && index < values.length) ? values[index] : fallback;
}

enum ArchiveStatus {
  none, // 0
  unlocking, // 1
  parsingUrl, // 2
  downloading, // 3
  downloaded, // 4
  unpacking, // 5
  completed, // 6
  paused, // 7
  failed, // 8
}

class ArchiveDownloadTask {
  final int gid;
  final String token;
  final String title;
  final String category;
  final int pageCount;
  final String galleryUrl;
  final String coverUrl;
  final String uploader;
  final String size;
  final String archivePageUrl;
  final bool isOriginal;
  String group;
  int priority;
  final String insertTime;
  ArchiveStatus status;
  String downloadPageUrl;
  String downloadUrl;
  int downloadedBytes;
  int totalBytes;
  CancelToken? _cancelToken;

  ArchiveDownloadTask({
    required this.gid,
    required this.token,
    required this.title,
    required this.category,
    required this.pageCount,
    required this.galleryUrl,
    required this.coverUrl,
    required this.uploader,
    required this.size,
    required this.archivePageUrl,
    required this.isOriginal,
    this.group = 'default',
    this.priority = 0,
    required this.insertTime,
    this.status = ArchiveStatus.none,
    this.downloadPageUrl = '',
    this.downloadUrl = '',
    this.downloadedBytes = 0,
    this.totalBytes = 0,
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
    'size': size,
    'archivePageUrl': archivePageUrl,
    'isOriginal': isOriginal,
    'status': status.index,
    'downloadPageUrl': downloadPageUrl,
    'downloadUrl': downloadUrl,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'group': group,
    'group_name': group,
    'priority': priority,
    'insertTime': insertTime,
  };
}

class ArchiveDownloadService {
  final EHClient _client;
  final ServerConfig _config;
  final EventBus _eventBus;

  final Map<int, ArchiveDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};

  int get _maxConcurrent => _config.maxConcurrentArchiveDownloads;

  List<ArchiveDownloadTask> get tasks => _tasks.values.toList();

  ArchiveDownloadService(this._client, this._config, this._eventBus);

  Future<void> init() async {
    final rows = db.selectAllArchiveDownloads();
    for (final row in rows) {
      final task = ArchiveDownloadTask(
        gid: row['gid'] as int,
        token: row['token'] as String,
        title: row['title'] as String,
        category: row['category'] as String,
        pageCount: row['page_count'] as int,
        galleryUrl: row['gallery_url'] as String,
        coverUrl: row['cover_url'] as String? ?? '',
        uploader: row['uploader'] as String? ?? '',
        size: row['size'] as String? ?? '',
        archivePageUrl: row['archive_page_url'] as String? ?? '',
        isOriginal: (row['is_original'] as int? ?? 0) == 1,
        status: _safeEnum(ArchiveStatus.values, row['archive_status'] as int, ArchiveStatus.failed),
        downloadPageUrl: row['download_page_url'] as String? ?? '',
        downloadUrl: row['download_url'] as String? ?? '',
        downloadedBytes: row['downloaded_bytes'] as int? ?? 0,
        totalBytes: row['total_bytes'] as int? ?? 0,
        group: row['group_name'] as String? ?? 'default',
        priority: row['priority'] as int? ?? 0,
        insertTime: row['insert_time'] as String? ?? DateTime.now().toIso8601String(),
      );
      _tasks[task.gid] = task;
    }
    log.info('Loaded ${_tasks.length} archive download tasks');

    final activeStatuses = {
      ArchiveStatus.unlocking,
      ArchiveStatus.parsingUrl,
      ArchiveStatus.downloading,
      ArchiveStatus.downloaded,
      ArchiveStatus.unpacking,
    };
    final toResume = _tasks.values.where((t) => activeStatuses.contains(t.status)).toList();
    for (final task in toResume) {
      log.info('Resuming archive download: ${task.gid} (${task.title})');
      task.status = ArchiveStatus.unlocking;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.unlocking.index);
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
    required String archivePageUrl,
    String coverUrl = '',
    String uploader = '',
    String size = '',
    bool isOriginal = false,
    String group = 'default',
    int priority = 0,
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.status == ArchiveStatus.paused || existing.status == ArchiveStatus.failed) {
        existing.status = ArchiveStatus.unlocking;
        db.updateArchiveDownloadStatus(gid, ArchiveStatus.unlocking.index);
        _processQueue();
      }
      return;
    }

    final now = DateTime.now().toIso8601String();
    final task = ArchiveDownloadTask(
      gid: gid,
      token: token,
      title: title,
      category: category,
      pageCount: pageCount,
      galleryUrl: galleryUrl,
      coverUrl: coverUrl,
      uploader: uploader,
      size: size,
      archivePageUrl: archivePageUrl,
      isOriginal: isOriginal,
      status: ArchiveStatus.unlocking,
      group: group,
      priority: priority,
      insertTime: now,
    );

    _tasks[gid] = task;
    db.insertArchiveDownload({
      'gid': gid,
      'token': token,
      'title': title,
      'category': category,
      'page_count': pageCount,
      'gallery_url': galleryUrl,
      'cover_url': coverUrl,
      'uploader': uploader,
      'size': size,
      'publish_time': now,
      'archive_status': ArchiveStatus.unlocking.index,
      'archive_page_url': archivePageUrl,
      'is_original': isOriginal ? 1 : 0,
      'group_name': group,
      'insert_time': now,
      'priority': priority,
    });

    _notifyProgress(task);
    _processQueue();
  }

  void updateTaskMeta(int gid, {int? priority, String? group}) {
    final task = _tasks[gid];
    if (task == null) return;
    if (priority != null) {
      task.priority = priority;
      db.updateArchiveDownloadMeta(gid, priority: priority);
    }
    if (group != null) {
      task.group = group;
      db.updateArchiveDownloadMeta(gid, groupName: group);
    }
    _notifyProgress(task);
  }

  void pauseDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    task.status = ArchiveStatus.paused;
    task._cancelToken?.cancel('paused');
    _activeDownloads.remove(gid);
    db.updateArchiveDownloadStatus(gid, ArchiveStatus.paused.index);
    _notifyProgress(task);
    _processQueue();
  }

  void resumeDownload(int gid) {
    final task = _tasks[gid];
    if (task == null) return;
    if (task.status != ArchiveStatus.paused && task.status != ArchiveStatus.failed) return;
    task.status = ArchiveStatus.unlocking;
    db.updateArchiveDownloadStatus(gid, ArchiveStatus.unlocking.index);
    _notifyProgress(task);
    _processQueue();
  }

  Future<void> deleteDownload(int gid, {bool deleteFiles = true}) async {
    final task = _tasks.remove(gid);
    task?._cancelToken?.cancel('deleted');
    _activeDownloads.remove(gid);
    db.deleteArchiveDownload(gid);

    if (deleteFiles) {
      final archiveDir = Directory(_archiveDir(gid));
      if (await archiveDir.exists()) await archiveDir.delete(recursive: true);
      final zipFile = File(_archiveZipPath(gid));
      if (await zipFile.exists()) await zipFile.delete();
    }
    _eventBus.fire('download_removed', {'type': 'archive', 'gid': gid});
    _processQueue();
  }

  ArchiveDownloadTask? _nextQueuedTask() {
    final candidates = _tasks.values
        .where((t) => t.status == ArchiveStatus.unlocking && !_activeDownloads.contains(t.gid))
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

  Future<void> _doDownload(ArchiveDownloadTask task) async {
    task._cancelToken = CancelToken();
    try {
      task.status = ArchiveStatus.unlocking;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.unlocking.index);
      _notifyProgress(task);

      if (task.downloadPageUrl.isEmpty) {
        final downloadPageUrl = await _client.unlockArchive(
          task.archivePageUrl,
          isOriginal: task.isOriginal,
          cancelToken: task._cancelToken,
        );
        task.downloadPageUrl = downloadPageUrl;
        db.updateArchiveDownloadUrls(task.gid, downloadPageUrl: downloadPageUrl);
      }

      task.status = ArchiveStatus.parsingUrl;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.parsingUrl.index);
      _notifyProgress(task);

      if (task.downloadUrl.isEmpty) {
        String? downloadUrl;
        for (var i = 0; i < 10 && task.status == ArchiveStatus.parsingUrl; i++) {
          downloadUrl = await _client.parseArchiveDownloadUrl(
            task.downloadPageUrl,
            cancelToken: task._cancelToken,
          );
          if (downloadUrl != null) break;
          await Future<void>.delayed(const Duration(seconds: 3));
          cancelTokenThrowIfCancelled(task._cancelToken);
        }
        if (downloadUrl == null) {
          throw Exception('Failed to parse archive download URL');
        }
        task.downloadUrl = downloadUrl;
        db.updateArchiveDownloadUrls(task.gid, downloadUrl: downloadUrl);
      }

      task.status = ArchiveStatus.downloading;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.downloading.index);
      _notifyProgress(task);

      final zipPath = _archiveZipPath(task.gid);
      await Directory(p.dirname(zipPath)).create(recursive: true);

      await _client.downloadFile(
        task.downloadUrl,
        zipPath,
        onProgress: (received, total) {
          task.downloadedBytes = received;
          task.totalBytes = total;
          db.updateArchiveDownloadStatus(
            task.gid,
            ArchiveStatus.downloading.index,
            downloadedBytes: received,
            totalBytes: total,
          );
          _notifyProgress(task);
        },
        cancelToken: task._cancelToken,
      );

      task.status = ArchiveStatus.downloaded;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.downloaded.index);
      _notifyProgress(task);

      task.status = ArchiveStatus.unpacking;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.unpacking.index);
      _notifyProgress(task);

      final extractDir = _archiveDir(task.gid);
      await Directory(extractDir).create(recursive: true);

      final success = await extractZipArchive(zipPath, extractDir);
      if (!success) {
        throw Exception('Failed to extract archive');
      }

      try {
        await File(zipPath).delete();
      } catch (_) {}

      task.status = ArchiveStatus.completed;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.completed.index);
      _notifyProgress(task);
      log.info('Archive ${task.gid} download and extraction completed');
    } on ArchiveUnlockException catch (e) {
      log.error('Archive unlock failed for ${task.gid}: ${e.message}');
      task.status = ArchiveStatus.failed;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      log.error('Archive download failed for ${task.gid}', e);
      task.status = ArchiveStatus.failed;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } catch (e, s) {
      log.error('Archive download failed for ${task.gid}', e, s);
      task.status = ArchiveStatus.failed;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } finally {
      _activeDownloads.remove(task.gid);
      _processQueue();
    }
  }

  String _archiveDir(int gid) => p.join(_config.downloadDir, 'archive', gid.toString());
  String _archiveZipPath(int gid) => p.join(_config.tempDir, 'archive_$gid.zip');

  void _notifyProgress(ArchiveDownloadTask task) {
    _eventBus.fire('archive_download_progress', task.toJson());
  }
}
