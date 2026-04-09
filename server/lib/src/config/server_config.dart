import 'dart:io';

class ServerConfig {
  final String dataDir;
  final int port;
  final String host;
  final String? webDir;
  final List<String> extraScanPaths;

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

    return ServerConfig(
      dataDir: dataDir,
      port: port,
      host: host,
      webDir: webDir,
      extraScanPaths: extraPaths.where((p) => p.isNotEmpty).toList(),
    );
  }

  Future<void> ensureDirectories() async {
    for (final dir in [dataDir, downloadDir, localGalleryDir, logDir, tempDir, configDir]) {
      await Directory(dir).create(recursive: true);
    }
  }
}
