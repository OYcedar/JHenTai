import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/log.dart';
import 'cookie_manager.dart';

/// Thrown when gallery HTML looks like EX sad panda / block page instead of a real gallery.
class GalleryDetailAccessException implements Exception {
  GalleryDetailAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _ehGalleryHtmlLooksBlocked(String body) {
  final lower = body.toLowerCase();
  if (lower.contains('sadpanda')) return true;
  if (body.length < 280) return true;
  return false;
}

class EHClient {
  late Dio _dio;
  late ServerCookieManager cookieManager;

  String _site = 'EH';

  String get site => _site;
  set site(String s) => _site = s;

  String get baseUrl => _site == 'EX' ? 'https://exhentai.org' : 'https://e-hentai.org';
  String get apiUrl => _site == 'EX' ? 'https://exhentai.org/api.php' : 'https://api.e-hentai.org/api.php';

  static const String ehForums = 'https://forums.e-hentai.org/index.php';

  /// CDN thumbnail URL for one `#gdt` link to a `/s/` viewer page (EH/EX layouts).
  static String extractThumbnailImageUrlFromGdtAnchor(Element a, String siteOrigin) {
    final parsed = parseGdtAnchorThumbnail(a, siteOrigin);
    if (parsed != null) {
      final u = parsed['thumbUrl'] as String? ?? '';
      if (u.isNotEmpty) return u;
    }
    return '';
  }

  /// Aligns with [GalleryThumbnail] / eh_spider_parser: large = one image URL; small = sprite sheet + crop.
  static Map<String, dynamic>? parseGdtAnchorThumbnail(Element a, String siteOrigin) {
    final div = a.querySelector('div[style]');
    if (div != null) {
      final style = div.attributes['style'] ?? '';
      final urlMatch = RegExp(r'url\(([^)]+)\)').firstMatch(style);
      if (urlMatch != null) {
        var thumbUrl = urlMatch.group(1)!.trim();
        if (thumbUrl.length >= 2 &&
            ((thumbUrl.startsWith('"') && thumbUrl.endsWith('"')) || (thumbUrl.startsWith("'") && thumbUrl.endsWith("'")))) {
          thumbUrl = thumbUrl.substring(1, thumbUrl.length - 1);
        }
        thumbUrl = _makeAbsoluteThumbUrl(thumbUrl, siteOrigin);

        final offsetMatch = RegExp(r'\)\s*-(\d+)px').firstMatch(style);
        final offsetVal = offsetMatch != null ? double.tryParse(offsetMatch.group(1)!) : null;

        final wMatch = RegExp(r'width:\s*(\d+)px').firstMatch(style);
        final hMatch = RegExp(r'height:\s*(\d+)px').firstMatch(style);
        final tw = double.tryParse(wMatch?.group(1) ?? '0') ?? 0;
        var th = double.tryParse(hMatch?.group(1) ?? '0') ?? 0;
        if (th > 0) th -= 1;

        final isLarge = offsetVal == null;
        final out = <String, dynamic>{
          'thumbUrl': thumbUrl,
          'isLarge': isLarge,
        };
        if (!isLarge) {
          out['offSet'] = offsetVal;
          out['thumbWidth'] = tw;
          out['thumbHeight'] = th;
        }
        final oh = div.attributes['data-orghash'];
        if (oh != null && oh.isNotEmpty) out['originImageHash'] = oh;
        return out;
      }
    }

    final img = a.querySelector('img');
    if (img != null) {
      final src = img.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        final thumbUrl = _makeAbsoluteThumbUrl(src, siteOrigin);
        final parts = thumbUrl.split('-');
        double? tw;
        double? th;
        if (parts.length >= 4) {
          tw = double.tryParse(parts[parts.length - 3]);
          th = double.tryParse(parts[parts.length - 2]);
        }
        final out = <String, dynamic>{
          'thumbUrl': thumbUrl,
          'isLarge': true,
        };
        if (tw != null) out['thumbWidth'] = tw;
        if (th != null) out['thumbHeight'] = th;
        return out;
      }
    }

