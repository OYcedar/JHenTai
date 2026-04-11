import 'package:html/parser.dart' as html_parser;

/// EH gallery index pagination cursors — parity with
/// [EHSpiderParser._galleryPageDocument2NextGid] / [_galleryPageDocument2PrevGid].
class EhGalleryListNavigation {
  EhGalleryListNavigation._();

  static final _nextRe = RegExp(r'next=([\d-]+)', caseSensitive: false);
  static final _prevRe = RegExp(r'prev=([\d-]+)', caseSensitive: false);

  static String? parseNextGid(String html) {
    final doc = html_parser.parse(html);
    var href = doc.querySelector('#unext')?.attributes['href'];
    href ??= doc.querySelector('a#dnext')?.attributes['href'];
    href ??= doc.querySelector('a[id="dnext"]')?.attributes['href'];
    return _nextRe.firstMatch(href ?? '')?.group(1);
  }

  static String? parsePrevGid(String html) {
    final doc = html_parser.parse(html);
    var href = doc.querySelector('#uprev')?.attributes['href'];
    href ??= doc.querySelector('a#dprev')?.attributes['href'];
    href ??= doc.querySelector('a[id="dprev"]')?.attributes['href'];
    return _prevRe.firstMatch(href ?? '')?.group(1);
  }
}
