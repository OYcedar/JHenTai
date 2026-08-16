import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import '../service/archive_download_service.dart';
import '../service/gallery_download_service.dart';
import '../service/local_gallery_service.dart';
import '../utils/archive_util.dart';

/// Yealico 只读阅读接口。
///
/// 面向 Yealico 站点规则暴露统一的书库模型（画廊下载 / 归档下载 / 本地图库），
/// 不暴露服务器绝对路径，也不复用管理员 API Token：
/// - 数据接口使用独立的 reader token（Bearer 头或 ?token= 查询参数）；
/// - /site-rule 与 /pair 属于管理操作，使用管理员 Bearer Token。
const String readerTokenConfigKey = 'reader_token';

/// 每页默认条目数。
const int readerDefaultPageSize = 50;

class ReaderRoutes {
  final ServerConfig _config;
  final GalleryDownloadService _galleryService;
  final ArchiveDownloadService _archiveService;
  final LocalGalleryService _localGalleryService;

  ReaderRoutes(
    this._config,
    this._galleryService,
    this._archiveService,
    this._localGalleryService,
  );

  Router get router {
    final router = Router();
    router.get('/items', _listItems);
    router.get('/items/<id>', _itemDetail);
    router.get('/items/<id>/pages', _listPages);
    router.get('/items/<id>/pages/<index>', _servePageImage);
    router.get('/site-rule', _siteRule);
    router.post('/pair', _pair);
    return router;
  }

