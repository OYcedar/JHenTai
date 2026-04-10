import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:web/web.dart' as web;

class WebSettingsPreferencePage extends StatelessWidget {
  const WebSettingsPreferencePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuPreference'.tr)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const _WebLanguageSubPage()),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text('tagTranslation.title'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const _WebTagTranslationSubPage()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text('settings.usertags'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed('/web/tag-sets'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text('blockRule.title'.tr),
            subtitle: Text('blockRule.manage'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed('/web/block-rules'),
          ),
          ListTile(
            leading: const Icon(Icons.bolt_outlined),
            title: Text('settings.openQuickSearch'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed('/web/quick-search'),
          ),
        ],
      ),
    );
  }
}

class _WebLanguageSubPage extends StatelessWidget {
  const _WebLanguageSubPage();

  @override
  Widget build(BuildContext context) {
    final currentLocale = Get.locale ?? const Locale('en', 'US');
    final options = <MapEntry<Locale, String>>[
      MapEntry(const Locale('en', 'US'), 'English'),
      MapEntry(const Locale('zh', 'CN'), '简体中文'),
      MapEntry(const Locale('zh', 'TW'), '繁體中文'),
      MapEntry(const Locale('ko', 'KR'), '한국어'),
      MapEntry(const Locale('pt', 'BR'), 'Português (BR)'),
      MapEntry(const Locale('ru', 'RU'), 'Русский'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('settings.language'.tr)),
      body: ListView(
        children: options
            .map((entry) => RadioListTile<String>(
                  title: Text(entry.value),
                  value: '${entry.key.languageCode}_${entry.key.countryCode}',
                  groupValue: '${currentLocale.languageCode}_${currentLocale.countryCode}',
                  onChanged: (v) {
                    Get.updateLocale(entry.key);
                    web.window.localStorage
                        .setItem('jh_web_locale', '${entry.key.languageCode}_${entry.key.countryCode}');
                    Get.back();
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _WebTagTranslationSubPage extends StatefulWidget {
  const _WebTagTranslationSubPage();

  @override
  State<_WebTagTranslationSubPage> createState() => _WebTagTranslationSubPageState();
}

class _WebTagTranslationSubPageState extends State<_WebTagTranslationSubPage> {
  final tagStatus = <String, dynamic>{}.obs;
  final isRefreshing = false.obs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      tagStatus.value = await backendApiClient.getTagTranslationStatus();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('tagTranslation.title'.tr)),
      body: Obx(() => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      tagStatus['loaded'] == true ? Icons.check_circle : Icons.info_outline,
                      color: tagStatus['loaded'] == true ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tagStatus['loaded'] == true
                            ? 'tagTranslation.loaded'.trParams({'count': '${tagStatus['count'] ?? 0}'})
                            : 'tagTranslation.notLoaded'.tr,
                      ),
                    ),
                  ],
                ),
                if (tagStatus['timestamp'] != null && (tagStatus['timestamp'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 28),
                    child: Text(
                      'tagTranslation.lastUpdate'
                          .trParams({'time': tagStatus['timestamp']?.toString() ?? ''}),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: isRefreshing.value
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text('tagTranslation.refresh'.tr),
                  onPressed: isRefreshing.value
                      ? null
                      : () async {
                          isRefreshing.value = true;
                          try {
                            final result = await backendApiClient.refreshTagTranslation();
                            if (result['success'] == true) {
                              Get.snackbar(
                                  'common.success'.tr,
                                  'tagTranslation.refreshSuccess'
                                      .trParams({'count': '${result['count'] ?? 0}'}),
                                  snackPosition: SnackPosition.BOTTOM);
                            } else {
                              Get.snackbar('common.error'.tr,
                                  result['message']?.toString() ?? 'common.failed'.tr,
                                  snackPosition: SnackPosition.BOTTOM);
                            }
                            await _load();
                          } catch (e) {
                            Get.snackbar('common.error'.tr,
                                'tagTranslation.refreshFailed'.trParams({'error': '$e'}),
                                snackPosition: SnackPosition.BOTTOM);
                          } finally {
                            isRefreshing.value = false;
                          }
                        },
                ),
              ],
            ),
          )),
    );
  }
}
