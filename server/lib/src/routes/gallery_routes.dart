import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../network/eh_client.dart';
import 'block_rule_routes.dart';

class GalleryRoutes {
  final EHClient _client;

  GalleryRoutes(this._client);

  Router get router {
    final router = Router();

    router.get('/list', _galleryList);
    router.get('/detail/<gid>/<token>', _galleryDetail);
    router.get('/images/<gid>/<token>', _galleryImagePages);

    return router;
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

    final queryParams = <String, dynamic>{};
    if (page != null) queryParams['page'] = page;
    if (search != null && search.isNotEmpty) queryParams['f_search'] = search;

    if (section == 'ranklist') {
      if (tl != null) queryParams['tl'] = tl;
    }
    if (section == 'favorites') {
      queryParams['inline_set'] = 'dm_e';
    }

    // Forward advanced search parameters
    for (final key in ['f_cats', 'f_sname', 'f_stags', 'f_sdesc', 'f_sh', 'advsearch', 'f_srdd', 'f_sr']) {
      final val = request.url.queryParameters[key];
      if (val != null && val.isNotEmpty) queryParams[key] = val;
    }

    try {
      final result = await _client.proxyGet(url, queryParams: queryParams.isNotEmpty ? queryParams : null);
      final html = result['data']?.toString() ?? '';
      final galleries = _parseGalleryListHtml(html);

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

    // Parse pagination from various page types
    String prevUrl = '';
    String nextUrl = '';
    final prevEl = doc.querySelector('#uprev, .ptt td:first-child a, a#dprev, a[id="dprev"]');
    final nextEl = doc.querySelector('#unext, .ptt td:last-child a, a#dnext, a[id="dnext"]');
    if (prevEl != null) prevUrl = prevEl.attributes['href'] ?? '';
    if (nextEl != null) nextUrl = nextEl.attributes['href'] ?? '';

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

    // Tags from .gt / .gtl / .gtw elements
    final tags = <String, List<String>>{};
    for (final tagEl in element.querySelectorAll('.gt, .gtl, .gtw')) {
      final title = tagEl.attributes['title'] ?? tagEl.text.trim();
      if (title.contains(':')) {
        final idx = title.indexOf(':');
        final ns = title.substring(0, idx);
        final tag = title.substring(idx + 1);
        tags.putIfAbsent(ns, () => []).add(tag);
      }
    }
    if (tags.isNotEmpty) extra['tags'] = tags;

    return extra;
  }
}
