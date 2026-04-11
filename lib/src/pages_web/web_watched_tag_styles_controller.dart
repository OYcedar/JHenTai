import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
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

  void _mergeTagSetResponse(Map<String, dynamic> data, Map<String, int> into) {
    final setBg = aRGBString2Color(data['tagSetBackgroundColor'] as String?);
    final tags = (data['tags'] as List?) ?? [];
    for (final raw in tags) {
      if (raw is! Map) continue;
      if (raw['watched'] != true) continue;
      final ns = raw['namespace']?.toString() ?? '';
      final key = raw['key']?.toString() ?? '';
      if (ns.isEmpty || key.isEmpty) continue;
      final mk = '$ns:$key';
      final tc = aRGBString2Color(raw['tagColor'] as String?);
      final bg = tc ?? setBg ?? UIConfig.ehWatchedTagDefaultBackGroundColor;
      into[mk] = _colorToArgb(bg);
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
        } catch (_) {}
      }
      backgroundArgbByTagKey.value = merged;
    } catch (_) {}
  }
}
