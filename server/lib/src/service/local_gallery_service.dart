import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/server_config.dart';
import '../core/log.dart';
import '../utils/archive_util.dart';

class LocalGallery {
  final String path;
  final String title;
  final int imageCount;
  final String? coverPath;

  LocalGallery({
    required this.path,
    required this.title,
    required this.imageCount,
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'imageCount': imageCount,
    'coverPath': coverPath,
  };
}

class LocalGalleryService {
  final ServerConfig _config;

  List<LocalGallery> _galleries = [];
  bool _scanning = false;

  List<LocalGallery> get galleries => List.unmodifiable(_galleries);
  bool get isScanning => _scanning;

  LocalGalleryService(this._config);

  Future<void> init() async {
    await refresh();
  }

  Future<void> refresh() async {
    if (_scanning) return;
    _scanning = true;

    try {
      final start = DateTime.now();
      _galleries = [];

      final scanPaths = <String>[_config.localGalleryDir, ..._config.extraScanPaths];

      for (final scanPath in scanPaths) {
        final dir = Directory(scanPath);
        if (!await dir.exists()) continue;
        await _scanDirectory(dir);
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      log.info('Local gallery scan complete: ${_galleries.length} galleries found in ${elapsed}ms');
    } catch (e, s) {
      log.error('Failed to scan local galleries', e, s);
    } finally {
      _scanning = false;
    }
  }

  List<String> get allowedScanPaths => [_config.localGalleryDir, ..._config.extraScanPaths];

  bool isPathAllowed(String path) {
    final resolved = p.canonicalize(path);
    return allowedScanPaths.any((allowed) {
      final resolvedAllowed = p.canonicalize(allowed);
      return resolved == resolvedAllowed || resolved.startsWith('$resolvedAllowed/');
    });
  }

  List<String> getGalleryImages(String galleryPath) {
    if (!isPathAllowed(galleryPath)) return [];

    final dir = Directory(galleryPath);
    if (!dir.existsSync()) return [];

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => isImageFile(f.path))
        .toList()
      ..sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));

    return files.map((f) => f.path).toList();
  }

  Future<void> _scanDirectory(Directory dir) async {
    try {
      final entities = await dir.list().toList();
      final subDirs = entities.whereType<Directory>().toList();
      final imageFiles = entities.whereType<File>().where((f) => isImageFile(f.path)).toList();

      if (imageFiles.isNotEmpty && !_isJHenTaiDownload(dir)) {
        final cover = imageFiles.isNotEmpty
            ? (imageFiles..sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)))).first.path
            : null;

        _galleries.add(LocalGallery(
          path: dir.path,
          title: p.basename(dir.path),
          imageCount: imageFiles.length,
          coverPath: cover,
        ));
      }

      for (final subDir in subDirs) {
        await _scanDirectory(subDir);
      }
    } catch (e) {
      log.warning('Failed to scan directory: ${dir.path}', e);
    }
  }

  bool _isJHenTaiDownload(Directory dir) {
    return File(p.join(dir.path, 'metadata')).existsSync() ||
           File(p.join(dir.path, 'ametadata')).existsSync() ||
           File(p.join(dir.path, 'metadata.json')).existsSync();
  }
}
