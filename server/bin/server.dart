import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'package:jhentai_server/src/config/server_config.dart';
import 'package:jhentai_server/src/core/database.dart';
import 'package:jhentai_server/src/core/log.dart';
import 'package:jhentai_server/src/debug_flags.dart';
import 'package:jhentai_server/src/middleware/auth_middleware.dart';
import 'package:jhentai_server/src/network/cookie_manager.dart';
import 'package:jhentai_server/src/network/eh_client.dart';
import 'package:jhentai_server/src/routes/router.dart';
import 'package:jhentai_server/src/service/archive_bot_service.dart';
import 'package:jhentai_server/src/service/archive_download_service.dart';
import 'package:jhentai_server/src/service/event_bus.dart';
import 'package:jhentai_server/src/service/gallery_download_service.dart';
import 'package:jhentai_server/src/service/local_gallery_service.dart';
import 'package:jhentai_server/src/service/super_resolution_service.dart';
import 'package:jhentai_server/src/service/tag_translation_service.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addOption('host', abbr: 'h', defaultsTo: '0.0.0.0')
    ..addOption('data-dir', abbr: 'd', defaultsTo: '')
    ..addOption('web-dir', abbr: 'w', defaultsTo: '');

  final results = parser.parse(args);

  final config = ServerConfig.fromEnv(
    dataDirOverride: results['data-dir'] != '' ? results['data-dir'] : null,
    webDirOverride: results['web-dir'] != '' ? results['web-dir'] : null,
    portOverride: int.tryParse(results['port']),
    hostOverride: results['host'] != '0.0.0.0' ? results['host'] : null,
  );

  await config.ensureDirectories();

  await log.init(config.logDir);
  log.info('JHenTai Server starting...');
  log.info('Data directory: ${config.dataDir}');
  log.info('Download directory: ${config.downloadDir}');

  await db.init(config.databasePath);

  // Auth middleware
  final authMiddleware = AuthMiddleware();
  await authMiddleware.init();

  final cookieManager = ServerCookieManager();
  await cookieManager.init();

  final ehClient = EHClient();
  await ehClient.init(
    cookieManager,
    connectTimeout:
        int.tryParse(db.readConfig('web_connect_timeout') ?? '') ?? 6000,
    receiveTimeout:
        int.tryParse(db.readConfig('web_receive_timeout') ?? '') ?? 6000,
  );

  // Restore persisted site preference
  final savedSite = db.readConfig('site');
  if (savedSite == 'EX' || savedSite == 'EH') {
    ehClient.site = savedSite!;
    log.info('Restored site preference: $savedSite');
  }

  final eventBus = EventBus();

  final archiveBotService = ArchiveBotService();
  await archiveBotService.init();

  final superResolutionService = SuperResolutionService(config, eventBus);
  await superResolutionService.init();

  final galleryDownloadService = GalleryDownloadService(
      ehClient, config, eventBus,
      superResolutionService: superResolutionService);
  await galleryDownloadService.init();

  final archiveDownloadService = ArchiveDownloadService(
      ehClient, config, eventBus,
      archiveBotService: archiveBotService,
      superResolutionService: superResolutionService);
  await archiveDownloadService.init();

  if (_restoreTasksAutomaticallyEnabled()) {
    try {
      final galleryRestored =
          await galleryDownloadService.restoreDownloadsFromMetadata();
      final archiveRestored =
          await archiveDownloadService.restoreDownloadsFromMetadata();
      log.info(
          'Auto-restored download tasks: gallery=$galleryRestored, archive=$archiveRestored');
    } catch (e, s) {
      log.error('Auto-restore download tasks failed', e, s);
    }
  }

  final localGalleryService = LocalGalleryService(config);
  await localGalleryService.init();

  final tagTranslationService = TagTranslationService();
  // Trigger background download of tag translations on startup
  tagTranslationService.refresh().catchError((e) {
    log.warning('Background tag translation download failed: $e');
    return <String, dynamic>{'success': false, 'message': '$e'};
  });

  final appRouter = AppRouter(
    ehClient: ehClient,
    galleryDownloadService: galleryDownloadService,
    archiveDownloadService: archiveDownloadService,
    archiveBotService: archiveBotService,
    localGalleryService: localGalleryService,
    config: config,
    eventBus: eventBus,
    authToken: authMiddleware.token,
    tagTranslationService: tagTranslationService,
    superResolutionService: superResolutionService,
  );

  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addMiddleware(authMiddleware.middleware)
      .addHandler(_buildHandler(appRouter.handler, config));

  final server = await shelf_io.serve(
    pipeline,
    config.host,
    config.port,
  );

  log.info('Server running at http://${server.address.host}:${server.port}');
  log.info(
      'API available at http://${server.address.host}:${server.port}/api/');
  if (jhImageProxyDebugEnabled()) {
    log.info(
        'JH_IMAGE_PROXY_DEBUG is on: verbose /api/proxy/image and /api/image success logs enabled');
  }

  bool shuttingDown = false;
  Future<void> shutdown() async {
    if (shuttingDown) return;
    shuttingDown = true;
    log.info('Shutting down...');
    eventBus.dispose();
    db.dispose();
    await server.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());
}

Handler _buildHandler(Handler apiHandler, ServerConfig config) {
  final webDir = config.webDir;
  if (webDir != null && Directory(webDir).existsSync()) {
    final staticHandler = createStaticHandler(
      webDir,
      defaultDocument: 'index.html',
    );
    final indexFile = File('$webDir/index.html');

    return (Request request) async {
      final path = request.url.path;
      if (path.startsWith('api/') || path.startsWith('ws/')) {
        return apiHandler(request);
      }
      final response = await staticHandler(request);
      if (request.method != 'GET' || response.statusCode != 404) {
        return _noCacheFlutterEntry(response, path);
      }
      final lastSegment =
          request.url.pathSegments.isEmpty ? '' : request.url.pathSegments.last;
      if (lastSegment.contains('.')) {
        return response;
      }
      return Response.ok(
        indexFile.openRead(),
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-cache',
        },
      );
    };
  }

  return apiHandler;
}

/// Flutter Web 入口文件禁用缓存，避免 Service Worker 一直加载旧构建：
/// index.html 与 flutter_bootstrap.js 每次重新校验，flutter_service_worker.js
/// 按规范也必须可更新，否则浏览器永远停留在旧版本页面。
Response _noCacheFlutterEntry(Response response, String path) {
  final name = path.split('/').last;
  if (name.isEmpty ||
      name == 'index.html' ||
      name == 'flutter_bootstrap.js' ||
      name == 'flutter_service_worker.js') {
    return response.change(headers: {'Cache-Control': 'no-cache'});
  }
  return response;
}

Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
  'Access-Control-Max-Age': '86400',
};

bool _restoreTasksAutomaticallyEnabled() {
  final raw = db.readConfig('webRestoreTasksAutomatically');
  if (raw == null || raw.trim().isEmpty) return false;
  final normalized = raw.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
