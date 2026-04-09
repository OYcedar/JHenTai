import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_downloads_page.dart';
import 'package:jhentai/src/pages_web/web_gallery_detail_page.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_local_page.dart';
import 'package:jhentai/src/pages_web/web_reader_page.dart';
import 'package:jhentai/src/pages_web/web_settings_page.dart';
import 'package:web/web.dart' as web;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final serverUrl = Uri.base.origin;

  final savedToken = web.window.localStorage.getItem('jh_api_token');

  backendApiClient.init(baseUrl: serverUrl, token: savedToken);

  runApp(const JHenTaiWebApp());
}

class JHenTaiWebApp extends StatelessWidget {
  const JHenTaiWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = _detectLocale();

    return GetMaterialApp(
      title: 'JHenTai',
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
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
      ],
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      getPages: _webRoutes,
      initialRoute: backendApiClient.hasToken ? '/web/home' : '/web/setup',
    );
  }

  Locale _detectLocale() {
    final platformLocale = PlatformDispatcher.instance.locale;
    const supported = [
      Locale('en', 'US'),
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('ko', 'KR'),
      Locale('pt', 'BR'),
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

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
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
      Get.lazyPut(() => WebReaderController());
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
    name: '/web/local/viewer',
    page: () => const WebLocalViewerPage(),
  ),
  GetPage(
    name: '/web/settings',
    page: () => const WebSettingsPage(),
    binding: BindingsBuilder(() {
      Get.lazyPut(() => WebSettingsController());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
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
                  Text('JHenTai Server Setup',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the API token shown in the server logs to connect.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      labelText: 'API Token',
                      border: const OutlineInputBorder(),
                      errorText: _error,
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
                          : const Text('Connect'),
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
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Please enter a token');
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
        _error = 'Invalid token. Check your server logs for the correct token.';
      });
    }
  }
}
