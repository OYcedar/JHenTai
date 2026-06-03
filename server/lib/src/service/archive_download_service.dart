import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import '../network/eh_client.dart';
import '../utils/archive_util.dart';
import 'download_runtime_settings.dart';
import 'event_bus.dart';
import 'super_resolution_service.dart';

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
  final String tagSearchText;
  final String publishTime;
  final String insertTime;
  ArchiveStatus status;
  String downloadPageUrl;
  String downloadUrl;
  int downloadedBytes;
  int totalBytes;
  String lastError;
  String errorCategory;
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
    this.tagSearchText = '',
    required this.publishTime,
    required this.insertTime,
    this.status = ArchiveStatus.none,
    this.downloadPageUrl = '',
    this.downloadUrl = '',
    this.downloadedBytes = 0,
    this.totalBytes = 0,
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
        'tagSearchText': tagSearchText,
        'tag_search_text': tagSearchText,
        'publishTime': publishTime,
        'publish_time': publishTime,
        'insertTime': insertTime,
        if (lastError.isNotEmpty) 'lastError': lastError,
        if (errorCategory.isNotEmpty) 'errorCategory': errorCategory,
      };
}

class ArchiveDownloadService {
  final EHClient _client;
  final ServerConfig _config;
  final EventBus _eventBus;
  final SuperResolutionService? _superResolutionService;

