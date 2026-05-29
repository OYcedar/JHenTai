import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/web_image_client_log_stub.dart'
    if (dart.library.js_interop) 'package:jhentai/src/pages_web/web_image_client_log.dart';
import 'package:web/web.dart' as web;

typedef HtmlParser<T> = T Function(Headers headers, dynamic data);

class BackendApiClient {
  late Dio _dio;
  String _baseUrl = '';
  String? _token;

  String get baseUrl => _baseUrl;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  String? get currentToken => _token;

  BackendApiClient();

  void init({required String baseUrl, String? token}) {
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _token = token;
    // Web Docker / EH proxy: first connection or cold server can exceed 10s; reader init uses these defaults.
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    if (_token != null) {
      _applyToken(_token!);
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) {
          final code = e.response?.statusCode;
          final path = e.requestOptions.path;
          if ((code == 401 || code == 403) &&
              path.contains('/api/') &&
              !path.contains('/api/auth/token/verify')) {
            _sessionInvalidatedByServer();
          }
          handler.next(e);
        },
      ),
    );
  }

  static bool _redirectingToSetup = false;

  void _sessionInvalidatedByServer() {
    if (_redirectingToSetup) return;
    _redirectingToSetup = true;
    _token = null;
    _dio.options.headers.remove('Authorization');
    web.window.localStorage.removeItem('jh_api_token');
    Future.microtask(() {
      _redirectingToSetup = false;
      if (Get.currentRoute != '/web/setup') {
        Get.offAllNamed('/web/setup');
      }
    });
  }

  void setToken(String token) {
    _token = token;
    _applyToken(token);
  }

  void clearToken() {
    _token = null;
    _dio.options.headers.remove('Authorization');
    web.window.localStorage.removeItem('jh_api_token');
  }

  void _applyToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<bool> verifyToken(String token) async {
    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ).post(
        '/api/auth/token/verify',
        data: jsonEncode({'token': token}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return response.data['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  // --- Proxy requests through backend ---

  Future<T> proxyGet<T>({
    required String url,
    Map<String, dynamic>? queryParameters,
    HtmlParser<T>? parser,
  }) async {
    final response = await _dio.get(
      '/api/proxy/get',
      queryParameters: {'url': url, ...?queryParameters},
    );

    final result = response.data as Map<String, dynamic>;
    if (parser != null) {
      final headers = Headers();
      final rawHeaders = result['headers'] as Map<String, dynamic>?;
      rawHeaders?.forEach((key, value) {
        if (value is List) {
          headers.set(key, value.cast<String>());
        }
      });
      return parser(headers, result['data']);
    }
    return result as T;
  }

  Future<T> proxyPost<T>({
    required String url,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    String? contentType,
    HtmlParser<T>? parser,
  }) async {
    final response = await _dio.post(
      '/api/proxy/post',
      data: {
        'url': url,
        'data': data,
        'queryParams': queryParameters,
        'contentType': contentType,
      },
    );

    final result = response.data as Map<String, dynamic>;
    if (parser != null) {
      final headers = Headers();
      final rawHeaders = result['headers'] as Map<String, dynamic>?;
      rawHeaders?.forEach((key, value) {
        if (value is List) {
          headers.set(key, value.cast<String>());
        }
      });
      return parser(headers, result['data']);
    }
    return result as T;
  }

  // --- Proxy image URL for display ---

  /// Long GET URLs break some reverse proxies (414 / header buffer). Use [fetchProxiedImageBytes] when true.
  static const int proxyImageGetMaxSafeLength = 2000;

  String proxyImageUrl(String imageUrl, {int? maxBytes}) {
    return '$_baseUrl/api/proxy/image?url=${Uri.encodeComponent(imageUrl)}&token=${Uri.encodeComponent(_token ?? '')}${maxBytes != null ? '&maxBytes=$maxBytes' : ''}';
  }

  bool shouldProxyImageUsePost(String imageUrl) {
    if (imageUrl.isEmpty) return false;
    return proxyImageUrl(imageUrl).length > proxyImageGetMaxSafeLength;
  }

  Future<Uint8List> fetchProxiedImageBytes(String imageUrl,
      {int? maxBytes}) async {
    webImageClientLogVerbose(
      'POST /api/proxy/image len(url)=${imageUrl.length}',
    );
    try {
      final response = await _dio.post<List<int>>(
        '/api/proxy/image',
        queryParameters:
            _token != null && _token!.isNotEmpty ? {'token': _token} : null,
        data: jsonEncode({
          'url': imageUrl,
          if (maxBytes != null) 'maxBytes': maxBytes,
        }),
        options: Options(
          responseType: ResponseType.bytes,
          contentType: Headers.jsonContentType,
        ),
      );
      final data = response.data;
      if (data == null) {
        webImageClientLogError(
          'POST /api/proxy/image empty body status=${response.statusCode}',
        );
        return Uint8List(0);
      }
      if (data.isEmpty) {
        webImageClientLogError(
          'POST /api/proxy/image 0 bytes status=${response.statusCode}',
        );
      } else {
        webImageClientLogVerbose(
          'POST /api/proxy/image ok bytes=${data.length}',
        );
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final ct = e.response?.headers.value('content-type');
      String? bodyHint;
      final raw = e.response?.data;
      if (raw is List<int>) {
        bodyHint = String.fromCharCodes(raw.take(200));
      } else if (raw != null) {
        bodyHint = raw.toString();
        if (bodyHint.length > 200) bodyHint = '${bodyHint.substring(0, 200)}…';
      }
      webImageClientLogError(
        'POST /api/proxy/image DioException type=${e.type} status=$code contentType=$ct '
        '${e.message ?? ''} body=${bodyHint ?? 'n/a'}',
      );
      rethrow;
    }
  }

  Future<void> prefetchProxiedImage(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    if (shouldProxyImageUsePost(imageUrl)) {
      await fetchProxiedImageBytes(imageUrl);
      return;
    }
    await _dio.get<List<int>>(
      '/api/proxy/image',
      queryParameters: {
        'url': imageUrl,
        if (_token != null && _token!.isNotEmpty) 'token': _token,
      },
      options: Options(responseType: ResponseType.bytes),
    );
  }

  // --- Auth ---

  Future<Map<String, dynamic>> login(String userName, String passWord) async {
    final response = await _dio.post(
      '/api/auth/login',
      data: {'userName': userName, 'passWord': passWord},
    );
    return response.data;
  }

  Future<void> logout() async {
    await _dio.post('/api/auth/logout');
  }

  Future<Map<String, dynamic>> getAuthStatus() async {
    final response = await _dio.get('/api/auth/status');
    return response.data;
  }

  Future<void> setCookies(String cookieString) async {
    await _dio.post('/api/auth/cookies', data: {'cookies': cookieString});
  }

  Future<Map<String, dynamic>> getCookies() async {
    final response = await _dio.get('/api/auth/cookies');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<Map<String, dynamic>> refreshIgneousCookie() async {
    final response = await _dio.post('/api/auth/cookies/igneous');
    return response.data is Map
        ? Map<String, dynamic>.from(response.data)
        : {'success': true};
  }

  Future<Map<String, dynamic>> setSite(String site) async {
    final response = await _dio.put('/api/auth/site', data: {'site': site});
    return response.data is Map
        ? Map<String, dynamic>.from(response.data)
        : {'success': true};
  }

  // --- Gallery downloads ---

  Future<List<dynamic>> listGalleryDownloads() async {
    final response = await _dio.get('/api/download/gallery/list');
    return (response.data['tasks'] as List?) ?? [];
  }

  Future<void> startGalleryDownload({
    required int gid,
    required String token,
    required String title,
    required String galleryUrl,
    String category = '',
    int pageCount = 0,
    String coverUrl = '',
    String uploader = '',
    String group = 'default',
    int priority = 0,
    bool downloadOriginalImage = false,
    String tagSearchText = '',
  }) async {
    await _dio.post(
      '/api/download/gallery/start',
      data: {
        'gid': gid,
        'token': token,
        'title': title,
        'category': category,
        'pageCount': pageCount,
        'galleryUrl': galleryUrl,
        'coverUrl': coverUrl,
        'uploader': uploader,
        'group': group,
        'priority': priority,
        'downloadOriginalImage': downloadOriginalImage,
        'tagSearchText': tagSearchText,
      },
    );
  }

  Future<Map<String, dynamic>> upgradeGalleryDownload({
    required int fromGid,
    required String newerVersionUrl,
  }) async {
    final response = await _dio.post(
      '/api/download/gallery/upgrade',
      data: {'fromGid': fromGid, 'newerVersionUrl': newerVersionUrl},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<Map<String, dynamic>> restoreGalleryDownloads() async {
    final response = await _dio.post('/api/download/gallery/restore');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<void> patchGalleryDownload(
    int gid, {
    int? priority,
    String? group,
  }) async {
    final body = <String, dynamic>{};
    if (priority != null) body['priority'] = priority;
    if (group != null) body['group'] = group;
    if (body.isEmpty) return;
    await _dio.patch('/api/download/gallery/$gid', data: body);
  }

  Future<void> pauseGalleryDownload(int gid) async {
    await _dio.post('/api/download/gallery/$gid/pause');
  }

  Future<void> resumeGalleryDownload(int gid) async {
    await _dio.post('/api/download/gallery/$gid/resume');
  }

  Future<void> reDownloadGallery(int gid) async {
    await _dio.post('/api/download/gallery/$gid/redownload');
  }

  Future<void> reDownloadGalleryImage(int gid, int serialNo) async {
    await _dio.post('/api/download/gallery/$gid/image/$serialNo/redownload');
  }

  Future<void> deleteGalleryDownload(int gid, {bool deleteFiles = true}) async {
    await _dio.delete(
      '/api/download/gallery/$gid',
      queryParameters: {'deleteFiles': deleteFiles.toString()},
    );
  }

  // --- Archive downloads ---

  Future<List<dynamic>> listArchiveDownloads() async {
    final response = await _dio.get('/api/download/archive/list');
    return (response.data['tasks'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> restoreArchiveDownloads() async {
    final response = await _dio.post('/api/download/archive/restore');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<void> startArchiveDownload({
    required int gid,
    required String token,
    required String title,
    required String galleryUrl,
    required String archivePageUrl,
    String category = '',
    int pageCount = 0,
    String coverUrl = '',
    String uploader = '',
    String size = '',
    bool isOriginal = false,
    String group = 'default',
    int priority = 0,
    String tagSearchText = '',
  }) async {
    await _dio.post(
      '/api/download/archive/start',
      data: {
        'gid': gid,
        'token': token,
        'title': title,
        'category': category,
        'pageCount': pageCount,
        'galleryUrl': galleryUrl,
        'archivePageUrl': archivePageUrl,
        'coverUrl': coverUrl,
        'uploader': uploader,
        'size': size,
        'isOriginal': isOriginal,
        'group': group,
        'priority': priority,
        'tagSearchText': tagSearchText,
      },
    );
  }

  Future<void> patchArchiveDownload(
    int gid, {
    int? priority,
    String? group,
  }) async {
    final body = <String, dynamic>{};
    if (priority != null) body['priority'] = priority;
    if (group != null) body['group'] = group;
    if (body.isEmpty) return;
    await _dio.patch('/api/download/archive/$gid', data: body);
  }

  Future<void> pauseArchiveDownload(int gid) async {
    await _dio.post('/api/download/archive/$gid/pause');
  }

  Future<void> resumeArchiveDownload(int gid) async {
    await _dio.post('/api/download/archive/$gid/resume');
  }

  Future<void> reUnlockArchiveDownload(int gid) async {
    await _dio.post('/api/download/archive/$gid/reunlock');
  }

  Future<void> deleteArchiveDownload(int gid, {bool deleteFiles = true}) async {
    await _dio.delete(
      '/api/download/archive/$gid',
      queryParameters: {'deleteFiles': deleteFiles.toString()},
    );
  }

  // --- Local galleries ---

  Future<List<dynamic>> listLocalGalleries() async {
    final response = await _dio.get('/api/local/list');
    return (response.data['galleries'] as List?) ?? [];
  }

  Future<List<String>> listLocalGalleryRoots() async {
    final response = await _dio.get('/api/local/roots');
    return ((response.data['roots'] as List?) ?? []).cast<String>();
  }

  Future<void> refreshLocalGalleries() async {
    await _dio.post('/api/local/refresh');
  }

  Future<List<String>> getLocalGalleryImages(String path) async {
    final response = await _dio.get(
      '/api/local/images',
      queryParameters: {'path': path},
    );
    return ((response.data['images'] as List?) ?? []).cast<String>();
  }

  Future<void> deleteLocalGallery(String path) async {
    await _dio.delete(
      '/api/local/gallery',
      queryParameters: {'path': path},
    );
  }

  // --- Downloaded image listing ---

  Future<List<String>> getGalleryDownloadImages(int gid) async {
    final response = await _dio.get('/api/download/gallery/$gid/images');
    return ((response.data['images'] as List?) ?? []).cast<String>();
  }

  Future<List<String>> getArchiveDownloadImages(int gid) async {
    final response = await _dio.get('/api/download/archive/$gid/images');
    return ((response.data['images'] as List?) ?? []).cast<String>();
  }

  // --- Image URL helpers ---

  String galleryImageUrl(int gid, String filename) {
    return '$_baseUrl/api/image/gallery/$gid/$filename?token=${Uri.encodeComponent(_token ?? '')}';
  }

  String archiveImageUrl(int gid, String filename) {
    return '$_baseUrl/api/image/archive/$gid/$filename?token=${Uri.encodeComponent(_token ?? '')}';
  }

  String imageFileUrl(String filePath) {
    return '$_baseUrl/api/image/file?path=${Uri.encodeComponent(filePath)}&token=${Uri.encodeComponent(_token ?? '')}';
  }

  // --- Structured gallery endpoints ---

  Future<Map<String, dynamic>> fetchGalleryList({
    String section = 'home',
    String? page,

    /// EH gallery index `next=` gid (native [requestGalleryPage]).
    String? next,

    /// EH gallery index `prev=` gid.
    String? prev,
    String? search,
    Map<String, dynamic>? advancedParams,

    /// EH `inline_set`: `fs_f` (favorited time) or `fs_p` (published time). Used when [section] is `favorites`.
    String? favSort,

    /// Filter favorites list to one folder (0–9). Used when [section] is `favorites`.
    int? favcat,

    /// EH gallery index `seek=yyyy-MM-dd` date jump (native [requestGalleryPage]).
    DateTime? seek,
  }) async {
    final params = <String, dynamic>{'section': section};
    if (page != null) params['page'] = page;
    if (next != null && next.isNotEmpty) params['next'] = next;
    if (prev != null && prev.isNotEmpty) params['prev'] = prev;
    if (search != null && search.isNotEmpty) params['f_search'] = search;
    if (advancedParams != null) params.addAll(advancedParams);
    if (favSort != null && favSort.isNotEmpty) params['fav_sort'] = favSort;
    if (favcat != null) params['favcat'] = favcat;
    if (seek != null) params['seek'] = _formatEhSeekDate(seek);
    final response = await _dio.get(
      '/api/gallery/list',
      queryParameters: params,
    );
    return response.data;
  }

  static String _formatEhSeekDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  /// Detail includes `thumbnailImageUrls` and `galleryThumbnails` (per-page thumb metadata for sprites).
  Future<Map<String, dynamic>> fetchGalleryDetail(int gid, String token) async {
    try {
      final response = await _dio.get('/api/gallery/detail/$gid/$token');
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : {};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        return {'error': data['error'].toString()};
      }
      if (data is String && data.isNotEmpty) {
        try {
          final m = jsonDecode(data) as Map<String, dynamic>?;
          if (m != null && m['error'] != null) {
            return {'error': m['error'].toString()};
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchGalleryStats(int gid, String token) async {
    final response = await _dio.get('/api/gallery/stats/$gid/$token');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<List<Map<String, dynamic>>> fetchGalleryTorrents(
      int gid, String token) async {
    final response = await _dio.get('/api/gallery/torrents/$gid/$token');
    final data = response.data;
    if (data is Map && data['torrents'] is List) {
      return (data['torrents'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> fetchEhStatus() async {
    final response = await _dio.get('/api/gallery/eh-status');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<void> resetImageLimit() async {
    await _dio.post('/api/gallery/reset-image-limit');
  }

  Future<Map<String, dynamic>> fetchGalleryHHInfo(String archivePageUrl) async {
    final response = await _dio.post(
      '/api/gallery/hh-info',
      data: {'archivePageUrl': archivePageUrl},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<Map<String, dynamic>> fetchGalleryArchiveInfo(
      String archivePageUrl) async {
    final response = await _dio.post(
      '/api/gallery/archive-info',
      data: {'archivePageUrl': archivePageUrl},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<String> requestGalleryHHDownload(
      String archivePageUrl, String resolution) async {
    final response = await _dio.post(
      '/api/gallery/hh-download',
      data: {'archivePageUrl': archivePageUrl, 'resolution': resolution},
    );
    final data = response.data;
    if (data is Map) {
      return data['message']?.toString() ?? '';
    }
    return '';
  }

  Future<Map<String, dynamic>> fetchGalleryListByUrl(String url) async {
    final response = await _dio.get(
      '/api/gallery/list-by-url',
      queryParameters: {'url': url},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<String?> imageLookupBase64(
    String imageBase64, {
    String filename = 'upload.jpg',
  }) async {
    final response = await _dio.post(
      '/api/gallery/image-lookup',
      data: {'imageBase64': imageBase64, 'filename': filename},
    );
    final m =
        response.data is Map ? Map<String, dynamic>.from(response.data) : {};
    return m['redirectUrl'] as String?;
  }

  Future<Map<String, dynamic>> resolveImagePageUrl(String url) async {
    final response = await _dio.get(
      '/api/gallery/resolve-image-page',
      queryParameters: {'url': url},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<Map<String, dynamic>> listUsertags({int tagset = 1}) async {
    final response = await _dio.get(
      '/api/usertags/list',
      queryParameters: {'tagset': tagset},
    );
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<void> addUsertag({
    required String tag,
    int tagSetNo = 1,
    bool watch = true,
    bool hidden = false,
    int weight = 10,
    String tagColor = '',
  }) async {
    await _dio.post(
      '/api/usertags/add',
      data: {
        'tagSetNo': tagSetNo,
        'tag': tag,
        'watch': watch,
        'hidden': hidden,
        'weight': weight,
        'tagColor': tagColor,
      },
    );
  }

  Future<void> deleteUsertag({
    required int watchedTagId,
    int tagSetNo = 1,
  }) async {
    await _dio.post(
      '/api/usertags/delete',
      data: {'tagSetNo': tagSetNo, 'watchedTagId': watchedTagId},
    );
  }

  Future<void> updateUsertag({
    required int tagId,
    required String apikey,
    required bool watch,
    required bool hidden,
    required int weight,
    String tagColor = '',
  }) async {
    await _dio.post(
      '/api/usertags/update',
      data: {
        'tagId': tagId,
        'apikey': apikey,
        'watch': watch,
        'hidden': hidden,
        'weight': weight,
        'tagColor': tagColor,
      },
    );
  }

  Future<void> updateUsertagSet({
    required int tagSetNo,
    required bool enable,
    String? color,
  }) async {
    await _dio.post(
      '/api/usertags/tagset/update',
      data: {
        'tagSetNo': tagSetNo,
        'enable': enable,
        'color': color ?? '',
      },
    );
  }

  /// Returns `imagePageUrls`, `thumbnailImageUrls`, `galleryThumbnails` (sprite metadata), and `totalPages`.
  Future<Map<String, dynamic>> fetchGalleryImagePages(
    int gid,
    String token,
  ) async {
    final response = await _dio.get('/api/gallery/images/$gid/$token');
    return response.data as Map<String, dynamic>;
  }

  // --- Favorites ---

  Future<Map<String, dynamic>> addFavorite(
    int gid,
    String token, {
    int favcat = 0,
    String favnote = '',
  }) async {
    final response = await _dio.post(
      '/api/favorite/add',
      data: {'gid': gid, 'token': token, 'favcat': favcat, 'favnote': favnote},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> removeFavorite(int gid, String token) async {
    final response = await _dio.post(
      '/api/favorite/remove',
      data: {'gid': gid, 'token': token},
    );
    return response.data;
  }

  // --- Rating ---

  Future<Map<String, dynamic>> rateGallery({
    required int gid,
    required String token,
    required int apiuid,
    required String apikey,
    required double rating,
  }) async {
    final response = await _dio.post(
      '/api/rating/rate',
      data: {
        'gid': gid,
        'token': token,
        'apiuid': apiuid,
        'apikey': apikey,
        'rating': rating,
      },
    );
    return response.data;
  }

  // --- History ---

  Future<Map<String, dynamic>> fetchHistory({
    int limit = 50,
    int offset = 0,
    String query = '',
  }) async {
    final response = await _dio.get(
      '/api/history/list',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return response.data;
  }

  Future<void> recordHistory({
    required int gid,
    String token = '',
    String title = '',
    String coverUrl = '',
    String category = '',
  }) async {
    await _dio.post(
      '/api/history/record',
      data: {
        'gid': gid,
        'token': token,
        'title': title,
        'coverUrl': coverUrl,
        'category': category,
      },
    );
  }

  Future<void> clearHistory() async {
    await _dio.delete('/api/history/clear');
  }

  Future<void> deleteHistoryItem(int gid) async {
    await _dio.delete('/api/history/$gid');
  }

  // --- Search history ---

  Future<List<dynamic>> fetchSearchHistory({int limit = 20}) async {
    final response = await _dio.get(
      '/api/search-history/list',
      queryParameters: {'limit': limit},
    );
    return (response.data['items'] as List?) ?? [];
  }

  Future<void> recordSearchHistory(String keyword) async {
    await _dio.post('/api/search-history/record', data: {'keyword': keyword});
  }

  Future<void> clearSearchHistory() async {
    await _dio.delete('/api/search-history/clear');
  }

  Future<void> deleteSearchHistoryItem(String keyword) async {
    await _dio.delete('/api/search-history/${Uri.encodeComponent(keyword)}');
  }

  // --- Comments ---

  Future<Map<String, dynamic>> postComment({
    required int gid,
    required String token,
    required String comment,
  }) async {
    final response = await _dio.post(
      '/api/comment/post',
      data: {'gid': gid, 'token': token, 'comment': comment},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> updateComment({
    required int gid,
    required String token,
    required int commentId,
    required String comment,
  }) async {
    final response = await _dio.post(
      '/api/comment/update',
      data: {
        'gid': gid,
        'token': token,
        'commentId': commentId,
        'comment': comment,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> voteComment({
    required int gid,
    required String token,
    required int apiuid,
    required String apikey,
    required int commentId,
    required int vote,
  }) async {
    final response = await _dio.post(
      '/api/comment/vote',
      data: {
        'gid': gid,
        'token': token,
        'apiuid': apiuid,
        'apikey': apikey,
        'commentId': commentId,
        'vote': vote,
      },
    );
    return response.data;
  }

  // --- Favorite folders (names + counts per slot) ---

  Future<({List<String> names, List<int> counts})>
      fetchFavoriteFolders() async {
    final response = await _dio.get('/api/favorite/names');
    final data = response.data as Map<String, dynamic>? ?? {};
    final names =
        ((data['names'] as List?) ?? []).map((e) => e.toString()).toList();
    final countsRaw = data['counts'] as List?;
    final counts = <int>[];
    if (countsRaw != null) {
      for (final e in countsRaw) {
        counts.add(int.tryParse(e.toString()) ?? 0);
      }
    }
    while (counts.length < names.length) {
      counts.add(0);
    }
    if (names.isEmpty) {
      return (
        names: List.generate(10, (i) => 'Favorites $i'),
        counts: List.filled(10, 0),
      );
    }
    return (names: names, counts: counts);
  }

  Future<List<String>> fetchFavoriteNames() async {
    final f = await fetchFavoriteFolders();
    return f.names;
  }

  /// Current favorite note from EH add-favorite popup HTML.
  Future<String> fetchFavoriteNote(int gid, String token) async {
    final response = await _dio.get(
      '/api/favorite/popup',
      queryParameters: {'gid': gid, 'token': token},
    );
    final data = response.data as Map<String, dynamic>? ?? {};
    return data['note']?.toString() ?? '';
  }

  // --- Tag translation ---

  Future<Map<String, dynamic>> refreshTagTranslation() async {
    final response = await _dio.post('/api/tag/refresh');
    return response.data;
  }

  Future<Map<String, dynamic>> getTagTranslationStatus() async {
    final response = await _dio.get('/api/tag/status');
    return response.data;
  }

  Future<Map<String, dynamic>> refreshTagSearchOrder() async {
    final response = await _dio.post('/api/tag/order-refresh');
    return response.data;
  }

  Future<Map<String, dynamic>> getTagSearchOrderStatus() async {
    final response = await _dio.get('/api/tag/order-status');
    return response.data;
  }

  Future<Map<String, dynamic>> getTagTranslation(
      String namespace, String key) async {
    final response = await _dio.get(
      '/api/tag/translate',
      queryParameters: {'namespace': namespace, 'key': key},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, String>> translateTags(
    List<Map<String, String>> tags,
  ) async {
    final response = await _dio.post(
      '/api/tag/batch',
      data: jsonEncode({'tags': tags}),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    final translations =
        response.data['translations'] as Map<String, dynamic>? ?? {};
    return translations.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<List<dynamic>> searchTags(String query, {int limit = 20}) async {
    final response = await _dio.get(
      '/api/tag/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    return (response.data['results'] as List?) ?? [];
  }

  // --- EH events ---

  Future<Map<String, dynamic>> checkEvents() async {
    final response = await _dio.get('/api/event/check');
    return response.data as Map<String, dynamic>? ?? {};
  }

  // --- Quick search ---

  Future<List<dynamic>> listQuickSearches() async {
    final response = await _dio.get('/api/quick-search/list');
    return (response.data['items'] as List?) ?? [];
  }

  Future<void> saveQuickSearch(
    String name,
    String config, {
    int sortOrder = 0,
  }) async {
    await _dio.post(
      '/api/quick-search/save',
      data: {'name': name, 'config': config, 'sortOrder': sortOrder},
    );
  }

  Future<void> deleteQuickSearch(String name) async {
    await _dio.delete('/api/quick-search/${Uri.encodeComponent(name)}');
  }

  // --- Block rules ---

  Future<List<dynamic>> listBlockRules() async {
    final response = await _dio.get('/api/block-rule/list');
    return (response.data['rules'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> saveBlockRule({
    int? id,
    String groupId = '',
    required String target,
    required String attribute,
    required String pattern,
    required String expression,
  }) async {
    final response = await _dio.post(
      '/api/block-rule/save',
      data: {
        if (id != null) 'id': id,
        'group_id': groupId,
        'target': target,
        'attribute': attribute,
        'pattern': pattern,
        'expression': expression,
      },
    );
    return response.data;
  }

  Future<void> deleteBlockRule(int id) async {
    await _dio.delete('/api/block-rule/$id');
  }

  Future<void> deleteBlockRuleGroup(String groupId) async {
    await _dio.delete('/api/block-rule/group/${Uri.encodeComponent(groupId)}');
  }

  // --- Tag voting ---

  Future<Map<String, dynamic>> voteTag({
    required int gid,
    required String token,
    required int apiuid,
    required String apikey,
    required String namespace,
    required String tag,
    required int vote,
  }) async {
    final response = await _dio.post(
      '/api/tag/vote',
      data: {
        'gid': gid,
        'token': token,
        'apiuid': apiuid,
        'apikey': apikey,
        'namespace': namespace,
        'tag': tag,
        'vote': vote,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> addTags({
    required int gid,
    required String token,
    required int apiuid,
    required String apikey,
    required String tags,
  }) async {
    final response = await _dio.post(
      '/api/tag/add',
      data: {
        'gid': gid,
        'token': token,
        'apiuid': apiuid,
        'apikey': apikey,
        'tags': tags,
      },
    );
    return response.data;
  }

  // --- Settings ---

  static const webUseBuiltInBlockedUsersKey = 'webUseBuiltInBlockedUsers';
  static const webRestoreTasksAutomaticallyKey = 'webRestoreTasksAutomatically';

  Future<Map<String, dynamic>> getSettings() async {
    final response = await _dio.get('/api/setting/');
    return response.data;
  }

  Future<List<Map<String, dynamic>>> listProfiles() async {
    final response = await _dio.get('/api/setting/profiles');
    final data = response.data;
    if (data is Map && data['profiles'] is List) {
      return (data['profiles'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> selectProfile(int profile) async {
    await _dio.put('/api/setting/profile', data: {'profile': profile});
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _dio.put('/api/setting/', data: settings);
  }

  Future<String?> getSetting(String key) async {
    try {
      final response = await _dio.get('/api/setting/$key');
      final data = response.data as Map<String, dynamic>;
      final value = data['value'];
      if (value == null) return null;
      return value is String ? value : jsonEncode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> putSetting(String key, dynamic value) async {
    await _dio.put(
      '/api/setting/$key',
      data: jsonEncode({'value': value}),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<bool> getUseBuiltInBlockedUsers() async {
    final raw = await getSetting(webUseBuiltInBlockedUsersKey);
    if (raw == null || raw.trim().isEmpty) {
      return true;
    }
    final normalized = raw.trim().toLowerCase();
    return normalized != 'false' && normalized != '0' && normalized != 'no';
  }

  Future<void> setUseBuiltInBlockedUsers(bool value) async {
    await putSetting(webUseBuiltInBlockedUsersKey, value);
  }

  Future<bool> getRestoreTasksAutomatically() async {
    final raw = await getSetting(webRestoreTasksAutomaticallyKey);
    if (raw == null || raw.trim().isEmpty) {
      return false;
    }
    final normalized = raw.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Future<void> setRestoreTasksAutomatically(bool value) async {
    await putSetting(webRestoreTasksAutomaticallyKey, value);
  }

  Future<Map<String, dynamic>> listServerLogs() async {
    final response = await _dio.get('/api/setting/logs');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<String> readServerLog(String name) async {
    final response = await _dio.get(
      '/api/setting/logs/${Uri.encodeComponent(name)}',
    );
    final data =
        response.data is Map ? Map<String, dynamic>.from(response.data) : {};
    return data['content']?.toString() ?? '';
  }

  Future<void> clearServerLogs() async {
    await _dio.delete('/api/setting/logs');
  }

  Future<Map<String, dynamic>> getPageCacheStats() async {
    final response = await _dio.get('/api/setting/cache/page');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<void> clearPageCache() async {
    await _dio.delete('/api/setting/cache/page');
  }

  Future<Map<String, dynamic>> exportUserData() async {
    final response = await _dio.get('/api/setting/export');
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  Future<Map<String, dynamic>> importUserData(Object data) async {
    final response = await _dio.post('/api/setting/import', data: data);
    return response.data is Map ? Map<String, dynamic>.from(response.data) : {};
  }

  // --- Health ---

  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get('/api/health');
    return response.data;
  }
}

final BackendApiClient backendApiClient = BackendApiClient();
