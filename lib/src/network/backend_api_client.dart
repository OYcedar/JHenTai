import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

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
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _token = token;
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    if (_token != null) {
      _applyToken(_token!);
    }
  }

  void setToken(String token) {
    _token = token;
    _applyToken(token);
  }

  void _applyToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<bool> verifyToken(String token) async {
    try {
      final response = await Dio(BaseOptions(baseUrl: _baseUrl))
          .post('/api/auth/token/verify', data: jsonEncode({'token': token}),
              options: Options(headers: {'Content-Type': 'application/json'}));
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
    final response = await _dio.get('/api/proxy/get', queryParameters: {
      'url': url,
      ...?queryParameters,
    });

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
    final response = await _dio.post('/api/proxy/post', data: {
      'url': url,
      'data': data,
      'queryParams': queryParameters,
      'contentType': contentType,
    });

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

  String proxyImageUrl(String imageUrl) {
    return '$_baseUrl/api/proxy/image?url=${Uri.encodeComponent(imageUrl)}&token=${Uri.encodeComponent(_token ?? '')}';
  }

  // --- Auth ---

  Future<Map<String, dynamic>> login(String userName, String passWord) async {
    final response = await _dio.post('/api/auth/login', data: {
      'userName': userName,
      'passWord': passWord,
    });
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

  Future<void> setSite(String site) async {
    await _dio.put('/api/auth/site', data: {'site': site});
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
  }) async {
    await _dio.post('/api/download/gallery/start', data: {
      'gid': gid,
      'token': token,
      'title': title,
      'category': category,
      'pageCount': pageCount,
      'galleryUrl': galleryUrl,
      'coverUrl': coverUrl,
      'uploader': uploader,
      'group': group,
    });
  }

  Future<void> pauseGalleryDownload(int gid) async {
    await _dio.post('/api/download/gallery/$gid/pause');
  }

  Future<void> resumeGalleryDownload(int gid) async {
    await _dio.post('/api/download/gallery/$gid/resume');
  }

  Future<void> deleteGalleryDownload(int gid, {bool deleteFiles = true}) async {
    await _dio.delete('/api/download/gallery/$gid', queryParameters: {
      'deleteFiles': deleteFiles.toString(),
    });
  }

  // --- Archive downloads ---

  Future<List<dynamic>> listArchiveDownloads() async {
    final response = await _dio.get('/api/download/archive/list');
    return (response.data['tasks'] as List?) ?? [];
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
  }) async {
    await _dio.post('/api/download/archive/start', data: {
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
    });
  }

  Future<void> pauseArchiveDownload(int gid) async {
    await _dio.post('/api/download/archive/$gid/pause');
  }

  Future<void> resumeArchiveDownload(int gid) async {
    await _dio.post('/api/download/archive/$gid/resume');
  }

  Future<void> deleteArchiveDownload(int gid, {bool deleteFiles = true}) async {
    await _dio.delete('/api/download/archive/$gid', queryParameters: {
      'deleteFiles': deleteFiles.toString(),
    });
  }

  // --- Local galleries ---

  Future<List<dynamic>> listLocalGalleries() async {
    final response = await _dio.get('/api/local/list');
    return (response.data['galleries'] as List?) ?? [];
  }

  Future<void> refreshLocalGalleries() async {
    await _dio.post('/api/local/refresh');
  }

  Future<List<String>> getLocalGalleryImages(String path) async {
    final response = await _dio.get('/api/local/images', queryParameters: {'path': path});
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
    String? search,
  }) async {
    final params = <String, dynamic>{'section': section};
    if (page != null) params['page'] = page;
    if (search != null && search.isNotEmpty) params['f_search'] = search;
    final response = await _dio.get('/api/gallery/list', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> fetchGalleryDetail(int gid, String token) async {
    final response = await _dio.get('/api/gallery/detail/$gid/$token');
    return response.data;
  }

  Future<Map<String, dynamic>> fetchGalleryImagePages(int gid, String token) async {
    final response = await _dio.get('/api/gallery/images/$gid/$token');
    return response.data;
  }

  // --- Settings ---

  Future<Map<String, dynamic>> getSettings() async {
    final response = await _dio.get('/api/setting/');
    return response.data;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _dio.put('/api/setting/', data: settings);
  }

  // --- Health ---

  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get('/api/health');
    return response.data;
  }
}

final BackendApiClient backendApiClient = BackendApiClient();
