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
import 'archive_bot_service.dart';
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

enum ArchiveParseSource {
  official,
  bot;

  static ArchiveParseSource fromValue(Object? value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    return switch (text) {
      'bot' || '1' || 'archivebot' || 'archive_bot' => ArchiveParseSource.bot,
      _ => ArchiveParseSource.official,
    };
  }

  String get label => switch (this) {
        ArchiveParseSource.official => 'Official EH archive',
        ArchiveParseSource.bot => 'Archive Bot / Archive-at-Home',
      };
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
  ArchiveParseSource parseSource;
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
    this.parseSource = ArchiveParseSource.official,
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
        'parseSource': parseSource.name,
        'parseSourceLabel': parseSource.label,
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
  final ArchiveBotService? _archiveBotService;
  final SuperResolutionService? _superResolutionService;

  final Map<int, ArchiveDownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};

  int get _maxConcurrent => effectiveMaxConcurrentArchiveDownloads(_config);

  List<ArchiveDownloadTask> get tasks => _tasks.values.toList();
  int get activeDownloadCount => _activeDownloads.length;

  ArchiveDownloadService(this._client, this._config, this._eventBus,
      {ArchiveBotService? archiveBotService,
      SuperResolutionService? superResolutionService})
      : _archiveBotService = archiveBotService,
        _superResolutionService = superResolutionService;

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

    final restored = await restoreDownloadsFromMetadata();
    if (restored > 0) {
      log.info('Restored $restored archive downloads from disk metadata');
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
        parseSource: ArchiveParseSource.fromValue(row['parse_source']),
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
    ArchiveParseSource parseSource = ArchiveParseSource.official,
  }) async {
    if (_tasks.containsKey(gid)) {
      final existing = _tasks[gid]!;
      if (existing.parseSource != parseSource &&
          existing.status != ArchiveStatus.completed) {
        await changeParseSource(gid, parseSource);
        return;
      }
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
      parseSource: parseSource,
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
      'parse_source': parseSource.name,
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

  ArchiveDownloadTask? getTask(int gid) => _tasks[gid];

  Future<bool> changeParseSource(
    int gid,
    ArchiveParseSource parseSource,
  ) async {
    final task = _tasks[gid];
    if (task == null || task.status == ArchiveStatus.completed) return false;

    task._cancelToken?.cancel('change parse source');
    _activeDownloads.remove(gid);
    task.parseSource = parseSource;
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

    db.updateArchiveDownloadMeta(gid, parseSource: parseSource.name);
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
      // 新格式 `Archive - <gid> - <标题>` 与旧格式 `archive/<gid>` 都删。
      final dirs = <String>{p.join(_config.downloadDir, 'archive', '$gid')};
      if (task != null) {
        dirs.add(_archiveDir(task));
      } else {
        final resolved = resolveArchiveDir(_config.downloadDir, gid);
        if (resolved != null) dirs.add(resolved);
      }
      for (final dirPath in dirs) {
        final archiveDir = Directory(dirPath);
        if (await archiveDir.exists()) {
          await archiveDir.delete(recursive: true);
        }
      }
      final zipFile = File(_archiveZipPath(gid));
      if (await zipFile.exists()) await zipFile.delete();
    }
    _eventBus.fire('download_removed', {'type': 'archive', 'gid': gid});
    _processQueue();
  }

  Future<int> restoreDownloadsFromMetadata() async {
    // 新格式：下载根目录下 `Archive - <gid> - <标题>` 文件夹，内含 ametadata。
    // 旧格式：`archive/<gid>` 文件夹，内含 metadata.json。两者都恢复。
    final candidates = <Directory>[];
    final root = Directory(_config.downloadDir);
    if (root.existsSync()) {
      try {
        await for (final entity in root.list(followLinks: false)) {
          if (entity is Directory &&
              RegExp(r'^Archive - \d+ - ').hasMatch(p.basename(entity.path))) {
            candidates.add(entity);
          }
        }
      } catch (e) {
        log.warning('Restore archive scan failed: ${root.path}: $e');
      }
    }
    final legacyRoot = Directory(p.join(_config.downloadDir, 'archive'));
    if (legacyRoot.existsSync()) {
      try {
        await for (final entity in legacyRoot.list(followLinks: false)) {
          if (entity is Directory) candidates.add(entity);
        }
      } catch (e) {
        log.warning('Restore archive scan failed: ${legacyRoot.path}: $e');
      }
    }

    var restored = 0;
    for (final entity in candidates) {
      final metaFile = File(p.join(entity.path, 'ametadata'));
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
            'Restore archive metadata failed: ${metaFileToUse.path}: $e');
        continue;
      }

      final gid = (meta['gid'] as num?)?.toInt() ??
          gidFromArchiveDirName(entity.path) ??
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
      final insertTime = meta['insertTime']?.toString() ??
          (await metaFileToUse.stat()).modified.toIso8601String();
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
        parseSource: ArchiveParseSource.fromValue(meta['parseSource']),
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
        'parse_source': task.parseSource.name,
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

      if (task.parseSource == ArchiveParseSource.official) {
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
      }

      task.status = ArchiveStatus.parsingUrl;
      db.updateArchiveDownloadStatus(task.gid, ArchiveStatus.parsingUrl.index);
      _notifyProgress(task);

      if (task.downloadUrl.isEmpty) {
        String? downloadUrl;
        if (task.parseSource == ArchiveParseSource.bot) {
          final archiveBotService = _archiveBotService;
          if (archiveBotService == null) {
            throw const ArchiveBotException('Archive Bot service unavailable');
          }
          downloadUrl = await archiveBotService.resolveArchiveUrl(
            gid: task.gid,
            token: task.token,
            reParse: true,
            cancelToken: task._cancelToken,
          );
        } else {
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

      final extractDir = _archiveDir(task);
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
    } on ArchiveBotException catch (e) {
      log.error('Archive Bot resolve failed for ${task.gid}: ${e.message}');
      task.status = ArchiveStatus.failed;
      task.lastError = e.message;
      task.errorCategory = 'archiveBot';
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

  String _archiveDir(ArchiveDownloadTask task) =>
      archiveDirPath(_config.downloadDir, task.gid, task.title);
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
    // 与旧版移动端一致：文件夹 `Archive - <gid> - <标题>`，元数据文件 ametadata，
    // 字段名也沿用 app 端（archiveStatusIndex/insertTime/sortOrder/groupName 等）。
    final metaFile = File(p.join(_archiveDir(task), 'ametadata'));
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
      'publishTime': task.publishTime,
      'archiveStatusIndex': _archiveStatusToAppCode(task.status),
      'archivePageUrl': task.archivePageUrl,
      'downloadPageUrl': task.downloadPageUrl,
      'downloadUrl': task.downloadUrl,
      'isOriginal': task.isOriginal,
      'insertTime': task.insertTime,
      'sortOrder': 0,
      'groupName': task.group,
      // fork 扩展字段
      'parseSource': task.parseSource.name,
      'priority': task.priority,
    }));
  }

  /// 服务端状态码转 app 端 ArchiveStatus code（10-90）。
  int _archiveStatusToAppCode(ArchiveStatus status) => switch (status) {
        ArchiveStatus.completed => 90,
        ArchiveStatus.downloaded => 70,
        ArchiveStatus.unpacking => 80,
        ArchiveStatus.parsingUrl => 50,
        ArchiveStatus.downloading => 60,
        ArchiveStatus.paused => 20,
        ArchiveStatus.failed => 10,
        ArchiveStatus.none || ArchiveStatus.unlocking => 30,
      };

  void _notifyProgress(ArchiveDownloadTask task) {
    _eventBus.fire('archive_download_progress', task.toJson());
  }

  String _classifyArchiveError(String error) {
    final text = error.toLowerCase();
    if (text.contains('509')) return 'quota';
    if (text.contains('archive bot') ||
        text.contains('archive-at-home') ||
        text.contains('archiveathome') ||
        text.contains('api key') ||
        text.contains('apikey')) {
      return 'archiveBot';
    }
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
