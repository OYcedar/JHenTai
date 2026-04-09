import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';

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

    final url = switch (section) {
      'popular' => '${_client.baseUrl}/popular',
      'favorites' => '${_client.baseUrl}/favorites.php',
      'watched' => '${_client.baseUrl}/watched',
      _ => _client.baseUrl,
    };

    final queryParams = <String, dynamic>{};
    if (page != null) queryParams['page'] = page;
    if (search != null && search.isNotEmpty) queryParams['f_search'] = search;

    try {
      final result = await _client.proxyGet(url, queryParams: queryParams.isNotEmpty ? queryParams : null);
      final html = result['data']?.toString() ?? '';
      final galleries = _parseGalleryListHtml(html);

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
          'galleryUrl': galleryUrl,
          'tags': detail.tags,
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

        final links = doc.querySelectorAll('#gdt a');
        for (final a in links) {
          final href = a.attributes['href'] ?? '';
          if (href.contains('/s/')) {
            allPageUrls.add(href);
          }
        }

        final nextLink = doc.querySelector('.ptt td:last-child a');
        final nextHref = nextLink?.attributes['href'];
        if (nextHref == null || nextHref == pageUrl) break;
        if (allPageUrls.length >= totalPages && totalPages > 0) break;
        pageUrl = nextHref;
      }

      return Response.ok(
        jsonEncode({
          'imagePageUrls': allPageUrls,
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

    final rows = doc.querySelectorAll('.glte, .gl1t, .gl3t, tr.gtr0, tr.gtr1');

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
        final catEl = a.parent?.querySelector('.cn, .cs, .ct');
        if (catEl != null) category = catEl.text.trim();

        galleries.add({
          'gid': int.parse(gid),
          'token': match.group(2),
          'title': title,
          'coverUrl': coverUrl,
          'category': category,
          'url': href,
        });
      }
    } else {
      for (final row in rows) {
        final a = row.querySelector('a[href*="/g/"]');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        final match = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(href);
        if (match == null) continue;

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

        galleries.add({
          'gid': int.parse(match.group(1)!),
          'token': match.group(2),
          'title': title,
          'coverUrl': coverUrl,
          'category': category,
          'url': href,
        });
      }
    }

    // Parse pagination
    String prevUrl = '';
    String nextUrl = '';
    final prevEl = doc.querySelector('#uprev');
    final nextEl = doc.querySelector('#unext');
    if (prevEl != null) prevUrl = prevEl.attributes['href'] ?? '';
    if (nextEl != null) nextUrl = nextEl.attributes['href'] ?? '';

    return {
      'galleries': galleries,
      'prevUrl': prevUrl,
      'nextUrl': nextUrl,
    };
  }
}