  /// 读取（必要时生成）reader token，存入数据库。
  String _ensureReaderToken() {
    final stored = db.readConfig(readerTokenConfigKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final token = _generateToken();
    db.writeConfig(readerTokenConfigKey, token);
    log.info('Generated new Yealico reader token');
    return token;
  }

  /// 轮换 reader token（旧二维码与旧规则立即失效）。
  String _rotateReaderToken() {
    final token = _generateToken();
    db.writeConfig(readerTokenConfigKey, token);
    log.info('Rotated Yealico reader token');
    return token;
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _baseUrl(Request request) {
    final scheme = request.headers['x-forwarded-proto'] ??
        (request.requestedUri.scheme.isEmpty
            ? 'http'
            : request.requestedUri.scheme);
    final host = request.headers['host'] ?? 'localhost';
    return '$scheme://$host';
  }

  String _withReaderToken(String url, String token) =>
      '$url?token=${Uri.encodeQueryComponent(token)}';

  // ---------- 书库模型 ----------

  String _galleryId(int gid) => 'g_$gid';
  String _archiveId(int gid) => 'a_$gid';
  String _localId(String path) =>
      'l_${sha1.convert(utf8.encode(path)).toString().substring(0, 12)}';

  Map<String, dynamic> _galleryItem(
      GalleryDownloadTask task, String base, String token) {
    final id = _galleryId(task.gid);
    return {
      'id': id,
      'title': task.title,
      'cover': _withReaderToken('$base/api/reader/v1/items/$id/pages/0', token),
      'pageCount': task.pageCount,
      'source': 'gallery',
      'status': 'ready',
      'uploader': task.uploader,
      'galleryUrl':
          _withReaderToken('$base/api/reader/v1/items/$id/pages', token),
      'insertTime': task.insertTime,
    };
  }

  Map<String, dynamic> _archiveItem(
      ArchiveDownloadTask task, String base, String token) {
    final id = _archiveId(task.gid);
    return {
      'id': id,
      'title': task.title,
      'cover': _withReaderToken('$base/api/reader/v1/items/$id/pages/0', token),
      'pageCount': task.pageCount,
      'source': 'archive',
      'status': 'ready',
      'uploader': task.uploader,
      'galleryUrl':
          _withReaderToken('$base/api/reader/v1/items/$id/pages', token),
      'insertTime': task.insertTime,
    };
  }

  Map<String, dynamic> _localItem(
      LocalGallery gallery, String base, String token) {
    final id = _localId(gallery.path);
    return {
      'id': id,
      'title': gallery.title,
      'cover': _withReaderToken('$base/api/reader/v1/items/$id/pages/0', token),
      'pageCount': gallery.imageCount,
      'source': 'local',
      'status': 'ready',
      'uploader': '',
      'galleryUrl':
          _withReaderToken('$base/api/reader/v1/items/$id/pages', token),
      'insertTime': '',
    };
  }

  Future<Response> _listItems(Request request) async {
    final source = request.url.queryParameters['source']?.trim();
    final page =
        max(1, int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1);
    final pageSize =
        (int.tryParse(request.url.queryParameters['pageSize'] ?? '') ??
                readerDefaultPageSize)
            .clamp(1, 200);
    final q = (request.url.queryParameters['q'] ?? '').trim().toLowerCase();
    final base = _baseUrl(request);
    final token = _ensureReaderToken();

    final items = <Map<String, dynamic>>[];
    if (source == null || source == 'gallery') {
      for (final task in _galleryService.tasks) {
        if (task.status != GalleryDownloadStatus.completed) continue;
        if (q.isNotEmpty && !task.title.toLowerCase().contains(q)) continue;
        items.add(_galleryItem(task, base, token));
      }
    }
    if (source == null || source == 'archive') {
      for (final task in _archiveService.tasks) {
        if (task.status != ArchiveStatus.completed) continue;
        if (q.isNotEmpty && !task.title.toLowerCase().contains(q)) continue;
        items.add(_archiveItem(task, base, token));
      }
    }
    if (source == null || source == 'local') {
      for (final gallery in _localGalleryService.galleries) {
        if (q.isNotEmpty && !gallery.title.toLowerCase().contains(q)) continue;
        items.add(_localItem(gallery, base, token));
      }
    }

    items.sort((a, b) =>
        (b['insertTime'] as String).compareTo(a['insertTime'] as String));

    final start = (page - 1) * pageSize;
    final pageItems = start >= items.length
        ? const <Map<String, dynamic>>[]
        : items.sublist(start, min(start + pageSize, items.length));

    return Response.ok(
      jsonEncode({
        'items': pageItems,
        'page': page,
        'pageSize': pageSize,
        'total': items.length,
        'nextPage': start + pageSize < items.length ? page + 1 : null,
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _itemDetail(Request request, String id) async {
    final base = _baseUrl(request);
    final token = _ensureReaderToken();
    final item = _findItem(id, base, token);
    if (item == null) return Response.notFound('{"error":"item not found"}');
    return Response.ok(
      jsonEncode(item),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Map<String, dynamic>? _findItem(String id, String base, String token) {
    if (id.startsWith('g_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return null;
      final task = _galleryService.tasks
          .where((t) =>
              t.gid == gid && t.status == GalleryDownloadStatus.completed)
          .firstOrNull;
      return task == null ? null : _galleryItem(task, base, token);
    }
    if (id.startsWith('a_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return null;
      final task = _archiveService.tasks
          .where((t) => t.gid == gid && t.status == ArchiveStatus.completed)
          .firstOrNull;
      return task == null ? null : _archiveItem(task, base, token);
    }
    if (id.startsWith('l_')) {
      for (final gallery in _localGalleryService.galleries) {
        if (_localId(gallery.path) == id) {
          return _localItem(gallery, base, token);
        }
      }
    }
    return null;
  }

  /// 解析资源 id 对应的图片文件列表（自然排序）。
  List<String> _resolveImageFiles(String id) {
    if (id.startsWith('g_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return const [];
      final dir = resolveGalleryDir(_config.downloadDir, gid);
      if (dir == null) return const [];
      return _listImageFilesInDir(dir);
    }
    if (id.startsWith('a_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return const [];
      final dir = resolveArchiveDir(_config.downloadDir, gid);
      if (dir == null) return const [];
      return _listImageFilesInDir(dir);
    }
    if (id.startsWith('l_')) {
      for (final gallery in _localGalleryService.galleries) {
        if (_localId(gallery.path) == id) {
          return _listImageFilesInDir(gallery.path);
        }
      }
    }
    return const [];
  }

  /// 目录图片列表缓存：按目录 mtime 失效，避免每张图片请求都重新扫描排序。
  final Map<String, _DirFilesCacheEntry> _dirFilesCache = {};

  List<String> _listImageFilesInDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    try {
      final stat = dir.statSync();
      final cached = _dirFilesCache[dirPath];
      if (cached != null &&
          cached.modified == stat.modified &&
          cached.changed == stat.changed) {
        return cached.files;
      }
      if (_dirFilesCache.length > 200) {
        _dirFilesCache.clear();
      }
      final files = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => isImageFile(f.path))
          .map((f) => f.path)
          .toList();
      files.sort(naturalCompare);
      _dirFilesCache[dirPath] = _DirFilesCacheEntry(
        modified: stat.modified,
        changed: stat.changed,
        files: files,
      );
      return files;
    } catch (_) {
      return const [];
    }
  }

  Future<Response> _listPages(Request request, String id) async {
    final files = _resolveImageFiles(id);
    final base = _baseUrl(request);
    final token = _ensureReaderToken();
    return Response.ok(
      jsonEncode({
        'id': id,
        'total': files.length,
        'pages': [
          for (var i = 0; i < files.length; i++)
            {
              'index': i,
              'url': _withReaderToken(
                  '$base/api/reader/v1/items/$id/pages/$i', token),
            }
        ],
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _servePageImage(
      Request request, String id, String index) async {
    final i = int.tryParse(index);
    if (i == null) return Response.notFound('Invalid page index');
    final files = _resolveImageFiles(id);
    if (i < 0 || i >= files.length) {
      return Response.notFound('Page not found');
    }
    final file = File(files[i]);
    if (!file.existsSync()) return Response.notFound('File not found');

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': file.lengthSync().toString(),
        'Cache-Control': 'public, max-age=86400',
      },
    );
  }

  // ---------- Yealico 规则 ----------

  Map<String, dynamic> _siteRuleJson(String base, String token) {
    final itemsUrl = '$base/api/reader/v1/items';
    final authenticatedItemsUrl = _withReaderToken(itemsUrl, token);
    return {
      'name': 'JHenTai Reader',
      'domain': base,
      'displayMode': 'collection',
      'indexUrl':
          '$authenticatedItemsUrl&page={page:}&pageSize=$readerDefaultPageSize',
      'searchUrl':
          '$authenticatedItemsUrl&q={keyword:}&page={page:}&pageSize=$readerDefaultPageSize',
      'detailUrl': _withReaderToken('$itemsUrl/{idCode:}', token),
      'galleryUrl': _withReaderToken('$itemsUrl/{idCode:}/pages', token),
      'headers': {'Authorization': 'Bearer $token'},
      'indexRule': {
        'item': {'selector': r'$root.items[*]'},
        'idCode': {'selector': r'$.id'},
        'title': {'selector': r'$.title'},
        'cover': {'selector': r'$.cover'},
        'totalImages': {'selector': r'$.pageCount'},
        'uploader': {'selector': r'$.uploader'},
      },
      'detailRule': {
        'title': {'selector': r'$.title'},
        'cover': {'selector': r'$.cover'},
        'totalImages': {'selector': r'$.pageCount'},
        'uploader': {'selector': r'$.uploader'},
      },
      'galleryRule': {
        'item': {'selector': r'$root.pages[*]'},
        'image': {'selector': r'$.url'},
      },
    };
  }

  Future<Response> _siteRule(Request request) async {
    final base = _baseUrl(request);
    final token = _ensureReaderToken();
    return Response.ok(
      jsonEncode(_siteRuleJson(base, token)),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// 轮换 reader token，返回新规则 JSON（旧规则立即失效）。
  Future<Response> _pair(Request request) async {
    final base = _baseUrl(request);
    final token = _rotateReaderToken();
    return Response.ok(
      jsonEncode({'token': token, 'rule': _siteRuleJson(base, token)}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}

class _DirFilesCacheEntry {
  _DirFilesCacheEntry({
    required this.modified,
    required this.changed,
    required this.files,
  });

  final DateTime modified;
  final DateTime changed;
  final List<String> files;
}
