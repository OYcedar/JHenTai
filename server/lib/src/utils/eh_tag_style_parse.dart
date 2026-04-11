import 'package:html/dom.dart';

/// EH gallery list / detail tag nodes often use inline `style` (watched radial-gradient, color).
/// Shared by [GalleryRoutes] list parsing and [EHClient] gallery detail `#taglist` parsing.
class EhTagStyleParse {
  EhTagStyleParse._();

  /// EH may put `style` on the tag node or an ancestor; merge a few levels for robustness.
  static String mergedInlineStyles(Element? el, {int maxDepth = 5}) {
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

  static int? foregroundArgb(String style) {
    var m = RegExp(r'color\s*:\s*#([0-9a-fA-F]{6})\b', caseSensitive: false).firstMatch(style);
    m ??= RegExp(r'color\s*:\s*#([0-9a-fA-F]{3})\b', caseSensitive: false).firstMatch(style);
    if (m == null) return null;
    var hex = m.group(1)!;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    return int.tryParse('FF$hex', radix: 16);
  }

  static int? watchedBackgroundArgb(String style) {
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
