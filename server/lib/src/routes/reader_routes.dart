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

  // ---------- 书库模型 ----------

  String _galleryId(int gid) => 'g_$gid';
  String _archiveId(int gid) => 'a_$gid';
  String _localId(String path) =>
      'l_${sha1.convert(utf8.encode(path)).toString().substring(0, 12)}';

  Map<String, dynamic> _galleryItem(GalleryDownloadTask task, String base) {
    final id = _galleryId(task.gid);
    return {
      'id': id,
      'title': task.title,
      'cover': '$base/api/reader/v1/items/$id/pages/0',
      'pageCount': task.pageCount,
      'source': 'gallery',
      'status': 'ready',
      'uploader': task.uploader,
      'galleryUrl': '$base/api/reader/v1/items/$id/pages',
      'insertTime': task.insertTime,
    };
  }

  Map<String, dynamic> _archiveItem(ArchiveDownloadTask task, String base) {
    final id = _archiveId(task.gid);
    return {
      'id': id,
      'title': task.title,
      'cover': '$base/api/reader/v1/items/$id/pages/0',
      'pageCount': task.pageCount,
      'source': 'archive',
      'status': 'ready',
      'uploader': task.uploader,
      'galleryUrl': '$base/api/reader/v1/items/$id/pages',
      'insertTime': task.insertTime,
    };
  }

  Map<String, dynamic> _localItem(LocalGallery gallery, String base) {
    final id = _localId(gallery.path);
    return {
      'id': id,
      'title': gallery.title,
      'cover': '$base/api/reader/v1/items/$id/pages/0',
      'pageCount': gallery.imageCount,
      'source': 'local',
      'status': 'ready',
      'uploader': '',
      'galleryUrl': '$base/api/reader/v1/items/$id/pages',
      'insertTime': '',
    };
  }

  Future<Response> _listItems(Request request) async {
    final source = request.url.queryParameters['source']?.trim();
    final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
    final pageSize =
        int.tryParse(request.url.queryParameters['pageSize'] ?? '') ??
            readerDefaultPageSize;
    final q = (request.url.queryParameters['q'] ?? '').trim().toLowerCase();
    final base = _baseUrl(request);

    final items = <Map<String, dynamic>>[];
    if (source == null || source == 'gallery') {
      for (final task in _galleryService.tasks) {
        if (task.status != GalleryDownloadStatus.completed) continue;
        if (q.isNotEmpty && !task.title.toLowerCase().contains(q)) continue;
        items.add(_galleryItem(task, base));
      }
    }
    if (source == null || source == 'archive') {
      for (final task in _archiveService.tasks) {
        if (task.status != ArchiveStatus.completed) continue;
        if (q.isNotEmpty && !task.title.toLowerCase().contains(q)) continue;
        items.add(_archiveItem(task, base));
      }
    }
    if (source == null || source == 'local') {
      for (final gallery in _localGalleryService.galleries) {
        if (q.isNotEmpty && !gallery.title.toLowerCase().contains(q)) continue;
        items.add(_localItem(gallery, base));
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
    final item = _findItem(id, base);
    if (item == null) return Response.notFound('{"error":"item not found"}');
    return Response.ok(
      jsonEncode(item),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Map<String, dynamic>? _findItem(String id, String base) {
    if (id.startsWith('g_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return null;
      final task = _galleryService.tasks
          .where((t) =>
              t.gid == gid && t.status == GalleryDownloadStatus.completed)
          .firstOrNull;
      return task == null ? null : _galleryItem(task, base);
    }
    if (id.startsWith('a_')) {
      final gid = int.tryParse(id.substring(2));
      if (gid == null) return null;
      final task = _archiveService.tasks
          .where((t) => t.gid == gid && t.status == ArchiveStatus.completed)
          .firstOrNull;
      return task == null ? null : _archiveItem(task, base);
    }
    if (id.startsWith('l_')) {
      for (final gallery in _localGalleryService.galleries) {
        if (_localId(gallery.path) == id) return _localItem(gallery, base);
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

  List<String> _listImageFilesInDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    try {
      final files = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => isImageFile(f.path))
          .map((f) => f.path)
          .toList();
      files.sort(naturalCompare);
      return files;
    } catch (_) {
      return const [];
    }
  }

  Future<Response> _listPages(Request request, String id) async {
    final files = _resolveImageFiles(id);
    final base = _baseUrl(request);
    return Response.ok(
      jsonEncode({
        'id': id,
        'total': files.length,
        'pages': [
          for (var i = 0; i < files.length; i++)
            {
              'index': i,
              'url': '$base/api/reader/v1/items/$id/pages/$i',
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
    return {
      'name': 'JHenTai Reader',
      'domain': base,
      'displayMode': 'collection',
      'indexUrl': '$itemsUrl?page={page:}&pageSize=$readerDefaultPageSize',
      'searchUrl':
          '$itemsUrl?q={keyword:}&page={page:}&pageSize=$readerDefaultPageSize',
      'galleryUrl': '$base/api/reader/v1/items/{idCode:}/pages',
      'headers': {'Authorization': 'Bearer $token'},
      'indexRule': {
        'item': {'selector': r'$root.items[*]'},
        'idCode': {'selector': r'$.id'},
        'title': {'selector': r'$.title'},
        'cover': {'selector': r'$.cover'},
        'totalImages': {'selector': r'$.pageCount'},
        'uploader': {'selector': r'$.uploader'},
      },
      'galleryRule': {
        'item': {'selector': r'$root.pages[*]'},
        'image': {'selector': r'$.url'},
      },
      'pages': [
        {
          'name': '全部',
          'flags': <String>[],
          'indexUrl': '$itemsUrl?page={page:}&pageSize=$readerDefaultPageSize',
          'galleryUrl': '$base/api/reader/v1/items/{idCode:}/pages',
          'relListRuleIndex': 0,
          'relGalleryRuleIndex': 0,
        }
      ],
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

  /// 轮换 reader token，返回新规则 JSON（旧二维码立即失效）。
  Future<Response> _pair(Request request) async {
    final base = _baseUrl(request);
    final token = _rotateReaderToken();
    return Response.ok(
      jsonEncode({'token': token, 'rule': _siteRuleJson(base, token)}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
