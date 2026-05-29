import 'dart:convert';

import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/database.dart';

const webExtraLocalGalleryScanPathsKey = 'web_extra_local_gallery_scan_paths';

List<String> effectiveLocalGalleryScanPaths(ServerConfig config) {
  final paths = <String>[
    config.localGalleryDir,
    ...config.extraScanPaths,
    ...webExtraLocalGalleryScanPaths(),
  ];
  final seen = <String>{};
  return [
    for (final path in paths)
      if (path.trim().isNotEmpty && seen.add(p.canonicalize(path.trim())))
        path.trim(),
  ];
}

bool isPathUnderLocalGalleryScanPath(String path, ServerConfig config) {
  final resolved = p.canonicalize(path);
  return effectiveLocalGalleryScanPaths(config).any((scanPath) {
    final resolvedScanPath = p.canonicalize(scanPath);
    return resolved == resolvedScanPath ||
        resolved.startsWith('$resolvedScanPath/');
  });
}

List<String> webExtraLocalGalleryScanPaths() {
  final raw = db.readConfig(webExtraLocalGalleryScanPathsKey);
  if (raw == null || raw.trim().isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const [];
}

void saveWebExtraLocalGalleryScanPaths(List<String> paths) {
  final seen = <String>{};
  final normalized = [
    for (final path in paths)
      if (path.trim().isNotEmpty && seen.add(p.canonicalize(path.trim())))
        path.trim(),
  ];
  db.writeConfig(webExtraLocalGalleryScanPathsKey, jsonEncode(normalized));
}

void removeWebExtraLocalGalleryScanPath(String path) {
  final target = p.canonicalize(path.trim());
  final paths = webExtraLocalGalleryScanPaths()
      .where((item) => p.canonicalize(item.trim()) != target)
      .toList();
  saveWebExtraLocalGalleryScanPaths(paths);
}
