import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/log.dart';
import 'cookie_manager.dart';

class EHClient {
  late Dio _dio;
  late ServerCookieManager cookieManager;

  String _site = 'EH';

  String get site => _site;
  set site(String s) => _site = s;

  String get baseUrl => _site == 'EX' ? 'https://exhentai.org' : 'https://e-hentai.org';
  String get apiUrl => _site == 'EX' ? 'https://exhentai.org/api.php' : 'https://api.e-hentai.org/api.php';

  static const String ehForums = 'https://forums.e-hentai.org/index.php';

  Future<void> init(ServerCookieManager cm, {int connectTimeout = 6000, int receiveTimeout = 6000}) async {
    cookieManager = cm;
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(milliseconds: connectTimeout),
      receiveTimeout: Duration(milliseconds: receiveTimeout),
    ));
    _dio.interceptors.add(cookieManager);
    _dio.interceptors.add(_ErrorInterceptor());
  }

  // --- Raw proxy for frontend ---

  Future<Map<String, dynamic>> proxyGet(String url, {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dio.get(url, queryParameters: queryParams);
      return _wrapResponse(response);
    } on DioException catch (e) {
      return _wrapError(e);
    }
  }

  Future<Map<String, dynamic>> proxyPost(String url, {dynamic data, Map<String, dynamic>? queryParams, String? contentType}) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        queryParameters: queryParams,
        options: contentType != null ? Options(contentType: contentType) : null,
      );
      return _wrapResponse(response);
    } on DioException catch (e) {
      return _wrapError(e);
    }
  }

  // --- Login ---

  Future<Map<String, dynamic>> login(String userName, String passWord) async {
    try {
      // Disable redirect-following so we can capture Set-Cookie from the 302
      final response = await _dio.post(
        ehForums,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
        queryParameters: {'act': 'Login', 'CODE': '01'},
        data: {
          'referer': 'https://forums.e-hentai.org/index.php?',
          'b': '', 'bt': '',
          'UserName': userName,
          'PassWord': passWord,
          'CookieDate': 365,
        },
      );

      final setCookies = response.headers['set-cookie'];
      if (setCookies != null && setCookies.length > 2) {
        final idMatch = RegExp(r'ipb_member_id=(\d+);')
            .firstMatch(setCookies.firstWhere((h) => h.contains('ipb_member_id'), orElse: () => ''));
        final hashMatch = RegExp(r'ipb_pass_hash=(\w+);')
            .firstMatch(setCookies.firstWhere((h) => h.contains('ipb_pass_hash'), orElse: () => ''));
        if (idMatch != null && hashMatch != null) {
          // Manually store the login cookies since the interceptor only
          // fires after the response is fully processed.
          final parsed = setCookies
              .map(Cookie.fromSetCookieValue)
              .map((c) => Cookie(c.name, c.value))
              .toList();
          await cookieManager.storeCookies(parsed);

          return {
            'success': true,
            'ipbMemberId': int.parse(idMatch.group(1)!),
            'ipbPassHash': hashMatch.group(1)!,
          };
        }
      }

      final body = response.data.toString();
      final doc = html_parser.parse(body);
      final errorMsg = doc.querySelector('.message')?.text ?? 'Login failed';
      return {'success': false, 'message': errorMsg};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Network error'};
    }
  }

  Future<void> logout() async {
    await cookieManager.removeAllCookies();
  }

  // --- Gallery detail parsing (for downloads) ---

  Future<GalleryDetailResult> fetchGalleryDetail(String galleryUrl) async {
    final response = await _dio.get(galleryUrl, queryParameters: {'hc': 1});
    final body = response.data.toString();
    return _parseGalleryDetail(body, galleryUrl);
  }

  Future<ImagePageResult> fetchImagePage(String imagePageUrl) async {
    final response = await _dio.get(imagePageUrl);
    final body = response.data.toString();
    return _parseImagePage(body);
  }

  Future<Response> downloadFile(String url, String savePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    return _dio.download(url, savePath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<List<int>> downloadBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? [];
  }

  // --- Archive operations ---

  Future<String?> unlockArchive(String archiverUrl, {required bool isOriginal}) async {
    final response = await _dio.post(
      archiverUrl,
      data: FormData.fromMap({
        'dltype': isOriginal ? 'org' : 'res',
        'dlcheck': isOriginal ? 'Download Original Archive' : 'Download Resample Archive',
      }),
    );

    final body = response.data.toString();
    final doc = html_parser.parse(body);

    final continueLink = doc.querySelector('#continue a')?.attributes['href'];
    if (continueLink != null) return continueLink;

    final onClickAttr = doc.querySelector('#continue input')?.attributes['onclick'];
    if (onClickAttr != null) {
      final urlMatch = RegExp(r"document\.location\s*=\s*'([^']+)'").firstMatch(onClickAttr);
      if (urlMatch != null) return urlMatch.group(1);
    }

    return null;
  }

  Future<String?> parseArchiveDownloadUrl(String downloadPageUrl) async {
    final response = await _dio.get(downloadPageUrl);
    final body = response.data.toString();
    final doc = html_parser.parse(body);

    final archiveLink = doc.querySelector('#db a')?.attributes['href'];
    return archiveLink;
  }

  // --- Favorites ---

  Future<Map<String, dynamic>> addFavorite(int gid, String token, {int favcat = 0, String favnote = ''}) async {
    try {
      await _dio.post(
        '$baseUrl/gallerypopups.php',
        queryParameters: {'gid': gid, 't': token, 'act': 'addfav'},
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {'favcat': favcat.toString(), 'favnote': favnote, 'apply': 'Add to Favorites', 'update': '1'},
      );
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to add favorite'};
    }
  }

  Future<Map<String, dynamic>> removeFavorite(int gid, String token) async {
    try {
      await _dio.post(
        '$baseUrl/gallerypopups.php',
        queryParameters: {'gid': gid, 't': token, 'act': 'addfav'},
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {'favcat': 'favdel', 'favnote': '', 'apply': 'Apply Changes', 'update': '1'},
      );
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to remove favorite'};
    }
  }

  // --- Comments ---

  Future<Map<String, dynamic>> postComment(int gid, String token, String comment) async {
    try {
      await _dio.post(
        '$baseUrl/g/$gid/$token/',
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {'commenttext_new': comment},
      );
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to post comment'};
    }
  }

  Future<Map<String, dynamic>> voteComment(int apiuid, String apikey, int gid, String token, int commentId, int vote) async {
    try {
      final response = await _dio.post(
        apiUrl,
        options: Options(contentType: Headers.jsonContentType),
        data: {
          'method': 'votecomment',
          'apiuid': apiuid,
          'apikey': apikey,
          'gid': gid,
          'token': token,
          'comment_id': commentId,
          'comment_vote': vote,
        },
      );
      return response.data is Map ? Map<String, dynamic>.from(response.data) : {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to vote'};
    }
  }

  // --- Favorite names ---

  Future<List<String>> fetchFavoriteNames() async {
    try {
      final response = await _dio.get('$baseUrl/favorites.php');
      final body = response.data.toString();
      final doc = html_parser.parse(body);
      final options = doc.querySelectorAll('.fp a.i');
      if (options.length >= 10) {
        return options.take(10).map((e) => e.text.trim()).toList();
      }
      final inputs = doc.querySelectorAll('input[name^="favorite_"]');
      if (inputs.length >= 10) {
        return inputs.take(10).map((e) => e.attributes['value'] ?? 'Favorites ${inputs.indexOf(e)}').toList();
      }
      return List.generate(10, (i) => 'Favorites $i');
    } catch (_) {
      return List.generate(10, (i) => 'Favorites $i');
    }
  }

  // --- Rating ---

  Future<Map<String, dynamic>> rateGallery(int gid, String token, int apiuid, String apikey, double rating) async {
    try {
      final response = await _dio.post(
        apiUrl,
        options: Options(contentType: Headers.jsonContentType),
        data: {
          'method': 'rategallery',
          'apiuid': apiuid,
          'apikey': apikey,
          'gid': gid,
          'token': token,
          'rating': (rating * 2).round(),
        },
      );
      return response.data is Map ? Map<String, dynamic>.from(response.data) : {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to rate'};
    }
  }

  // --- Tag voting ---

  Future<Map<String, dynamic>> voteTag({
    required int apiuid,
    required String apikey,
    required int gid,
    required String token,
    required String namespace,
    required String tag,
    required int vote,
  }) async {
    try {
      final response = await _dio.post(
        apiUrl,
        options: Options(contentType: Headers.jsonContentType),
        data: {
          'method': 'taggallery',
          'apiuid': apiuid,
          'apikey': apikey,
          'gid': gid,
          'token': token,
          'tags': '$namespace:$tag',
          'vote': vote,
        },
      );
      return response.data is Map ? Map<String, dynamic>.from(response.data) : {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': e.message ?? 'Failed to vote tag'};
    }
  }

  // --- Gallery API ---

  Future<Map<String, dynamic>> fetchGalleryMetadata(int gid, String token) async {
    final response = await _dio.post(
      apiUrl,
      options: Options(contentType: Headers.jsonContentType),
      data: {
        'method': 'gdata',
        'gidlist': [[gid, token]],
        'namespace': 1,
      },
    );
    return response.data is Map ? response.data : {};
  }

  // --- HTML parsers ---

  GalleryDetailResult _parseGalleryDetail(String html, String galleryUrl) {
    final doc = html_parser.parse(html);
    final result = GalleryDetailResult();

    result.title = doc.querySelector('#gn')?.text ?? '';
    result.titleJpn = doc.querySelector('#gj')?.text ?? '';
    result.category = doc.querySelector('#gdc .cs')?.text ?? doc.querySelector('#gdc .ct')?.text ?? '';
    result.uploader = doc.querySelector('#gdn a')?.text ?? '';

    final coverStyle = doc.querySelector('#gd1 div')?.attributes['style'] ?? '';
    final coverMatch = RegExp(r'url\(([^)]+)\)').firstMatch(coverStyle);
    result.coverUrl = coverMatch?.group(1) ?? '';

    final ratingText = doc.querySelector('#rating_label')?.text ?? '';
    final ratingMatch = RegExp(r'[\d.]+').firstMatch(ratingText);
    result.rating = double.tryParse(ratingMatch?.group(0) ?? '') ?? 0;

    final pageCountText = doc.querySelector('#gdd .gdt2')?.text ?? '';
    final pageMatch = RegExp(r'(\d+) pages').firstMatch(pageCountText);
    result.pageCount = int.tryParse(pageMatch?.group(1) ?? '') ?? 0;

    final archiveLink = doc.querySelector('a[onclick*="archiver"]')?.attributes['onclick'];
    if (archiveLink != null) {
      final urlMatch = RegExp(r"'(https?://[^']+)'").firstMatch(archiveLink);
      result.archiverUrl = urlMatch?.group(1);
    }

    // Parse tags grouped by namespace (#taglist tr)
    for (final tr in doc.querySelectorAll('#taglist tr')) {
      final tdNamespace = tr.querySelector('td.tc');
      final namespace = tdNamespace?.text.replaceAll(':', '').trim() ?? 'misc';
      final tagElements = tr.querySelectorAll('td:not(.tc) a, td:not(.tc) div a');
      final tagValues = tagElements.map((a) => a.text.trim()).where((t) => t.isNotEmpty).toList();
      if (tagValues.isNotEmpty) {
        result.tags[namespace] = tagValues;
      }
    }

    // Parse apiuid / apikey from inline script
    for (final script in doc.querySelectorAll('script')) {
      final text = script.text;
      final uidMatch = RegExp(r'var apiuid\s*=\s*(\d+)').firstMatch(text);
      final keyMatch = RegExp(r'var apikey\s*=\s*"(\w+)"').firstMatch(text);
      if (uidMatch != null) result.apiuid = int.tryParse(uidMatch.group(1)!);
      if (keyMatch != null) result.apikey = keyMatch.group(1);
    }

    // Parse favorite status
    final favDiv = doc.querySelector('#fav .i');
    if (favDiv != null) {
      final style = favDiv.attributes['style'] ?? '';
      final posMatch = RegExp(r'background-position:0px -(\d+)px').firstMatch(style);
      if (posMatch != null) {
        final yOffset = int.tryParse(posMatch.group(1)!) ?? 0;
        result.favoriteSlot = yOffset ~/ 19;
      }
    }
    final favName = doc.querySelector('#fav .fn')?.text;
    if (favName != null && favName.isNotEmpty) {
      result.favoriteName = favName;
    }

    // Parse comments
    for (final c in doc.querySelectorAll('#cdiv .c1')) {
      final header = c.querySelector('.c3')?.text ?? '';
      final authorEl = c.querySelector('.c3 a');
      final author = authorEl?.text ?? 'Anonymous';
      final dateMatch = RegExp(r'Posted on (.+?) by').firstMatch(header);
      final date = dateMatch?.group(1) ?? '';
      final scoreEl = c.querySelector('.c5 span');
      final score = scoreEl?.text ?? '';
      final bodyEl = c.querySelector('.c6');
      final body = bodyEl?.innerHtml ?? '';
      final idAttr = c.parent?.attributes['id'] ?? '';
      final commentId = RegExp(r'comment_(\d+)').firstMatch(idAttr)?.group(1) ?? '';

      result.comments.add({
        'id': commentId,
        'author': author,
        'date': date,
        'score': score,
        'body': body,
      });
    }

    result.thumbnailUrls = doc.querySelectorAll('#gdt a')
        .map((a) => a.attributes['href'] ?? '')
        .where((href) => href.isNotEmpty)
        .toList();

    final pageLinks = doc.querySelectorAll('.gdtl a, .gdtm a');
    for (final a in pageLinks) {
      final href = a.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        result.imagePageUrls.add(href);
      }
    }

    if (result.imagePageUrls.isEmpty) {
      for (final a in doc.querySelectorAll('#gdt a')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('/s/')) {
          result.imagePageUrls.add(href);
        }
      }
    }

    return result;
  }

  ImagePageResult _parseImagePage(String html) {
    final doc = html_parser.parse(html);
    final result = ImagePageResult();

    final imgElement = doc.querySelector('#img');
    result.imageUrl = imgElement?.attributes['src'] ?? '';

    final nl = doc.querySelector('#loadfail')?.attributes['onclick'];
    if (nl != null) {
      final nlMatch = RegExp(r"nl\('([^']+)'\)").firstMatch(nl);
      result.reloadKey = nlMatch?.group(1);
    }

    return result;
  }

  Map<String, dynamic> _wrapResponse(Response response) {
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name] = values;
    });

    return {
      'statusCode': response.statusCode,
      'headers': headers,
      'data': response.data,
    };
  }

  Map<String, dynamic> _wrapError(DioException e) {
    return {
      'statusCode': e.response?.statusCode ?? 0,
      'error': e.message ?? 'Request failed',
      'data': e.response?.data?.toString(),
    };
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is String) {
      final data = response.data as String;
      if (data.startsWith('Your IP address') || data.startsWith('This IP address')) {
        log.warning('EH IP ban detected');
      }
      if (data.contains('You have exceeded your image')) {
        log.warning('EH image limit exceeded');
      }
    }
    handler.next(response);
  }
}

class GalleryDetailResult {
  String title = '';
  String titleJpn = '';
  String category = '';
  String uploader = '';
  String coverUrl = '';
  double rating = 0;
  int pageCount = 0;
  String? archiverUrl;
  List<String> thumbnailUrls = [];
  List<String> imagePageUrls = [];
  Map<String, List<String>> tags = {};
  int? apiuid;
  String? apikey;
  int? favoriteSlot;
  String? favoriteName;
  List<Map<String, dynamic>> comments = [];
}

class ImagePageResult {
  String imageUrl = '';
  String? reloadKey;
}
