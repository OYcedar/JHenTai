import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../network/eh_client.dart';
import '../utils/gallery_stats_parser.dart';
import 'block_rule_routes.dart';

class GalleryRoutes {
  final EHClient _client;

  GalleryRoutes(this._client);

  Router get router {
    final router = Router();

    router.get('/list', _galleryList);
    router.get('/list-by-url', _galleryListByUrl);
    router.get('/stats/<gid>/<token>', _galleryStats);
    router.post('/image-lookup', _galleryImageLookup);
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

  Future<Response> _galleryStats(Request request, String gid, String token) async {
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
      return Response.ok(jsonEncode(stats), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch stats: $e'}),
      );
    }
  }

  Future<Response> _galleryListByUrl(Request request) async {
    final raw = request.url.queryParameters['url'];
    if (raw == null || raw.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing url query parameter'}));
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
      galleries['prevUrl'] = _normalizeListHref(galleries['prevUrl'] as String?, origin);
      galleries['nextUrl'] = _normalizeListHref(galleries['nextUrl'] as String?, origin);
      final list = galleries['galleries'] as List<Map<String, dynamic>>?;
      if (list != null) {
        for (final g in list) {
          final u = g['url'] as String? ?? '';
          if (u.isNotEmpty) g['url'] = _normalizeListHref(u, origin);
        }
      }
      final blockRules = db.selectAllBlockRules();
      if (blockRules.isNotEmpty && list != null) {
        list.removeWhere((g) => blockRules.any((rule) => matchesBlockRule(rule, g)));
      }
      return Response.ok(jsonEncode(galleries), headers: {'Content-Type': 'application/json'});
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
      return Response.badRequest(body: jsonEncode({'error': 'Missing imageBase64'}));
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

  Future<Response> _galleryList(Request request) async {
    final page = request.url.queryParameters['page'];
    final search = request.url.queryParameters['f_search'];
    final section = request.url.queryParameters['section'] ?? 'home';

    final tl = request.url.queryParameters['tl'];

    final url = switch (section) {
      'popular' => '${_client.baseUrl}/popular',
      'favorites' => '${_client.baseUrl}/favorites.php',
      'watched' => '${_client.baseUrl}/watched',
      'ranklist' => '${_client.baseUrl}/toplist.php',
      _ => _client.baseUrl,
    };

    // EH/EX gallery index uses `page` as 0-based offset pages (same as WebHomeController.currentPage).
    final queryParams = <String, dynamic>{};
    if (page != null) queryParams['page'] = page;
    if (search != null && search.isNotEmpty) queryParams['f_search'] = search;

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
        // Align with native [SearchConfig]: disable language filter on index search.
        'f_sfl',
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
      final result = await _client.proxyGet(url, queryParams: queryParams.isNotEmpty ? queryParams : null);
      final html = result['data']?.toString() ?? '';
      final galleries = _parseGalleryListHtml(html);

      // Make list API match list-by-url: absolute prev/next and gallery hrefs (client expects full URLs).
      final origin = _client.baseUrl;
      galleries['prevUrl'] = _normalizeListHref(galleries['prevUrl'] as String?, origin);
      galleries['nextUrl'] = _normalizeListHref(galleries['nextUrl'] as String?, origin);
      final listForNorm = galleries['galleries'] as List<Map<String, dynamic>>?;
      if (listForNorm != null) {
        for (final g in listForNorm) {
          final u = g['url'] as String? ?? '';
          if (u.isNotEmpty) {
            g['url'] = _normalizeListHref(u, origin);
          }
        }
      }

      final blockRules = db.selectAllBlockRules();
      if (blockRules.isNotEmpty) {
        final list = galleries['galleries'] as List<Map<String, dynamic>>?;
        if (list != null) {
          list.removeWhere((g) => blockRules.any((rule) => matchesBlockRule(rule, g)));
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

  Future<Response> _galleryDetail(Request request, String gid, String token) async {
    final galleryUrl = '${_client.baseUrl}/g/$gid/$token/';

    try {
      final detail = await _client.fetchGalleryDetail(galleryUrl);
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
          'apiuid': detail.apiuid,
          'apikey': detail.apikey,
          'favoriteSlot': detail.favoriteSlot,
          'favoriteName': detail.favoriteName,
          'comments': detail.comments,
          'publishDate': detail.publishDate,
          'fileSize': detail.fileSize,
          'language': detail.language,
          'parentUrl': detail.parentUrl,
          'ratingCount': detail.ratingCount,
          'newerVersionUrl': detail.newerVersionUrl,
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

  Future<Response> _galleryImagePages(Request request, String gid, String token) async {
    final galleryUrl = '${_client.baseUrl}/g/$gid/$token/';

    try {
      final allPageUrls = <String>[];
      final allThumbUrls = <String>[];
      final allGalleryThumbs = <Map<String, dynamic>>[];
      var pageUrl = galleryUrl;
      int totalPages = 0;

      while (true) {
        final result = await _client.proxyGet(pageUrl);
        final html = result['data']?.toString() ?? '';
        final doc = html_parser.parse(html);

        if (totalPages == 0) {
          final pageCountText = doc.querySelector('.gpc')?.text ?? '';
          final countMatch = RegExp(r'of (\d+)').firstMatch(pageCountText);
          totalPages = int.tryParse(countMatch?.group(1) ?? '') ?? 0;
        }

        _client.appendGalleryThumbPageData(html, pageUrl, allPageUrls, allThumbUrls, allGalleryThumbs);

        final nextLink = doc.querySelector('.ptt td:last-child a');
        final nextHref = nextLink?.attributes['href'];
        if (nextHref == null || nextHref == pageUrl) break;
        if (allPageUrls.length >= totalPages && totalPages > 0) break;
        pageUrl = nextHref;
      }

      return Response.ok(
        jsonEncode({
          'imagePageUrls': allPageUrls,
          'thumbnailImageUrls': allThumbUrls,
          'galleryThumbnails': allGalleryThumbs,
          'totalPages': totalPages > 0 ? totalPages : allPageUrls.length,
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
    final tr = doc.querySelector('.ptt > tbody > tr') ?? doc.querySelector('table.ptt tr');
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
      if (t == '<' || t == '‹' || t.toLowerCase() == 'prev' || t.toLowerCase() == 'previous') return true;
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
      nextEl = doc.querySelector('.ptt td:nth-last-child(2) a');
      if (nextEl != null && !isLastPageJump(nextEl) && looksLikeNextNav(nextEl)) {
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
      final last = doc.querySelector('.ptt td:last-child a');
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
      if (prevEl != null && !isFirstPageJump(prevEl) && looksLikePrevNav(prevEl)) {
        prevUrl = href(prevEl) ?? '';
      }
    }

    if (prevUrl.isEmpty) {
      prevEl = doc.querySelector('.ptt td:first-child a');
      if (prevEl != null && !isFirstPageJump(prevEl) && looksLikePrevNav(prevEl)) {
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

    final rows = doc.querySelectorAll('.glte, .gl1t, .gl3t, tr.gtr0, tr.gtr1, .itg tr');

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

        final extra = _parseRowMetadata(parent ?? a);

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

  Map<String, dynamic> _parseRowMetadata(dynamic element) {
    final extra = <String, dynamic>{};

    // Page count: look for "N pages" text
    final allText = element.text ?? '';
    final pageMatch = RegExp(r'(\d+)\s*pages?').firstMatch(allText);
    if (pageMatch != null) {
      extra['pageCount'] = int.tryParse(pageMatch.group(1)!) ?? 0;
    }

    // Rating from .ir star background-position
    final ratingEl = element.querySelector('.ir');
    if (ratingEl != null) {
      final style = ratingEl.attributes['style'] ?? '';
      final posMatch = RegExp(r'background-position:\s*(-?\d+)px\s+(-?\d+)px').firstMatch(style);
      if (posMatch != null) {
        final x = int.tryParse(posMatch.group(1)!) ?? 0;
        final y = int.tryParse(posMatch.group(2)!) ?? 0;
        double rating = 5.0 + x / 16.0;
        if (y <= -21) rating -= 0.5;
        extra['rating'] = rating.clamp(0.0, 5.0);
      }
    }

    // Uploader from common link selectors
    for (final sel in ['.gl3e a', '.gl4c a', 'td.glhide a', 'a[href*="uploader"]']) {
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
      ...element.querySelectorAll('.gt, .gtl, .gtw, div.gt, div.gtl, div.gtw, a.gt'),
      ...element.querySelectorAll('.gl1e .gtl, .gl1e .gt, .gl5c .gtl, .gl3c .gtl, .gl4c .gtl'),
      ...element.querySelectorAll(
        '.gl2e > div > a > div > div:nth-child(1) > table > tbody > tr > td > div',
      ),
    ];
    final tags = _parseGalleryRowTags(tagElements);
    if (tags.isNotEmpty) extra['tags'] = tags;

    return extra;
  }

  /// Per-namespace list of `{tag, color?, backgroundColor?}` (ARGB ints) for watched-tag styling.
  Map<String, List<Map<String, dynamic>>> _parseGalleryRowTags(List<Element> tagElements) {
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

      final style = _mergedInlineStyles(tagEl);
      final colorArgb = _parseEhTagForegroundArgb(style);
      final bgArgb = _parseEhTagWatchedBackgroundArgb(style);

      final m = <String, dynamic>{'tag': tagName};
      if (colorArgb != null) m['color'] = colorArgb;
      if (bgArgb != null) m['backgroundColor'] = bgArgb;
      tags.putIfAbsent(ns, () => []).add(m);
    }
    return tags;
  }

  /// EH may put `style` on the tag node or an ancestor; merge a few levels for robustness.
  String _mergedInlineStyles(Element? el, {int maxDepth = 5}) {
    final sb = StringBuffer();
    Element? cur = el;
    for (var i = 0; i < maxDepth && cur != null; i++) {
      final s = cur.attributes['style'];
      if (s != null && s.isNotEmpty) {
        sb.write(s);
        if (!s.endsWith(';')) sb.write(';');
      }
      final p = cur.parent;
      cur = p is Element ? p : null;
    }
    return sb.toString();
  }

  int? _parseEhTagForegroundArgb(String style) {
    var m = RegExp(r'color\s*:\s*#([0-9a-fA-F]{6})\b', caseSensitive: false).firstMatch(style);
    m ??= RegExp(r'color\s*:\s*#([0-9a-fA-F]{3})\b', caseSensitive: false).firstMatch(style);
    if (m == null) return null;
    var hex = m.group(1)!;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    return int.tryParse('FF$hex', radix: 16);
  }

  int? _parseEhTagWatchedBackgroundArgb(String style) {
    final twoStop = RegExp(
      r'(?:background\s*:\s*)?radial-gradient\([^#]*#([0-9a-fA-F]{6})[^#]*,\s*#([0-9a-fA-F]{6})',
      caseSensitive: false,
    ).firstMatch(style);
    if (twoStop != null && twoStop.groupCount >= 2) {
      final outer = twoStop.group(2);
      if (outer != null) return int.tryParse('FF$outer', radix: 16);
    }
    final oneStop = RegExp(
      r'(?:background\s*:\s*)?radial-gradient\([^)]*#([0-9a-fA-F]{6})',
      caseSensitive: false,
    ).firstMatch(style);
    if (oneStop != null) {
      final g = oneStop.group(1);
      if (g != null) return int.tryParse('FF$g', radix: 16);
    }
    final solid = RegExp(
      r'background(?:-color)?\s*:\s*#([0-9a-fA-F]{6})\b',
      caseSensitive: false,
    ).firstMatch(style);
    if (solid != null) {
      final g = solid.group(1);
      if (g != null) return int.tryParse('FF$g', radix: 16);
    }
    return null;
  }
}
