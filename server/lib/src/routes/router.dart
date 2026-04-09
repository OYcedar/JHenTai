import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/server_config.dart';
import '../network/eh_client.dart';
import '../service/archive_download_service.dart';
import '../service/event_bus.dart';
import '../service/gallery_download_service.dart';
import '../service/local_gallery_service.dart';
import 'auth_routes.dart';
import 'comment_routes.dart';
import 'download_routes.dart';
import 'favorite_routes.dart';
import 'gallery_routes.dart';
import 'history_routes.dart';
import 'image_routes.dart';
import 'local_routes.dart';
import 'proxy_routes.dart';
import 'rating_routes.dart';
import 'search_history_routes.dart';
import 'setting_routes.dart';

class AppRouter {
  final EHClient ehClient;
  final GalleryDownloadService galleryDownloadService;
  final ArchiveDownloadService archiveDownloadService;
  final LocalGalleryService localGalleryService;
  final ServerConfig config;
  final EventBus eventBus;
  final String authToken;

  AppRouter({
    required this.ehClient,
    required this.galleryDownloadService,
    required this.archiveDownloadService,
    required this.localGalleryService,
    required this.config,
    required this.eventBus,
    required this.authToken,
  });

  Handler get handler {
    final router = Router();

    router.mount('/api/proxy/', ProxyRoutes(ehClient).router.call);
    router.mount('/api/auth/', AuthRoutes(ehClient).router.call);
    router.mount('/api/gallery/', GalleryRoutes(ehClient).router.call);
    router.mount('/api/download/', DownloadRoutes(galleryDownloadService, archiveDownloadService, config).router.call);
    router.mount('/api/local/', LocalRoutes(localGalleryService).router.call);
    router.mount('/api/image/', ImageRoutes(config).router.call);
    router.mount('/api/setting/', SettingRoutes(config).router.call);
    router.mount('/api/favorite/', FavoriteRoutes(ehClient).router.call);
    router.mount('/api/rating/', RatingRoutes(ehClient).router.call);
    router.mount('/api/history/', HistoryRoutes().router.call);
    router.mount('/api/search-history/', SearchHistoryRoutes().router.call);
    router.mount('/api/comment/', CommentRoutes(ehClient).router.call);

    router.get('/api/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'version': '1.0.0',
          'loggedIn': ehClient.cookieManager.hasLoggedIn,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    router.post('/api/auth/token/verify', (Request request) async {
      final bodyStr = await request.readAsString();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
      }
      final token = body['token'] as String?;
      if (token == authToken) {
        return Response.ok(
          jsonEncode({'valid': true}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({'valid': false}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    router.get('/ws/events', _websocketHandler);

    return router.call;
  }

  Handler get _websocketHandler {
    return webSocketHandler((WebSocketChannel channel) {
      final subscription = eventBus.stream.listen((event) {
        try {
          channel.sink.add(eventBus.serializeEvent(event));
        } catch (_) {}
      });

      channel.stream.listen(
        (_) {},
        onDone: () => subscription.cancel(),
        onError: (_) => subscription.cancel(),
      );
    });
  }
}