    for (Element? el = a.parent; el != null; el = el.parent) {
      final st = el.attributes['style'] ?? '';
      if (!st.contains('url(')) continue;
      final urlMatch = RegExp(r'url\(([^)]+)\)').firstMatch(st);
      if (urlMatch == null) continue;
      var thumbUrl = urlMatch.group(1)!.trim();
      if (thumbUrl.length >= 2 &&
          ((thumbUrl.startsWith('"') && thumbUrl.endsWith('"')) || (thumbUrl.startsWith("'") && thumbUrl.endsWith("'")))) {
        thumbUrl = thumbUrl.substring(1, thumbUrl.length - 1);
      }
      thumbUrl = _makeAbsoluteThumbUrl(thumbUrl, siteOrigin);
      final offsetMatch = RegExp(r'\)\s*-(\d+)px').firstMatch(st);
      final off = offsetMatch != null ? double.tryParse(offsetMatch.group(1)!) : null;
      final wMatch = RegExp(r'width:\s*(\d+)px').firstMatch(st);
      final hMatch = RegExp(r'height:\s*(\d+)px').firstMatch(st);
      final tw = double.tryParse(wMatch?.group(1) ?? '0') ?? 0;
      var th = double.tryParse(hMatch?.group(1) ?? '0') ?? 0;
      if (th > 0) th -= 1;
      if (off != null) {
        return {
          'thumbUrl': thumbUrl,
          'isLarge': false,
          'offSet': off,
          'thumbWidth': tw,
          'thumbHeight': th,
        };
      }
    }

    return null;
  }

