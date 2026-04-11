import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_tag_key_normalize.dart';
import 'package:jhentai/src/utils/color_util.dart';

/// Merges EH `/mytags` colors into gallery list/detail (parity with native
/// [MyTagsSetting] + [DetailsPageLogic._addColor2WatchedTags]).
class WebWatchedTagStylesController extends GetxController {
  /// `namespace:key` → background ARGB (only tags with `watched: true` on /mytags).
  final backgroundArgbByTagKey = Rx<Map<String, int>>({});

  static int _colorToArgb(Color c) {
    final a = (c.a * 255.0).round() & 0xff;
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  void _putWatchedBackground(Map<String, int> into, String namespace, String key, int argb) {
    for (final variant in webTagMapKeyVariants(namespace, key)) {
      into[variant] = argb;
    }
  }

  void _mergeTagSetResponse(Map<String, dynamic> data, Map<String, int> into) {
    final setBg = aRGBString2Color(data['tagSetBackgroundColor'] as String?);
    final tags = (data['tags'] as List?) ?? [];
    for (final raw in tags) {
      if (raw is! Map) continue;
      if (raw['watched'] != true) continue;
      final ns = raw['namespace']?.toString() ?? '';
      final key = raw['key']?.toString() ?? '';
      if (ns.isEmpty || key.isEmpty) continue;
      final tc = aRGBString2Color(raw['tagColor'] as String?);
      final bg = tc ?? setBg ?? UIConfig.ehWatchedTagDefaultBackGroundColor;
      _putWatchedBackground(into, ns, key, _colorToArgb(bg));
    }
  }

  /// Loads all tag sets (same spirit as native [MyTagsSetting.refreshAllOnlineTagSets]).
  Future<void> refresh() async {
    if (!backendApiClient.hasToken) return;
    try {
      final first = await backendApiClient.listUsertags(tagset: 1);
      final merged = <String, int>{};
      _mergeTagSetResponse(first, merged);

      final sets = (first['tagSets'] as List?) ?? [];
      for (final s in sets) {
        if (s is! Map) continue;
        final n = (s['number'] as num?)?.toInt();
        if (n == null || n == 1) continue;
        try {
          final m = await backendApiClient.listUsertags(tagset: n);
          _mergeTagSetResponse(m, merged);
        } catch (e, st) {
          debugPrint('WebWatchedTagStylesController: tagset $n failed: $e');
          debugPrint('$st');
        }
      }
      backgroundArgbByTagKey.value = merged;
    } catch (e, st) {
      debugPrint('WebWatchedTagStylesController.refresh failed: $e');
      debugPrint('$st');
    }
  }

  /// Resolve `/mytags` background color using the same key variants as [_mergeTagSetResponse].
  static int? lookupBackgroundArgb(Map<String, int> map, String namespace, String tagKey) {
    for (final k in webTagMapKeyVariants(namespace, tagKey)) {
      final v = map[k];
      if (v != null) return v;
    }
    return null;
  }
}
