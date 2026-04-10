import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/web_locale_text.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_block_rules_page.dart';
import 'package:jhentai/src/pages_web/web_downloads_page.dart';
import 'package:jhentai/src/pages_web/web_gallery_detail_page.dart';
import 'package:jhentai/src/pages_web/web_history_page.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_local_page.dart';
import 'package:jhentai/src/pages_web/web_reader_page.dart';
import 'package:jhentai/src/pages_web/web_settings_page.dart';
import 'package:jhentai/src/pages_web/web_thumbnails_page.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final serverUrl = Uri.base.origin;

  final savedToken = web.window.localStorage.getItem('jh_api_token');

  backendApiClient.init(baseUrl: serverUrl, token: savedToken);

  Get.put(ThemeController());
  Get.put(WebLayoutController());
  Get.put(WebDownloadService());

  runApp(const JHenTaiWebApp());
}

class WebLayoutController extends GetxController {
  final selectedGid = Rxn<int>();
  final selectedToken = Rxn<String>();
  final leftPaneIndex = 0.obs;

  void selectGallery(int gid, String token) {
    selectedGid.value = gid;
    selectedToken.value = token;
  }

  void clearSelection() {
    selectedGid.value = null;
    selectedToken.value = null;
  }
}

class WebDownloadService extends GetxController {
  final galleryTasks = <int, Map<String, dynamic>>{}.obs;
  final archiveTasks = <int, Map<String, dynamic>>{}.obs;
  final isLoaded = false.obs;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  @override
  void onInit() {
    super.onInit();
    if (backendApiClient.hasToken) {
      _loadTasks();
      _connectWebSocket();
    }
  }

  @override
  void onClose() {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.onClose();
  }

  void activate() {
    if (isLoaded.value) return;
    _loadTasks();
    _connectWebSocket();
  }

  Future<void> _loadTasks() async {
    try {
      final gTasks = await backendApiClient.listGalleryDownloads();
      final gMap = <int, Map<String, dynamic>>{};
      for (final t in gTasks) {
        final task = t as Map<String, dynamic>;
        final gid = task['gid'] as int;
        gMap[gid] = task;
      }
      galleryTasks.value = gMap;

      final aTasks = await backendApiClient.listArchiveDownloads();
      final aMap = <int, Map<String, dynamic>>{};
      for (final t in aTasks) {
        final task = t as Map<String, dynamic>;
        final gid = task['gid'] as int;
        aMap[gid] = task;
      }
      archiveTasks.value = aMap;
      isLoaded.value = true;
    } catch (e) {
      debugPrint('WebDownloadService load failed: $e');
    }
  }

  void _connectWebSocket() {
    if (isClosed) return;
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();

    try {
      final wsUrl = backendApiClient.baseUrl.replaceFirst('http', 'ws');
      final wsToken = backendApiClient.currentToken ?? '';
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws/events?token=$wsToken'),
      );
      _reconnectAttempts = 0;

      _wsSubscription = _wsChannel!.stream.listen(
        (data) => _handleWsMessage(data.toString()),
        onError: (e) {
          debugPrint('WDS WebSocket error: $e');
          _scheduleReconnect();
        },
        onDone: () => _scheduleReconnect(),
      );
    } catch (e) {
      debugPrint('WDS WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (isClosed) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: (_reconnectAttempts * 2).clamp(1, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connectWebSocket);
  }

  void _handleWsMessage(String message) {
    try {
      final event = jsonDecode(message) as Map<String, dynamic>;
      final eventType = event['event'] as String?;
      final data = event['data'] as Map<String, dynamic>?;
      if (data == null) return;

      if (eventType == 'gallery_download_progress') {
        final gid = data['gid'] as int;
        galleryTasks[gid] = data;
      } else if (eventType == 'archive_download_progress') {
        final gid = data['gid'] as int;
        archiveTasks[gid] = data;
      } else if (eventType == 'download_removed') {
        _loadTasks();
      }
    } catch (e) {
      debugPrint('WDS WS parse error: $e');
    }
  }

  Map<String, dynamic>? getGalleryTask(int gid) => galleryTasks[gid];
  Map<String, dynamic>? getArchiveTask(int gid) => archiveTasks[gid];

  int? getGalleryStatus(int gid) => galleryTasks[gid]?['status'] as int?;
  int? getArchiveStatus(int gid) => archiveTasks[gid]?['status'] as int?;

  bool isGalleryDownloaded(int gid) => getGalleryStatus(gid) == 3;
  bool isGalleryDownloading(int gid) => getGalleryStatus(gid) == 1;

  Future<void> pauseGallery(int gid) => backendApiClient.pauseGalleryDownload(gid);
  Future<void> resumeGallery(int gid) => backendApiClient.resumeGalleryDownload(gid);
  Future<void> deleteGallery(int gid) => backendApiClient.deleteGalleryDownload(gid);
  Future<void> pauseArchive(int gid) => backendApiClient.pauseArchiveDownload(gid);
  Future<void> resumeArchive(int gid) => backendApiClient.resumeArchiveDownload(gid);
  Future<void> deleteArchive(int gid) => backendApiClient.deleteArchiveDownload(gid);

  Future<void> refresh() => _loadTasks();
}

class ThemeController extends GetxController {
  final themeMode = ThemeMode.system.obs;
  final Rx<Color> seedColor = Rx<Color>(Colors.deepPurple);

  static const _themeModeKey = 'jh_theme_mode';
  static const _seedColorKey = 'jh_seed_color';