  final Map<int, ArchiveDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};

  int get _maxConcurrent => effectiveMaxConcurrentArchiveDownloads(_config);

  List<ArchiveDownloadTask> get tasks => _tasks.values.toList();
  int get activeDownloadCount => _activeDownloads.length;

  ArchiveDownloadService(this._client, this._config, this._eventBus,
      {SuperResolutionService? superResolutionService})
      : _superResolutionService = superResolutionService;

  Future<void> init() async {
    _loadTasksFromDatabase();
    log.info('Loaded ${_tasks.length} archive download tasks');

    final activeStatuses = {
      ArchiveStatus.unlocking,
      ArchiveStatus.parsingUrl,
      ArchiveStatus.downloading,
      ArchiveStatus.downloaded,
      ArchiveStatus.unpacking,
    };
    final toResume =
        _tasks.values.where((t) => activeStatuses.contains(t.status)).toList();
    for (final task in toResume) {
      log.info('Resuming archive download: ${task.gid} (${task.title})');
      task.status = ArchiveStatus.unlocking;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.unlocking.index);
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
    log.info('Reloaded ${_tasks.length} archive download tasks');
  }

  void _loadTasksFromDatabase() {
    _tasks.clear();
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
        status: _safeEnum(ArchiveStatus.values, row['archive_status'] as int,
            ArchiveStatus.failed),
        downloadPageUrl: row['download_page_url'] as String? ?? '',
        downloadUrl: row['download_url'] as String? ?? '',
        downloadedBytes: row['downloaded_bytes'] as int? ?? 0,
        totalBytes: row['total_bytes'] as int? ?? 0,
        group: row['group_name'] as String? ?? 'default',
        priority: row['priority'] as int? ?? 0,
        tagSearchText: row['tag_search_text'] as String? ?? '',
        publishTime: row['publish_time'] as String? ?? '',
        insertTime:
            row['insert_time'] as String? ?? DateTime.now().toIso8601String(),
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
    required String archivePageUrl,
    String coverUrl = '',
    String uploader = '',
    String size = '',
    bool isOriginal = false,
    String group = 'default',
    int priority = 0,
    String tagSearchText = '',
    String? publishTime,
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.status == ArchiveStatus.paused ||
          existing.status == ArchiveStatus.failed) {
        existing.status = ArchiveStatus.unlocking;
        existing.lastError = '';
        existing.errorCategory = '';
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
      tagSearchText: tagSearchText,
      publishTime:
          publishTime != null && publishTime.isNotEmpty ? publishTime : now,
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
      'publish_time':
          publishTime != null && publishTime.isNotEmpty ? publishTime : now,
      'archive_status': ArchiveStatus.unlocking.index,
      'archive_page_url': archivePageUrl,
      'is_original': isOriginal ? 1 : 0,
      'group_name': group,
      'insert_time': now,
      'priority': priority,
      'tag_search_text': tagSearchText,
    });
    _saveMetadata(task);

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
    if (task.status != ArchiveStatus.paused &&
        task.status != ArchiveStatus.failed) return;
    task.status = ArchiveStatus.unlocking;
    task.lastError = '';
    task.errorCategory = '';
    db.updateArchiveDownloadStatus(gid, ArchiveStatus.unlocking.index);
    _notifyProgress(task);
    _processQueue();
  }

  Future<bool> reUnlock(int gid) async {
    final task = _tasks[gid];
    if (task == null) return false;

    task._cancelToken?.cancel('reunlock');
    _activeDownloads.remove(gid);
    task.status = ArchiveStatus.unlocking;
    task.lastError = '';
    task.errorCategory = '';
    task.downloadPageUrl = '';
    task.downloadUrl = '';
    task.downloadedBytes = 0;
    task.totalBytes = 0;

    final zipFile = File(_archiveZipPath(gid));
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    db.updateArchiveDownloadUrls(gid, downloadPageUrl: '', downloadUrl: '');
    db.updateArchiveDownloadStatus(
      gid,
      ArchiveStatus.unlocking.index,
      downloadedBytes: 0,
      totalBytes: 0,
    );
    _saveMetadata(task);
    _notifyProgress(task);
    _processQueue();
    return true;
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

  Future<int> restoreDownloadsFromMetadata() async {
    final root = Directory(p.join(_config.downloadDir, 'archive'));
    if (!await root.exists()) return 0;

    var restored = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final metaFile = File(p.join(entity.path, 'metadata.json'));
      if (!await metaFile.exists()) continue;

      Map<String, dynamic> meta;
      try {
        final decoded = jsonDecode(await metaFile.readAsString());
        if (decoded is! Map) continue;
        meta = decoded.cast<String, dynamic>();
      } catch (e) {
        log.warning('Restore archive metadata failed: ${metaFile.path}: $e');
        continue;
      }

      final gid = (meta['gid'] as num?)?.toInt() ??
          int.tryParse(p.basename(entity.path));
      if (gid == null || _tasks.containsKey(gid)) continue;

      final token = meta['token']?.toString() ?? '';
      final title = meta['title']?.toString() ?? '';
      final galleryUrl = meta['galleryUrl']?.toString() ?? '';
      final archivePageUrl = meta['archivePageUrl']?.toString() ?? '';
      if (token.isEmpty ||
          title.isEmpty ||
          galleryUrl.isEmpty ||
          archivePageUrl.isEmpty) {
        continue;
      }

      final hasImages = _hasExtractedImages(entity);
      final insertTime = (await metaFile.stat()).modified.toIso8601String();
      final task = ArchiveDownloadTask(
        gid: gid,
        token: token,
        title: title,
        category: meta['category']?.toString() ?? '',
        pageCount: (meta['pageCount'] as num?)?.toInt() ?? 0,
        galleryUrl: galleryUrl,
        coverUrl: meta['coverUrl']?.toString() ?? '',
        uploader: meta['uploader']?.toString() ?? '',
        size: meta['size']?.toString() ?? '',
        archivePageUrl: archivePageUrl,
        isOriginal: meta['isOriginal'] as bool? ?? false,
        group: meta['group']?.toString() ??
            meta['groupName']?.toString() ??
            'default',
        priority: (meta['priority'] as num?)?.toInt() ?? 0,
        publishTime: meta['publishTime']?.toString() ??
            meta['publish_time']?.toString() ??
            insertTime,
        insertTime: insertTime,
        status: hasImages ? ArchiveStatus.completed : ArchiveStatus.paused,
        downloadPageUrl: meta['downloadPageUrl']?.toString() ?? '',
        downloadUrl: meta['downloadUrl']?.toString() ?? '',
      );

      _tasks[gid] = task;
      db.insertArchiveDownload({
        'gid': gid,
        'token': token,
        'title': title,
        'category': task.category,
        'page_count': task.pageCount,
        'gallery_url': galleryUrl,
        'cover_url': task.coverUrl,
        'uploader': task.uploader,
        'size': task.size,
        'publish_time': task.publishTime,
        'archive_status': task.status.index,
        'archive_page_url': archivePageUrl,
        'download_page_url': task.downloadPageUrl,
        'download_url': task.downloadUrl,
        'is_original': task.isOriginal ? 1 : 0,
        'group_name': task.group,
        'insert_time': insertTime,
        'priority': task.priority,
      });

      restored++;
      _notifyProgress(task);
    }

    if (restored > 0) _processQueue();
    return restored;
  }

  ArchiveDownloadTask? _nextQueuedTask() {
    final candidates = _tasks.values
        .where((t) =>
            t.status == ArchiveStatus.unlocking &&
            !_activeDownloads.contains(t.gid))
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
        db.updateArchiveDownloadUrls(task.gid,
            downloadPageUrl: downloadPageUrl);
        _saveMetadata(task);
      }

      task.status = ArchiveStatus.parsingUrl;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.parsingUrl.index);
      _notifyProgress(task);

      if (task.downloadUrl.isEmpty) {
        String? downloadUrl;
        for (var i = 0;
            i < 10 && task.status == ArchiveStatus.parsingUrl;
            i++) {
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
        _saveMetadata(task);
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

      if (effectiveDeleteArchiveFileAfterDownload()) {
        try {
          await File(zipPath).delete();
        } catch (_) {}
      }

      task.status = ArchiveStatus.completed;
      task.lastError = '';
      task.errorCategory = '';
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.completed.index);
      _saveMetadata(task);
      _notifyProgress(task);
      log.info('Archive ${task.gid} download and extraction completed');
      final superResolutionService = _superResolutionService;
      if (superResolutionService != null) {
        unawaited(superResolutionService.createJobIfAutoEnabled(
            sourceType: 'archive', gid: task.gid));
      }
    } on ArchiveUnlockException catch (e) {
      log.error('Archive unlock failed for ${task.gid}: ${e.message}');
      task.status = ArchiveStatus.failed;
      task.lastError = e.message;
      task.errorCategory = 'archiveUnlock';
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      log.error('Archive download failed for ${task.gid}', e);
      task.status = ArchiveStatus.failed;
      task.lastError = '$e';
      task.errorCategory = _classifyArchiveError('$e');
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } catch (e, s) {
      log.error('Archive download failed for ${task.gid}', e, s);
      task.status = ArchiveStatus.failed;
      task.lastError = '$e';
      task.errorCategory = _classifyArchiveError('$e');
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.failed.index);
      _notifyProgress(task);
    } finally {
      _activeDownloads.remove(task.gid);
      _processQueue();
    }
  }

  String _archiveDir(int gid) =>
      p.join(_config.downloadDir, 'archive', gid.toString());
  String _archiveZipPath(int gid) =>
      p.join(_config.tempDir, 'archive_$gid.zip');

  bool _hasExtractedImages(Directory dir) {
    try {
      return dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .any((f) => isImageFile(f.path));
    } catch (_) {
      return false;
    }
  }

  void _saveMetadata(ArchiveDownloadTask task) {
    final metaFile = File(p.join(_archiveDir(task.gid), 'metadata.json'));
    metaFile.parent.createSync(recursive: true);
    metaFile.writeAsStringSync(jsonEncode({
      'gid': task.gid,
      'token': task.token,
      'title': task.title,
      'category': task.category,
      'pageCount': task.pageCount,
      'galleryUrl': task.galleryUrl,
      'coverUrl': task.coverUrl,
      'uploader': task.uploader,
      'size': task.size,
      'archivePageUrl': task.archivePageUrl,
      'isOriginal': task.isOriginal,
      'group': task.group,
      'priority': task.priority,
      'publishTime': task.publishTime,
      'downloadPageUrl': task.downloadPageUrl,
      'downloadUrl': task.downloadUrl,
    }));
  }

  void _notifyProgress(ArchiveDownloadTask task) {
    _eventBus.fire('archive_download_progress', task.toJson());
  }

  String _classifyArchiveError(String error) {
    final text = error.toLowerCase();
    if (text.contains('509')) return 'quota';
    if (text.contains('unlock')) return 'archiveUnlock';
    if (text.contains('hath.network') ||
        text.contains('proxy') ||
        text.contains('handshake') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timeout')) {
      return 'hath';
    }
    if (text.contains('extract') ||
        text.contains('zip') ||
        text.contains('archive')) {
      return 'archiveDownload';
    }
    return 'unknown';
  }
}