  static String _makeAbsoluteThumbUrl(String url, String siteOrigin) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$siteOrigin$url';
    return url;
  }

  /// Appends aligned viewer page URLs, legacy [thumbnailImageUrls], and full [galleryThumbnails] maps.
  void appendGalleryThumbPageData(
    String html,
    String pageUrl,
    List<String> pageUrls,
    List<String> thumbnailImageUrls,
    List<Map<String, dynamic>> galleryThumbnails,
  ) {
    final doc = html_parser.parse(html);
    final siteOrigin = Uri.parse(pageUrl).origin;

    void appendForAnchor(Element a, {required bool requireS}) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) return;
      if (requireS && !href.contains('/s/')) return;
      pageUrls.add(href);
      final parsed = parseGdtAnchorThumbnail(a, siteOrigin);
      if (parsed != null) {
        galleryThumbnails.add(parsed);
        thumbnailImageUrls.add(parsed['thumbUrl'] as String? ?? '');
      } else {
        final fallback = extractThumbnailImageUrlFromGdtAnchor(a, siteOrigin);
        thumbnailImageUrls.add(fallback);
        galleryThumbnails.add({
          'thumbUrl': fallback,
          'isLarge': true,
        });
      }
    }

    final pageLinks = doc.querySelectorAll('.gdtl a, .gdtm a');
    if (pageLinks.isNotEmpty) {
      for (final a in pageLinks) {
        appendForAnchor(a, requireS: false);
      }
    } else {
      for (final a in doc.querySelectorAll('#gdt a')) {
        appendForAnchor(a, requireS: true);
      }
    }
  }

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
    if (_ehGalleryHtmlLooksBlocked(body)) {
      throw GalleryDetailAccessException(
        'Gallery page unavailable. For ExHentai, use valid cookies including igneous.',
      );
    }
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

  // --- Favorite names / counts (favorites.php) ---

  /// Parses folder names and per-folder counts (same structure as EHSpiderParser.favoritePage2FavoriteTagsAndCounts).
  Future<({List<String> names, List<int> counts})> fetchFavoriteFolders() async {
    try {
      final response = await _dio.get('$baseUrl/favorites.php');
      final body = response.data.toString();
      return _parseFavoriteFoldersHtml(body);
    } catch (_) {
      return (names: List.generate(10, (i) => 'Favorites $i'), counts: List.filled(10, 0));
    }
  }

  ({List<String> names, List<int> counts}) _parseFavoriteFoldersHtml(String body) {
    final doc = html_parser.parse(body);
    final divs = doc.querySelectorAll('.nosel > .fp');
    if (divs.length > 1) {
      final list = divs.toList();
      list.removeLast();
      if (list.length >= 10) {
        final names = <String>[];
        final counts = <int>[];
        for (final div in list.take(10)) {
          names.add(div.querySelector('div:last-child')?.text.trim() ?? '');
          counts.add(int.tryParse(div.querySelector('div:first-child')?.text.trim() ?? '0') ?? 0);
        }
        return (names: names, counts: counts);
      }
    }
    final options = doc.querySelectorAll('.fp a.i');
    if (options.length >= 10) {
      final names = options.take(10).map((e) => e.text.trim()).toList();
      return (names: names, counts: List.filled(10, 0));
    }
    final inputs = doc.querySelectorAll('input[name^="favorite_"]');
    if (inputs.length >= 10) {
      final names = inputs
          .take(10)
          .map((e) => e.attributes['value'] ?? 'Favorites ${inputs.indexOf(e)}')
          .toList();
      return (names: names, counts: List.filled(10, 0));
    }
    return (names: List.generate(10, (i) => 'Favorites $i'), counts: List.filled(10, 0));
  }

  Future<List<String>> fetchFavoriteNames() async {
    final folders = await fetchFavoriteFolders();
    return folders.names;
  }

  /// GET gallery popups addfav — favorite note textarea (see favoritePopup2GalleryNote).
  Future<String> fetchFavoritePopupNote(int gid, String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/gallerypopups.php',
        queryParameters: {'gid': gid, 't': token, 'act': 'addfav'},
      );
      final body = response.data.toString();
      final doc = html_parser.parse(body);
      final ta = doc.querySelector('#galpop textarea') ??
          doc.querySelector('#galpop > div > div:nth-child(3) > textarea');
      return ta?.text ?? '';
    } catch (_) {
      return '';
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

  // --- Stats / image lookup / my tags (Web parity with native) ---

  String get statsPageUrl =>
      _site == 'EX' ? 'https://exhentai.org/stats.php' : 'https://e-hentai.org/stats.php';

  String get imageLookupUrl => _site == 'EX'
      ? 'https://exhentai.org/upld/image_lookup.php'
      : 'https://upld.e-hentai.org/image_lookup.php';

  String get myTagsUrl => '$baseUrl/mytags';

  Future<String> fetchStatsPageHtml(int gid, String token) async {
    final response = await _dio.get<String>(statsPageUrl, queryParameters: {'gid': gid, 't': token});
    return response.data ?? '';
  }

  /// Returns absolute or relative Location from EH image lookup (302).
  Future<String?> postImageLookup(List<int> bytes, String filename) async {
    try {
      final response = await _dio.post(
        imageLookupUrl,
        data: FormData.fromMap({
          'sfile': MultipartFile.fromBytes(bytes, filename: filename),
          'f_sfile': 'File Search',
          'fs_similar': 'on',
          'fs_exp': 'on',
        }),
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && (status == 302 || status == 303 || status == 200),
        ),
      );
      final code = response.statusCode ?? 0;
      if (code == 302 || code == 303) {
        return response.headers.value('location');
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 302 || code == 303) {
        return e.response?.headers.value('location');
      }
      rethrow;
    }
    return null;
  }

  Future<String> fetchMyTagsHtml(int tagSetNo) async {
    final response = await _dio.get<String>(myTagsUrl, queryParameters: {'tagset': tagSetNo});
    return response.data ?? '';
  }

  Future<void> postMyTagsForm(int tagSetNo, Map<String, dynamic> fields) async {
    await _dio.post(
      myTagsUrl,
      queryParameters: {'tagset': tagSetNo},
      options: Options(contentType: Headers.formUrlEncodedContentType),
      data: fields,
    );
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

    // Parse all #gdd metadata rows
    final gddRows = doc.querySelectorAll('#gdd tr');
    for (final tr in gddRows) {
      final label = tr.querySelector('.gdt1')?.text.trim().toLowerCase() ?? '';
      final value = tr.querySelector('.gdt2')?.text.trim() ?? '';
      if (label.contains('posted')) {
        result.publishDate = value;
      } else if (label.contains('file size')) {
        result.fileSize = value;
      } else if (label.contains('length')) {
        final pageMatch = RegExp(r'(\d+) pages?').firstMatch(value);
        result.pageCount = int.tryParse(pageMatch?.group(1) ?? '') ?? 0;
      } else if (label.contains('language')) {
        result.language = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      } else if (label.contains('parent')) {
        final parentLink = tr.querySelector('.gdt2 a');
        if (parentLink != null) {
          result.parentUrl = parentLink.attributes['href'];
        }
      }
    }

    // Rating count
    final ratingCountText = doc.querySelector('#rating_count')?.text ?? '';
    result.ratingCount = int.tryParse(ratingCountText) ?? 0;

    // Newer version
    final newerEl = doc.querySelector('#gnd a');
    if (newerEl != null) {
      result.newerVersionUrl = newerEl.attributes['href'];
    }

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

    appendGalleryThumbPageData(
      html,
      galleryUrl,
      result.imagePageUrls,
      result.thumbnailImageUrls,
      result.galleryThumbnails,
    );

    return result;
  }

  ImagePageResult _parseImagePage(String html) {
    final doc = html_parser.parse(html);
    final result = ImagePageResult();

    final imgElement = doc.querySelector('#img');
    result.imageUrl = imgElement?.attributes['src'] ?? '';

    // Fallback: try regex patterns if DOM query missed it
    if (result.imageUrl.isEmpty) {
      final patterns = [
        RegExp(r'id="img"\s[^>]*src="([^"]+)"'),
        RegExp(r'src="([^"]+)"\s[^>]*id="img"'),
        RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"'),
        RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"'),
      ];
      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          result.imageUrl = match.group(1)!;
          break;
        }
      }
    }

    // Last resort: find any CDN image URL
    if (result.imageUrl.isEmpty) {
      final cdnMatch = RegExp(r'"(https?://[^"]+\.(jpg|png|gif|webp))"', caseSensitive: false).firstMatch(html);
      if (cdnMatch != null) result.imageUrl = cdnMatch.group(1)!;
    }

    final nl = doc.querySelector('#loadfail')?.attributes['onclick'];
    if (nl != null) {
      final nlMatch = RegExp(r"nl\('([^']+)'\)").firstMatch(nl);
      result.reloadKey = nlMatch?.group(1);
    }

    try {
      final hashEl = doc.querySelector('#i6 div a');
      final href = hashEl?.attributes['href'];
      if (href != null) {
        final hm = RegExp(r'f_shash=(\w+)').firstMatch(href);
        if (hm != null) result.imageHash = hm.group(1)!;
      }
    } catch (_) {}

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
  List<String> imagePageUrls = [];
  List<String> thumbnailImageUrls = [];
  List<Map<String, dynamic>> galleryThumbnails = [];
  Map<String, List<String>> tags = {};
  int? apiuid;
  String? apikey;
  int? favoriteSlot;
  String? favoriteName;
  List<Map<String, dynamic>> comments = [];
  String publishDate = '';
  String fileSize = '';
  String language = '';
  String? parentUrl;
  int ratingCount = 0;
  String? newerVersionUrl;
}

class ImagePageResult {
  String imageUrl = '';
  String? reloadKey;
  /// EH file hash from `f_shash=` on the image page (for upgrade reuse / JHenTai public API).
  String imageHash = '';
}