  static const seedColors = <Color>[
    Colors.deepPurple,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.grey,
  ];

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final modeStr = web.window.localStorage.getItem(_themeModeKey);
    if (modeStr != null) {
      themeMode.value = switch (modeStr) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }
    final colorStr = web.window.localStorage.getItem(_seedColorKey);
    if (colorStr != null) {
      final colorVal = int.tryParse(colorStr);
      if (colorVal != null) {
        seedColor.value = Color(colorVal);
      }
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    web.window.localStorage.setItem(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
    Get.changeThemeMode(mode);
  }

  void setSeedColor(Color color) {
    seedColor.value = color;
    web.window.localStorage.setItem(_seedColorKey, color.toARGB32().toString());
    Get.changeTheme(_buildTheme(Brightness.light, color));
    Get.changeTheme(_buildTheme(Brightness.dark, color));
    Get.forceAppUpdate();
  }

  static ThemeData _buildTheme(Brightness brightness, Color seed) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
      ),
    );
  }
}

class JHenTaiWebApp extends StatelessWidget {
  const JHenTaiWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = _detectLocale();
    final tc = Get.find<ThemeController>();

    return Obx(() => GetMaterialApp(
      title: 'JHenTai',
      translations: WebLocaleText(),
      themeMode: tc.themeMode.value,
      theme: ThemeController._buildTheme(Brightness.light, tc.seedColor.value),
      darkTheme: ThemeController._buildTheme(Brightness.dark, tc.seedColor.value),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('ko', 'KR'),
        Locale('pt', 'BR'),
        Locale('ru', 'RU'),
      ],
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      getPages: _webRoutes,
      initialRoute: backendApiClient.hasToken ? '/web/home' : '/web/setup',
    ));
  }

  Locale _detectLocale() {
    final saved = web.window.localStorage.getItem('jh_web_locale');
    if (saved != null && saved.contains('_')) {
      final parts = saved.split('_');
      return Locale(parts[0], parts.length > 1 ? parts[1] : '');
    }
    final platformLocale = PlatformDispatcher.instance.locale;
    const supported = [
      Locale('en', 'US'),
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('ko', 'KR'),
      Locale('pt', 'BR'),
      Locale('ru', 'RU'),
    ];
    for (final loc in supported) {
      if (loc.languageCode == platformLocale.languageCode) {
        if (loc.countryCode == platformLocale.countryCode) return loc;
      }
    }
    for (final loc in supported) {
      if (loc.languageCode == platformLocale.languageCode) return loc;
    }
    return const Locale('en', 'US');
  }
}

final _webRoutes = [
  GetPage(
    name: '/web/setup',
    page: () => const WebSetupPage(),
  ),
  GetPage(
    name: '/web/home',
    page: () => const WebHomePage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebHomeController());
    }),
  ),
  GetPage(
    name: '/web/gallery/:gid/:token',
    page: () => const WebGalleryDetailPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebGalleryDetailController());
    }),
  ),
  GetPage(
    name: '/web/reader/:gid/:token',
    page: () => const WebReaderPage(),
    binding: BindingsBuilder(() {
      final controller = WebReaderController();
      final args = Get.arguments;
      if (args is Map<String, dynamic> && args['images'] is List<String>) {
        controller.localImages = args['images'] as List<String>;
      }
      Get.lazyPut(() => controller);
    }),
  ),
  GetPage(
    name: '/web/downloads',
    page: () => const WebDownloadsPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebDownloadsController());
    }),
  ),
  GetPage(
    name: '/web/local',
    page: () => const WebLocalPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebLocalController());
    }),
  ),
  
  GetPage(
    name: '/web/settings',
    page: () => const WebSettingsPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebSettingsController());
    }),
  ),
  GetPage(
    name: '/web/history',
    page: () => const WebHistoryPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebHistoryController());
    }),
  ),
  GetPage(
    name: '/web/thumbnails/:gid/:token',
    page: () => const WebThumbnailsPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebThumbnailsController());
    }),
  ),
  GetPage(
    name: '/web/block-rules',
    page: () => const WebBlockRulesPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebBlockRulesController());
    }),
  ),
];

class WebSetupPage extends StatefulWidget {
  const WebSetupPage({super.key});

  @override
  State<WebSetupPage> createState() => _WebSetupPageState();
}

class _WebSetupPageState extends State<WebSetupPage> {
  final _tokenController = TextEditingController();
  bool _verifying = false;
  String? _error;

  static const _tokenLen = 64;

  @override
  void initState() {
    super.initState();
    _tokenController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final len = _tokenController.text.trim().length;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('setup.title'.tr,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'setup.description'.tr,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'setup.tokenHint'.tr,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _tokenController,
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'setup.tokenLabel'.tr,
                      hintText: 'setup.tokenPasteHint'.tr,
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      alignLabelWithHint: true,
                      counterText: 'setup.tokenCharCount'.trParams({
                        'current': '$len',
                        'total': '$_tokenLen',
                      }),
                    ),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _verifying ? null : _verify,
                      child: _verifying
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('setup.connect'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verify() async {
    final token = _tokenController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (token.isEmpty) {
      setState(() => _error = 'setup.emptyToken'.tr);
      return;
    }
    if (token.length != _tokenLen || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(token)) {
      setState(() => _error = 'setup.tokenWrongLength'.tr);
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    final valid = await backendApiClient.verifyToken(token);
    if (valid) {
      backendApiClient.setToken(token);
      web.window.localStorage.setItem('jh_api_token', token);
      Get.offAllNamed('/web/home');
    } else {
      setState(() {
        _verifying = false;
        _error = 'setup.invalidToken'.tr;
      });
    }
  }
}
