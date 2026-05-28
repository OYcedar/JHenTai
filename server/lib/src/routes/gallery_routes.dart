import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../network/eh_client.dart';
import '../utils/eh_gallery_list_navigation.dart';
import '../utils/eh_tag_style_parse.dart';
import '../utils/gallery_stats_parser.dart';
import 'block_rule_routes.dart';

/// Parses total image count from EH/EX `.gpc` thumbnail pager text (English + common variants).
int _parseThumbGridTotalPages(String gpcText) {
  final t = gpcText.replaceAll('\u00a0', ' ').trim();
  if (t.isEmpty) return 0;

  int parseDigits(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[,\s]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  final patterns = <RegExp>[
    RegExp(r'of\s+([\d,\s]+)\s*$', caseSensitive: false),
    RegExp(r'of\s+([\d,\s]+)', caseSensitive: false),
    RegExp(r'/\s*([\d,\s]+)\s*$', caseSensitive: false),
    RegExp(r'/\s*([\d,\s]+)', caseSensitive: false),
    RegExp(r'(\d+)\s*pages?\b', caseSensitive: false),
    RegExp(r'(\d+)\s*ページ', caseSensitive: false),
    RegExp(r'(\d+)\s*张', caseSensitive: false),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(t);
    if (m != null) {
      final n = parseDigits(m.group(1)!);
      if (n > 0) return n;
    }
  }
  return 0;
}

class GalleryRoutes {
  final EHClient _client;

  GalleryRoutes(this._client);

  Router get router {
    final router = Router();

    router.get('/list', _galleryList);
    router.get('/list-by-url', _galleryListByUrl);
    router.get('/stats/<gid>/<token>', _galleryStats);
    router.get('/torrents/<gid>/<token>', _galleryTorrents);
    router.get('/eh-status', _ehStatus);
    router.post('/reset-image-limit', _resetImageLimit);
    router.post('/hh-info', _galleryHHInfo);
    router.post('/hh-download', _galleryHHDownload);
    router.post('/image-lookup', _galleryImageLookup);
    router.get('/resolve-image-page', _resolveImagePage);
    router.get('/detail/<gid>/<token>', _galleryDetail);
    router.get('/images/<gid>/<token>', _galleryImagePages);

    return router;
  }

  String _normalizeListHref(String? href, String origin) {
    if (href == null || href.isEmpty) return '';
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) return '$origin$href';
    return '$origin/$href';
  }

  Future<Response> _galleryStats(
      Request request, String gid, String token) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    try {
      final html = await _client.fetchStatsPageHtml(id, token);
      final stats = parseGalleryStatsHtml(html);
      if (stats == null) {
        return Response(
          404,
          body: jsonEncode({'error': 'Stats unavailable or gallery hidden'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.ok(jsonEncode(stats),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch stats: $e'}),
      );
    }
  }

  Future<Response> _ehStatus(Request request) async {
    try {
      final homeHtml = await _client.fetchHomePageHtml();
      final exchangeHtml = await _client.fetchExchangePageHtml();
      return Response.ok(
        jsonEncode({
          ..._parseImageLimit(homeHtml),
          ..._parseAssets(exchangeHtml),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch EH status: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _resetImageLimit(Request request) async {
    try {
      await _client.resetImageLimit();
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to reset image limit: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic> _parseImageLimit(String html) {
    final doc = html_parser.parse(html);
    final isDonator = doc.querySelector(
          '.stuffbox > .homebox > form > p > input[value="Reset Quota"]',
        ) !=
        null;
    if (!isDonator) {
      return {'isDonator': false};
    }
    int? intText(String selector) {
      final raw = doc.querySelector(selector)?.text.replaceAll(',', '').trim();
      return int.tryParse(raw ?? '');
    }

    return {
      'isDonator': true,
      'currentConsumption':
          intText('.stuffbox > .homebox > p > strong:nth-child(1)'),
      'totalLimit': intText('.stuffbox > .homebox > p > strong:nth-child(3)'),
      'resetCost': intText('.stuffbox > .homebox > p:nth-child(3) > strong'),
    };
  }

  Map<String, dynamic> _parseAssets(String html) {
    final doc = html_parser.parse(html);
    final creditDesc =
        doc.querySelector('#buyform')?.parent?.nextElementSibling?.text;
    final gpCreditDesc =
        doc.querySelector('#sellform')?.parent?.nextElementSibling?.text;
    final credit =
        RegExp(r'([\d,k ]+)Credits').firstMatch(creditDesc ?? '')?.group(1);
    final gp = RegExp(r'([\d,k ]+)GP').firstMatch(gpCreditDesc ?? '')?.group(1);
    return {
      'credit': credit?.trim() ?? '-',
      'gp': gp?.trim() ?? '-',
    };
  }

  Future<Response> _galleryTorrents(
      Request request, String gid, String token) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid gid'}));
    }
    try {
      final html = await _client.fetchTorrentPageHtml(id, token);
      final torrents = _parseTorrentPageHtml(html);
      return Response.ok(
        jsonEncode({'torrents': torrents}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch torrents: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  List<Map<String, dynamic>> _parseTorrentPageHtml(String html) {
    final doc = html_parser.parse(html);
    final result = <Map<String, dynamic>>[];
    final forms = doc.querySelectorAll('#torrentinfo > div > form');
    for (final form in forms) {
      final rows = form.querySelectorAll('div > table > tbody > tr');
      if (rows.length < 3) continue;
      final link = rows[2].querySelector('td > a');
      final torrentUrl = link?.attributes['href'] ?? '';
      if (link == null || torrentUrl.isEmpty) continue;

      final metaText = rows[0].text.replaceAll('\u00a0', ' ');
      final uploaderText = rows.length > 1 ? rows[1].text : '';
      final infoHash = RegExp(r'/([^/.]+)\.torrent(?:$|[?#])')
          .firstMatch(torrentUrl)
          ?.group(1);
      final downloadUrl = torrentUrl.replaceFirst(
        RegExp(r'https://exhentai\.org/torrent', caseSensitive: false),
        'https://ehtracker.org/get',
      );
      result.add({
        'title': link.text.trim(),
        'postTime': _firstGroup(
          RegExp(r'Posted:\s*(.*?)(?:\s+Size:|$)', caseSensitive: false),
          metaText,
        ),
        'size': _firstGroup(
          RegExp(r'Size:\s*(.*?)(?:\s+Seeds:|$)', caseSensitive: false),
          metaText,
        ),
        'seeds': _parseMetaInt('Seeds', metaText),
        'peers': _parseMetaInt('Peers', metaText),
        'downloads': _parseMetaInt('Downloads', metaText),
        'uploader': _firstGroup(
          RegExp(r'(?:Posted by|Uploader):\s*(.*)$', caseSensitive: false),
          uploaderText,
        ),
        'torrentUrl': torrentUrl,
        'downloadUrl': downloadUrl,
        'magnetUrl': infoHash == null ? '' : 'magnet:?xt=urn:btih:$infoHash',
        'outdated': metaText.toLowerCase().contains('outdated') ||
            (rows[0]
                    .querySelector('span[style*="color:red"]')
                    ?.attributes['style']
                    ?.isNotEmpty ??
                false),
      });
    }
    return result;
  }

  String _firstGroup(RegExp pattern, String text) {
    return pattern.firstMatch(text)?.group(1)?.trim() ?? '';
  }

  int _parseMetaInt(String label, String text) {
    final match =
        RegExp('$label:\\s*(\\d+)', caseSensitive: false).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<Response> _galleryHHInfo(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final archivePageUrl = body['archivePageUrl']?.toString() ?? '';
      if (archivePageUrl.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing archivePageUrl'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final html = await _client.fetchHHArchivePageHtml(archivePageUrl);
      return Response.ok(
        jsonEncode(_parseHHArchivePageHtml(html)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch H@H info: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _galleryHHDownload(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final archivePageUrl = body['archivePageUrl']?.toString() ?? '';
      final resolution = body['resolution']?.toString() ?? '';
      if (archivePageUrl.isEmpty || resolution.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing archivePageUrl or resolution'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final html = await _client.requestHHDownload(archivePageUrl, resolution);
      final message = html_parser.parse(html).querySelector('#db > p')?.text ??
          'H@H download request submitted';
      return Response.ok(
        jsonEncode({'message': message.trim()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to request H@H download: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic> _parseHHArchivePageHtml(String html) {
    final doc = html_parser.parse(html);
    final balanceText = doc.querySelector('#db > p:nth-child(4)')?.text ?? '';
    final archives = <Map<String, dynamic>>[];
    for (final td in doc.querySelectorAll('table > tbody > tr > td')) {
      final desc = td.querySelector('p:nth-child(1)')?.text.trim() ?? '';
      final onclick =
          td.querySelector('p:nth-child(1) > a')?.attributes['onclick'] ?? '';
      final resolution = RegExp(r"'(\w+)'").firstMatch(onclick)?.group(1) ?? '';
      final size = td.querySelector('p:nth-child(3)')?.text.trim() ?? '';
      final cost = td.querySelector('p:nth-child(5)')?.text.trim() ?? '';
      if (desc.isEmpty || resolution.isEmpty) continue;
      archives.add({
        'resolutionDesc': desc,
        'resolution': resolution,
        'size': size,
        'cost': cost,
      });
    }
    return {
      'gpCount': _parseBalanceCount(balanceText, 'GP'),
      'creditCount': _parseBalanceCount(balanceText, 'Credits'),
      'archives': archives,
    };
  }

  int? _parseBalanceCount(String text, String unit) {
    final match = RegExp(r'([\d,]+)\s+' + RegExp.escape(unit)).firstMatch(text);
    return int.tryParse(match?.group(1)?.replaceAll(',', '') ?? '');
  }

  Future<Response> _galleryListByUrl(Request request) async {
    final raw = request.url.queryParameters['url'];
    if (raw == null || raw.isEmpty) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Missing url query parameter'}));
    }
    final decoded = Uri.decodeComponent(raw);
    final fetchUrl = _normalizeListHref(decoded, _client.baseUrl);
    if (fetchUrl.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid url'}));
    }
    try {
      final result = await _client.proxyGet(fetchUrl);
      final html = result['data']?.toString() ?? '';
      if (html.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Empty response'}),
        );
      }
      final galleries = _parseGalleryListHtml(html);
      final origin = Uri.parse(fetchUrl).origin;
      galleries['prevUrl'] =
          _normalizeListHref(galleries['prevUrl'] as String?, origin);
      galleries['nextUrl'] =
          _normalizeListHref(galleries['nextUrl'] as String?, origin);
      final list = galleries['galleries'] as List<Map<String, dynamic>>?;
      if (list != null) {
        for (final g in list) {
          final u = g['url'] as String? ?? '';
          if (u.isNotEmpty) g['url'] = _normalizeListHref(u, origin);
        }
      }
      final blockRules = db.selectAllBlockRules();
      if (blockRules.isNotEmpty && list != null) {
        list.removeWhere(
            (g) => blockRules.any((rule) => matchesBlockRule(rule, g)));
      }
      return Response.ok(jsonEncode(galleries),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch list: $e'}),
      );
    }
  }

  Future<Response> _galleryImageLookup(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }
    final b64 = body['imageBase64'] as String?;
    final filename = body['filename'] as String? ?? 'upload.jpg';
    if (b64 == null || b64.isEmpty) {
      return Response.badRequest(
          body: jsonEncode({'error': 'Missing imageBase64'}));
    }
    try {
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) {
        return Response.badRequest(body: jsonEncode({'error': 'Empty image'}));
      }
      if (bytes.length > 25 * 1024 * 1024) {
        return Response(413, body: jsonEncode({'error': 'Image too large'}));
      }
      final loc = await _client.postImageLookup(bytes, filename);
      if (loc == null || loc.isEmpty) {
        return Response(
          502,
          body: jsonEncode({'error': 'Lookup did not redirect'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final absolute = _normalizeListHref(loc, _client.baseUrl);
      return Response.ok(
        jsonEncode({'redirectUrl': absolute}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Image lookup failed: $e'}),
      );
    }
  }

  Future<Response> _resolveImagePage(Request request) async {
    final raw = request.url.queryParameters['url'];
    if (raw == null || raw.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing url query parameter'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final imagePageUrl = Uri.decodeComponent(raw);
    final imagePageMatch = RegExp(
      r'https://e[-x]hentai\.org/s/[a-z0-9]{10}/(\d+)-(\d+)',
      caseSensitive: false,
    ).firstMatch(imagePageUrl);
    if (imagePageMatch == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid image page url'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final result = await _client.fetchImagePage(imagePageUrl);
      final parentUrl = result.parentGalleryUrl;
      final parentMatch = RegExp(
        r'https://e[-x]hentai\.org/g/(\d+)/([a-z0-9]{10})',
        caseSensitive: false,
      ).firstMatch(parentUrl);
      if (parentMatch == null) {
        return Response(
          404,
          body: jsonEncode({'error': 'Parent gallery link not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'gid': int.parse(parentMatch.group(1)!),
          'token': parentMatch.group(2)!,
          'pageNo': int.parse(imagePageMatch.group(2)!),
          'parentGalleryUrl': parentUrl,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to resolve image page: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _galleryList(Request request) async {
    final page = request.url.queryParameters['page'];
    final cursorNext = request.url.queryParameters['next'];
    final cursorPrev = request.url.queryParameters['prev'];
    final search = request.url.queryParameters['f_search'];
    final section = request.url.queryParameters['section'] ?? 'home';
    final seek = request.url.queryParameters['seek'];

    final tl = request.url.queryParameters['tl'];

    final url = switch (section) {
      'popular' => '${_client.baseUrl}/popular',
      'favorites' => '${_client.baseUrl}/favorites.php',
      'watched' => '${_client.baseUrl}/watched',
      'ranklist' => '${_client.baseUrl}/toplist.php',
      _ => _client.baseUrl,
    };

    final queryParams = <String, dynamic>{};
    // Ranklist uses `p=` (native [requestRanklistPage]), not `page=`.
    if (section == 'ranklist') {
      if (page != null && page.isNotEmpty) {
        queryParams['p'] = page;
      }
    } else {
      // Main index lists: native uses `next` / `prev` gid cursors; `page` is fallback only.
      if (cursorNext != null && cursorNext.isNotEmpty) {
        queryParams['next'] = cursorNext;
      } else if (cursorPrev != null && cursorPrev.isNotEmpty) {
        queryParams['prev'] = cursorPrev;
      } else if (seek != null && seek.isNotEmpty) {
        queryParams['seek'] = seek;
      } else if (page != null && page.isNotEmpty) {
        queryParams['page'] = page;
      }
    }
    // Only index-like lists accept arbitrary `f_search`. Popular / ranklist may 5xx or break parsers if
    // the client sends e.g. `language:"…"` from an empty keyword (WebHomeController._composeFSearch).
    if (search != null && search.isNotEmpty) {
      if (section == 'home' || section == 'watched' || section == 'favorites') {
        queryParams['f_search'] = search;
      }
    }

    if (section == 'ranklist') {
      if (tl != null) queryParams['tl'] = tl;
    }
    if (section == 'favorites') {
      // Align with native: FavoriteSortOrder — fs_f = favorited time, fs_p = published time.
      final favSort = request.url.queryParameters['fav_sort'] ?? 'fs_f';
      queryParams['inline_set'] = favSort == 'fs_p' ? 'fs_p' : 'fs_f';
      final favcatStr = request.url.queryParameters['favcat'];
      if (favcatStr != null && favcatStr.isNotEmpty) {
        final fc = int.tryParse(favcatStr);
        if (fc != null && fc >= 0 && fc <= 9) {
          queryParams['favcat'] = fc;
        }
      }
    }

    // Advanced search / category bitmask only applies to the main gallery index on EH/EX.
    // Forwarding them to /popular, /watched, etc. can break upstream responses and cause 5xx.
    if (section == 'home') {
      for (final key in [
        'f_cats',
        'f_sname',
        'f_stags',
        'f_sdesc',
        'f_sh',
        'advsearch',
        'f_srdd',
        'f_sr',
        'f_sto',
        'f_spf',
        'f_spt',
        // Align with native [SearchConfig]: disable language filter on index search.
        'f_sfl',
        'f_sfu',
        'f_sft',
      ]) {
        final val = request.url.queryParameters[key];
        if (val != null && val.isNotEmpty) queryParams[key] = val;
      }
    } else if (section == 'watched') {
      final fSfl = request.url.queryParameters['f_sfl'];
      if (fSfl != null && fSfl.isNotEmpty) {
        queryParams['f_sfl'] = fSfl;
      }
    }

    try {
      final result = await _client.proxyGet(url,
          queryParams: queryParams.isNotEmpty ? queryParams : null);
      final html = result['data']?.toString() ?? '';
      final galleries = _parseGalleryListHtml(html);

      // Make list API match list-by-url: absolute prev/next and gallery hrefs (client expects full URLs).
      final origin = _client.baseUrl;
      galleries['prevUrl'] =
          _normalizeListHref(galleries['prevUrl'] as String?, origin);
      galleries['nextUrl'] =
          _normalizeListHref(galleries['nextUrl'] as String?, origin);
      final listForNorm = galleries['galleries'] as List<Map<String, dynamic>>?;
      if (listForNorm != null) {
        for (final g in listForNorm) {
          final u = g['url'] as String? ?? '';
          if (u.isNotEmpty) {
            g['url'] = _normalizeListHref(u, origin);
          }
        }
      }

      // EH cursor navigation (before block rules — independent of filtered row count).
      var parsedNextGid = EhGalleryListNavigation.parseNextGid(html);
      var parsedPrevGid = EhGalleryListNavigation.parsePrevGid(html);
      final nu = galleries['nextUrl'] as String? ?? '';
      final pu = galleries['prevUrl'] as String? ?? '';
      parsedNextGid ??= RegExp(r'[?&]next=([\d-]+)', caseSensitive: false)
          .firstMatch(nu)
          ?.group(1);
      parsedPrevGid ??= RegExp(r'[?&]prev=([\d-]+)', caseSensitive: false)
          .firstMatch(pu)
          ?.group(1);
      galleries['nextGid'] = parsedNextGid;
      galleries['prevGid'] = parsedPrevGid;
      galleries['hasMore'] =
          (parsedNextGid != null && parsedNextGid.isNotEmpty) || nu.isNotEmpty;
      galleries['hasPrev'] =
          (parsedPrevGid != null && parsedPrevGid.isNotEmpty) || pu.isNotEmpty;

      final blockRules = db.selectAllBlockRules();
      if (blockRules.isNotEmpty) {
        final list = galleries['galleries'] as List<Map<String, dynamic>>?;
        if (list != null) {
          list.removeWhere(
              (g) => blockRules.any((rule) => matchesBlockRule(rule, g)));
        }
      }

      return Response.ok(
        jsonEncode(galleries),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch gallery list: $e'}),
      );
    }
  }

  Future<Response> _galleryDetail(
      Request request, String gid, String token) async {
    final galleryUrl = '${_client.baseUrl}/g/$gid/$token/';

    try {
      final detail = await _client.fetchGalleryDetail(galleryUrl);
      final comments = detail.comments
          .map((comment) => Map<String, dynamic>.from(comment))
          .toList();
      final blockRules = [
        ...db.selectAllBlockRules(),
        ...await builtInBlockedUserRules(),
      ];
      if (blockRules.isNotEmpty) {
        comments.removeWhere((comment) =>
            blockRules.any((rule) => matchesCommentBlockRule(rule, comment)));
      }
      return Response.ok(
        jsonEncode({
          'title': detail.title,
          'titleJpn': detail.titleJpn,
          'category': detail.category,
          'uploader': detail.uploader,
          'coverUrl': detail.coverUrl,
          'rating': detail.rating,
          'pageCount': detail.pageCount,
          'archiverUrl': detail.archiverUrl,
          'imagePageUrls': detail.imagePageUrls,
          'thumbnailImageUrls': detail.thumbnailImageUrls,
          'galleryThumbnails': detail.galleryThumbnails,
          'galleryUrl': galleryUrl,
          'tags': detail.tags,
          'tagsRich': detail.tagsRich,
          'apiuid': detail.apiuid,
          'apikey': detail.apikey,
          'favoriteSlot': detail.favoriteSlot,
          'favoriteName': detail.favoriteName,
          'comments': comments,
          'publishDate': detail.publishDate,
          'fileSize': detail.fileSize,
          'language': detail.language,
          'parentUrl': detail.parentUrl,
          'ratingCount': detail.ratingCount,
          'newerVersionUrl': detail.newerVersionUrl,
          'childVersions': detail.childVersions,
          'torrentCount': detail.torrentCount,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on GalleryDetailAccessException catch (e) {
      return Response(
        403,
        body: jsonEncode({'error': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch gallery detail: $e'}),
      );
    }
  }

  Future<Response> _galleryImagePages(
      Request request, String gid, String token) async {
    final galleryUrl = '${_client.baseUrl}/g/$gid/$token/';

    try {
      final allPageUrls = <String>[];
      final allThumbUrls = <String>[];
      final allGalleryThumbs = <Map<String, dynamic>>[];
      final baseUri = Uri.parse(galleryUrl);
      var thumbPageIndex = 0;
      var totalPages = 0;
      var hitCap = false;

      while (true) {
        final q = Map<String, String>.from(baseUri.queryParameters);
        q['p'] = '$thumbPageIndex';
        final pageUrl = baseUri.replace(queryParameters: q).toString();

        final result = await _client.proxyGet(pageUrl);
        final html = result['data']?.toString() ?? '';
        final doc = html_parser.parse(html);

        if (totalPages == 0) {
          final pageCountText = doc.querySelector('.gpc')?.text ?? '';
          totalPages = _parseThumbGridTotalPages(pageCountText);
        }

        final countBefore = allPageUrls.length;
        _client.appendGalleryThumbPageData(
            html, pageUrl, allPageUrls, allThumbUrls, allGalleryThumbs);

        if (totalPages > 0 && allPageUrls.length >= totalPages) break;
        if (allPageUrls.length == countBefore) break;

        final cap = totalPages > 0 ? (totalPages + 9) ~/ 10 + 10 : 50;
        if (thumbPageIndex >= cap) {
          hitCap = true;
          break;
        }
        thumbPageIndex++;
      }

      final int reportedTotal;
      if (totalPages > 0) {
        reportedTotal = totalPages;
      } else if (!hitCap && allPageUrls.isNotEmpty) {
        reportedTotal = allPageUrls.length;
      } else {
        reportedTotal = 0;
      }

      return Response.ok(
        jsonEncode({
          'imagePageUrls': allPageUrls,
          'thumbnailImageUrls': allThumbUrls,
          'galleryThumbnails': allGalleryThumbs,
          'totalPages': reportedTotal,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch image pages: $e'}),
      );
    }
  }

  Element? _pttLinkAdjacentToCurrent(Document doc, {required bool next}) {
    final tr = doc.querySelector('.ptt > tbody > tr') ??
        doc.querySelector('table.ptt tr');
    if (tr == null) return null;
    final cells = tr.children.whereType<Element>().toList();
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].localName != 'td') continue;
      if (!cells[i].classes.contains('ptds')) continue;
      if (next) {
        if (i + 1 < cells.length) {
          return cells[i + 1].querySelector('a');
        }
      } else {
        if (i > 0) {
          return cells[i - 1].querySelector('a');
        }
      }
    }
    return null;
  }

  /// Prev/next gallery list URLs — layered fallbacks when EH changes `.ptt` or drops `#unext` / `#uprev`.
  ({String prevUrl, String nextUrl}) _parsePaginationUrls(Document doc) {
    var prevUrl = '';
    var nextUrl = '';

    String? href(Element? e) {
      final h = e?.attributes['href'];
      if (h == null || h.isEmpty) return null;
      return h;
    }

    bool isFirstPageJump(Element a) {
      final t = a.text.trim();
      return t == '<<' || t == '«' || t.toLowerCase() == 'first';
    }

    bool isLastPageJump(Element a) {
      final t = a.text.trim();
      return t == '>>' || t == '»' || t.toLowerCase() == 'last';
    }

    bool looksLikeNextNav(Element a) {
      final t = a.text.trim();
      if (t == '>' || t == '›' || t.toLowerCase() == 'next') return true;
      final rel = a.attributes['rel']?.toLowerCase();
      return rel == 'next';
    }

    bool looksLikePrevNav(Element a) {
      final t = a.text.trim();
      if (t == '<' ||
          t == '‹' ||
          t.toLowerCase() == 'prev' ||
          t.toLowerCase() == 'previous') return true;
      final rel = a.attributes['rel']?.toLowerCase();
      return rel == 'prev';
    }

    bool pageishHref(String h) {
      return h.contains('page=') || RegExp(r'[?&]p(age)?=').hasMatch(h);
    }

    Element? nextEl = doc.querySelector('#unext');
    nextEl ??= doc.querySelector('a#dnext');
    nextEl ??= doc.querySelector('a[id="dnext"]');
    nextUrl = href(nextEl) ?? '';

    if (nextUrl.isEmpty) {
      nextUrl = href(doc.querySelector('a[rel="next"]')) ?? '';
    }

    if (nextUrl.isEmpty) {
      final pttCells = doc.querySelectorAll('.ptt td');
      nextEl = pttCells.length >= 2
          ? pttCells[pttCells.length - 2].querySelector('a')
          : null;
      if (nextEl != null &&
          !isLastPageJump(nextEl) &&
          looksLikeNextNav(nextEl)) {
        nextUrl = href(nextEl) ?? '';
      }
    }

    if (nextUrl.isEmpty) {
      final adj = _pttLinkAdjacentToCurrent(doc, next: true);
      if (adj != null && !isLastPageJump(adj)) {
        nextUrl = href(adj) ?? '';
      }
    }

    if (nextUrl.isEmpty) {
      final pttCells = doc.querySelectorAll('.ptt td');
      final last =
          pttCells.isNotEmpty ? pttCells.last.querySelector('a') : null;
      if (last != null && looksLikeNextNav(last) && !isLastPageJump(last)) {
        nextUrl = href(last) ?? '';
      }
    }

    if (nextUrl.isEmpty) {
      for (final a in doc.querySelectorAll('.ptt a')) {
        final h = href(a);
        if (h == null) continue;
        if (looksLikeNextNav(a) && !isLastPageJump(a) && pageishHref(h)) {
          nextUrl = h;
          break;
        }
      }
    }

    Element? prevEl = doc.querySelector('#uprev');
    prevEl ??= doc.querySelector('a#dprev');
    prevEl ??= doc.querySelector('a[id="dprev"]');
    prevUrl = href(prevEl) ?? '';

    if (prevUrl.isEmpty) {
      prevUrl = href(doc.querySelector('a[rel="prev"]')) ?? '';
    }

    if (prevUrl.isEmpty) {
      prevEl = doc.querySelector('.ptt td:nth-child(2) a');
      if (prevEl != null &&
          !isFirstPageJump(prevEl) &&
          looksLikePrevNav(prevEl)) {
        prevUrl = href(prevEl) ?? '';
      }
    }

    if (prevUrl.isEmpty) {
      prevEl = doc.querySelector('.ptt td:first-child a');
      if (prevEl != null &&
          !isFirstPageJump(prevEl) &&
          looksLikePrevNav(prevEl)) {
        prevUrl = href(prevEl) ?? '';
      }
    }

    if (prevUrl.isEmpty) {
      final adj = _pttLinkAdjacentToCurrent(doc, next: false);
      if (adj != null && !isFirstPageJump(adj)) {
        prevUrl = href(adj) ?? '';
      }
    }

    if (prevUrl.isEmpty) {
      for (final a in doc.querySelectorAll('.ptt a')) {
        final h = href(a);
        if (h == null) continue;
        if (looksLikePrevNav(a) && !isFirstPageJump(a) && pageishHref(h)) {
          prevUrl = h;
          break;
        }
      }
    }

    return (prevUrl: prevUrl, nextUrl: nextUrl);
  }

  Map<String, dynamic> _parseGalleryListHtml(String html) {
    final doc = html_parser.parse(html);
    final galleries = <Map<String, dynamic>>[];

    final rows =
        doc.querySelectorAll('.glte, .gl1t, .gl3t, tr.gtr0, tr.gtr1, .itg tr');

    if (rows.isEmpty) {
      final galleryLinks = doc.querySelectorAll('a[href*="/g/"]');
      final seen = <String>{};

      for (final a in galleryLinks) {
        final href = a.attributes['href'] ?? '';
        final match = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(href);
        if (match == null) continue;
        final gid = match.group(1)!;
        if (seen.contains(gid)) continue;
        seen.add(gid);

        final titleEl = a.querySelector('.glink') ?? a;
        final title = titleEl.text.trim();
        if (title.isEmpty) continue;

        String coverUrl = '';
        final img = a.querySelector('img') ?? a.parent?.querySelector('img');
        if (img != null) {
          coverUrl = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        }

        String category = '';
        final parent = a.parent;
        final catEl = parent?.querySelector('.cn, .cs, .ct');
        if (catEl != null) category = catEl.text.trim();

        final scope = a.parent is Element ? a.parent as Element : a;
        final extra = _parseRowMetadata(scope);

        galleries.add({
          'gid': int.parse(gid),
          'token': match.group(2),
          'title': title,
          'coverUrl': coverUrl,
          'category': category,
          'url': href,
          ...extra,
        });
      }
    } else {
      final seen = <String>{};
      for (final row in rows) {
        final a = row.querySelector('a[href*="/g/"]');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        final match = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(href);
        if (match == null) continue;

        final gid = match.group(1)!;
        if (seen.contains(gid)) continue;
        seen.add(gid);

        final titleEl = row.querySelector('.glink');
        final title = titleEl?.text.trim() ?? '';

        String coverUrl = '';
        final img = row.querySelector('img');
        if (img != null) {
          coverUrl = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        }

        String category = '';
        final catEl = row.querySelector('.cn, .cs, .ct');
        if (catEl != null) category = catEl.text.trim();

        final extra = _parseRowMetadata(row);

        galleries.add({
          'gid': int.parse(gid),
          'token': match.group(2),
          'title': title,
          'coverUrl': coverUrl,
          'category': category,
          'url': href,
          ...extra,
        });
      }
    }

    // Parse pagination from various page types (EH DOM changes often — use layered fallbacks).
    final pn = _parsePaginationUrls(doc);
    var prevUrl = pn.prevUrl;
    var nextUrl = pn.nextUrl;

    // Ranklist toplist.php uses different pagination - look for page links
    if (prevUrl.isEmpty && nextUrl.isEmpty) {
      final pageLinks = doc.querySelectorAll('.ptt a, .ptds + td a');
      if (pageLinks.isNotEmpty) {
        nextUrl = pageLinks.last.attributes['href'] ?? '';
      }
    }

    return {
      'galleries': galleries,
      'prevUrl': prevUrl,
      'nextUrl': nextUrl,
    };
  }

  Map<String, dynamic> _parseRowMetadata(Element element) {
    final extra = <String, dynamic>{};

    // Page count: look for "N pages" text
    final allText = element.text;
    final pageMatch = RegExp(r'(\d+)\s*pages?').firstMatch(allText);
    if (pageMatch != null) {
      extra['pageCount'] = int.tryParse(pageMatch.group(1)!) ?? 0;
    }

    // Rating from .ir star background-position
    final ratingEl = element.querySelector('.ir');
    if (ratingEl != null) {
      final style = ratingEl.attributes['style'] ?? '';
      final posMatch = RegExp(r'background-position:\s*(-?\d+)px\s+(-?\d+)px')
          .firstMatch(style);
      if (posMatch != null) {
        final x = int.tryParse(posMatch.group(1)!) ?? 0;
        final y = int.tryParse(posMatch.group(2)!) ?? 0;
        double rating = 5.0 + x / 16.0;
        if (y <= -21) rating -= 0.5;
        final clamped = rating.clamp(0.0, 5.0);
        if (clamped.isFinite) {
          extra['rating'] = clamped;
        }
      }
    }

    // Uploader from common link selectors
    for (final sel in [
      '.gl3e a',
      '.gl4c a',
      'td.glhide a',
      'a[href*="uploader"]'
    ]) {
      final el = element.querySelector(sel);
      if (el != null) {
        final text = el.text.trim();
        if (text.isNotEmpty) {
          extra['uploader'] = text;
          break;
        }
      }
    }

    // Tags: compact (.gt*) and extended (gl2e…) — EH highlights watched tags via inline style
    // (same as EHSpiderParser._parseCompactGalleryTags / _parseExtendedGalleryTags).
    // Extra selectors cover newer table/thumbnail layouts where tags moved to sibling cells.
    final tagElements = <Element>[
      ...element
          .querySelectorAll('.gt, .gtl, .gtw, div.gt, div.gtl, div.gtw, a.gt'),
      ...element.querySelectorAll(
          '.gl1e .gtl, .gl1e .gt, .gl5c .gtl, .gl3c .gtl, .gl4c .gtl'),
      ...element.querySelectorAll(
        '.gl2e > div > a > div > div:nth-child(1) > table > tbody > tr > td > div',
      ),
    ];
    final tags = _parseGalleryRowTags(tagElements);
    if (tags.isNotEmpty) extra['tags'] = tags;

    return extra;
  }

  /// Per-namespace list of `{tag, color?, backgroundColor?}` (ARGB ints) for watched-tag styling.
  Map<String, List<Map<String, dynamic>>> _parseGalleryRowTags(
      List<Element> tagElements) {
    final tags = <String, List<Map<String, dynamic>>>{};
    final seen = <String>{};

    for (final tagEl in tagElements) {
      final title = tagEl.attributes['title'] ?? tagEl.text.trim();
      if (!title.contains(':')) continue;

      final idx = title.indexOf(':');
      final ns = title.substring(0, idx);
      final tagName = title.substring(idx + 1);
      final dedupeKey = '$ns:$tagName';
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);

      final style = EhTagStyleParse.mergedInlineStyles(tagEl);
      final colorArgb = EhTagStyleParse.foregroundArgb(style);
      final bgArgb = EhTagStyleParse.watchedBackgroundArgb(style);

      final m = <String, dynamic>{'tag': tagName};
      if (colorArgb != null) m['color'] = colorArgb;
      if (bgArgb != null) m['backgroundColor'] = bgArgb;
      tags.putIfAbsent(ns, () => []).add(m);
    }
    return tags;
  }
}
