import '../config/server_config.dart';
import '../core/database.dart';

const webMaxConcurrentGalleryDownloadsKey =
    'web_max_concurrent_gallery_downloads';
const webMaxConcurrentArchiveDownloadsKey =
    'web_max_concurrent_archive_downloads';
const webDownloadAllGalleriesOfSamePriorityKey =
    'web_download_all_galleries_of_same_priority';
const webGalleryUpgradeReuseImagesKey = 'web_gallery_upgrade_reuse_images';
const webDeleteArchiveFileAfterDownloadKey =
    'web_delete_archive_file_after_download';

int effectiveMaxConcurrentGalleryDownloads(ServerConfig config) {
  return _readInt(
    webMaxConcurrentGalleryDownloadsKey,
    fallback: config.maxConcurrentGalleryDownloads,
    min: 1,
    max: 16,
  );
}

int effectiveMaxConcurrentArchiveDownloads(ServerConfig config) {
  return _readInt(
    webMaxConcurrentArchiveDownloadsKey,
    fallback: config.maxConcurrentArchiveDownloads,
    min: 1,
    max: 8,
  );
}

bool effectiveDownloadAllGalleriesOfSamePriority(ServerConfig config) {
  return _readBool(
    webDownloadAllGalleriesOfSamePriorityKey,
    fallback: config.downloadAllGalleriesOfSamePriority,
  );
}

bool effectiveGalleryUpgradeReuseImages(ServerConfig config) {
  return _readBool(
    webGalleryUpgradeReuseImagesKey,
    fallback: config.galleryUpgradeReuseImages,
  );
}

bool effectiveDeleteArchiveFileAfterDownload() {
  return _readBool(
    webDeleteArchiveFileAfterDownloadKey,
    fallback: true,
  );
}

int _readInt(
  String key, {
  required int fallback,
  required int min,
  required int max,
}) {
  final value = int.tryParse(db.readConfig(key) ?? '');
  return (value ?? fallback).clamp(min, max).toInt();
}

bool _readBool(String key, {required bool fallback}) {
  final value = db.readConfig(key);
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}
