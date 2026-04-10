import 'dart:io';

class ServerConfig {
  final String dataDir;
  final int port;
  final String host;
  final String? webDir;
  final List<String> extraScanPaths;
  final int maxConcurrentGalleryDownloads;
  final int maxConcurrentArchiveDownloads;

  /// When true and [jhApiSecret] is set, gallery upgrades may copy unchanged pages using JHenTai public hashes API.
  final bool galleryUpgradeReuseImages;
  final String jhPublicApiBaseUrl;
  final String jhAppId;
  final String jhApiSecret;

  String get downloadDir => '$dataDir/download';
  String get localGalleryDir => '$dataDir/local_gallery';
  String get databasePath => '$dataDir/db.sqlite';
  String get logDir => '$dataDir/logs';
  String get tempDir => '$dataDir/temp';
  String get configDir => '$dataDir/config';

  ServerConfig({
    required this.dataDir,
    this.port = 8080,
    this.host = '0.0.0.0',
    this.webDir,
    this.extraScanPaths = const [],
    this.maxConcurrentGalleryDownloads = 3,
    this.maxConcurrentArchiveDownloads = 2,
    this.galleryUpgradeReuseImages = true,
    this.jhPublicApiBaseUrl = 'https://jhentai.top',
    this.jhAppId = 'jhentai',
    this.jhApiSecret = '',
  });

  factory ServerConfig.fromEnv({
    String? dataDirOverride,
    String? webDirOverride,
    int? portOverride,
    String? hostOverride,
  }) {
    final dataDir = dataDirOverride ?? Platform.environment['JH_DATA_DIR'] ?? '/data';
    final port = portOverride ?? int.tryParse(Platform.environment['JH_PORT'] ?? '8080') ?? 8080;
    final host = hostOverride ?? Platform.environment['JH_HOST'] ?? '0.0.0.0';
    final webDir = webDirOverride ?? Platform.environment['JH_WEB_DIR'] ?? '/app/web';
    final extraPaths = Platform.environment['JH_EXTRA_SCAN_PATHS']?.split(',') ?? [];
    final maxG = int.tryParse(Platform.environment['JH_MAX_CONCURRENT_DOWNLOADS'] ?? '') ??
        int.tryParse(Platform.environment['JH_MAX_CONCURRENT_GALLERY_DOWNLOADS'] ?? '') ??
        3;
    final maxA = int.tryParse(Platform.environment['JH_MAX_CONCURRENT_ARCHIVE_DOWNLOADS'] ?? '') ?? 2;

    final reuse = _parseEnvBool(Platform.environment['JH_GALLERY_UPGRADE_REUSE_IMAGES'], defaultValue: true);
    final jhBase = Platform.environment['JH_JHENTAI_PUBLIC_API'] ?? 'https://jhentai.top';
    final jhApp = Platform.environment['JH_JHENTAI_APP_ID'] ?? 'jhentai';
    final jhSecret = Platform.environment['JH_JHENTAI_API_SECRET'] ?? '';

    return ServerConfig(
      dataDir: dataDir,
      port: port,
      host: host,
      webDir: webDir,
      extraScanPaths: extraPaths.where((p) => p.isNotEmpty).toList(),
      maxConcurrentGalleryDownloads: maxG.clamp(1, 16),
      maxConcurrentArchiveDownloads: maxA.clamp(1, 8),
      galleryUpgradeReuseImages: reuse,
      jhPublicApiBaseUrl: jhBase.replaceAll(RegExp(r'/$'), ''),
      jhAppId: jhApp,
      jhApiSecret: jhSecret,
    );
  }

  static bool _parseEnvBool(String? v, {required bool defaultValue}) {
    if (v == null || v.isEmpty) return defaultValue;
    final l = v.toLowerCase().trim();
    if (l == '0' || l == 'false' || l == 'no') return false;
    if (l == '1' || l == 'true' || l == 'yes') return true;
    return defaultValue;
  }

  Future<void> ensureDirectories() async {
    for (final dir in [dataDir, downloadDir, localGalleryDir, logDir, tempDir, configDir]) {
      await Directory(dir).create(recursive: true);
    }
  }
}
