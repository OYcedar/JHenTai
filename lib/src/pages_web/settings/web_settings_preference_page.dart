import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';
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
          const _WebDefaultSectionTile(),
          const _WebGalleryDisplaySection(),
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

class _WebGalleryDisplaySection extends StatefulWidget {
  const _WebGalleryDisplaySection();

  @override
  State<_WebGalleryDisplaySection> createState() =>
      _WebGalleryDisplaySectionState();
}

class _WebGalleryDisplaySectionState extends State<_WebGalleryDisplaySection> {
  late bool showAllGalleryTitles;
  late bool showGalleryTagVoteStatus;
  late bool showComments;
  late bool showAllComments;

  @override
  void initState() {
    super.initState();
    showAllGalleryTitles = WebPreferenceSettings.showAllGalleryTitles;
    showGalleryTagVoteStatus = WebPreferenceSettings.showGalleryTagVoteStatus;
    showComments = WebPreferenceSettings.showComments;
    showAllComments = WebPreferenceSettings.showAllComments;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.title),
          title: Text('showAllGalleryTitles'.tr),
          subtitle: Text('showAllGalleryTitlesHint'.tr),
          value: showAllGalleryTitles,
          onChanged: (value) {
            setState(() => showAllGalleryTitles = value);
            WebPreferenceSettings.saveShowAllGalleryTitles(value);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.how_to_vote_outlined),
          title: Text('showGalleryTagVoteStatus'.tr),
          subtitle: Text('showGalleryTagVoteStatusHint'.tr),
          value: showGalleryTagVoteStatus,
          onChanged: (value) {
            setState(() => showGalleryTagVoteStatus = value);
            WebPreferenceSettings.saveShowGalleryTagVoteStatus(value);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.comment_outlined),
          title: Text('showComments'.tr),
          value: showComments,
          onChanged: (value) {
            setState(() {
              showComments = value;
              if (!value) {
                showAllComments = false;
              }
            });
            WebPreferenceSettings.saveShowComments(value);
            if (!value) {
              WebPreferenceSettings.saveShowAllComments(false);
            }
          },
        ),
        if (showComments)
          SwitchListTile(
            secondary: const Icon(Icons.forum_outlined),
            title: Text('showAllComments'.tr),
            subtitle: Text('showAllCommentsHint'.tr),
            value: showAllComments,
            onChanged: (value) {
              setState(() => showAllComments = value);
              WebPreferenceSettings.saveShowAllComments(value);
            },
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _WebDefaultSectionTile extends StatefulWidget {
  const _WebDefaultSectionTile();

  @override
  State<_WebDefaultSectionTile> createState() => _WebDefaultSectionTileState();
}

class _WebDefaultSectionTileState extends State<_WebDefaultSectionTile> {
  late String section;

  @override
  void initState() {
    super.initState();
    final saved = web.window.localStorage
        .getItem(WebHomeController.defaultSectionStorageKey);
    section = saved != null && WebHomeController.defaultSections.contains(saved)
        ? saved
        : 'home';
  }

  String _label(String value) => switch (value) {
        'popular' => 'home.popular'.tr,
        'ranklist' => 'home.ranklist'.tr,
        'favorites' => 'home.favorites'.tr,
        'watched' => 'home.watched'.tr,
        _ => 'home.home'.tr,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.home_outlined),
      title: Text('defaultTab'.tr),
      trailing: DropdownButton<String>(
        value: section,
        alignment: AlignmentDirectional.centerEnd,
        items: [
          for (final value in WebHomeController.defaultSections)
            DropdownMenuItem(value: value, child: Text(_label(value))),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => section = value);
          web.window.localStorage
              .setItem(WebHomeController.defaultSectionStorageKey, value);
        },
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
                  groupValue:
                      '${currentLocale.languageCode}_${currentLocale.countryCode}',
                  onChanged: (v) {
                    Get.updateLocale(entry.key);
                    web.window.localStorage.setItem('jh_web_locale',
                        '${entry.key.languageCode}_${entry.key.countryCode}');
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
  State<_WebTagTranslationSubPage> createState() =>
      _WebTagTranslationSubPageState();
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
                      tagStatus['loaded'] == true
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: tagStatus['loaded'] == true
                          ? Colors.green
                          : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tagStatus['loaded'] == true
                            ? 'tagTranslation.loaded'.trParams(
                                {'count': '${tagStatus['count'] ?? 0}'})
                            : 'tagTranslation.notLoaded'.tr,
                      ),
                    ),
                  ],
                ),
                if (tagStatus['timestamp'] != null &&
                    (tagStatus['timestamp'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 28),
                    child: Text(
                      'tagTranslation.lastUpdate'.trParams(
                          {'time': tagStatus['timestamp']?.toString() ?? ''}),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: isRefreshing.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text('tagTranslation.refresh'.tr),
                  onPressed: isRefreshing.value
                      ? null
                      : () async {
                          isRefreshing.value = true;
                          try {
                            final result =
                                await backendApiClient.refreshTagTranslation();
                            if (result['success'] == true) {
                              Get.snackbar(
                                  'common.success'.tr,
                                  'tagTranslation.refreshSuccess'.trParams(
                                      {'count': '${result['count'] ?? 0}'}),
                                  snackPosition: SnackPosition.BOTTOM);
                            } else {
                              Get.snackbar(
                                  'common.error'.tr,
                                  result['message']?.toString() ??
                                      'common.failed'.tr,
                                  snackPosition: SnackPosition.BOTTOM);
                            }
                            await _load();
                          } catch (e) {
                            Get.snackbar(
                                'common.error'.tr,
                                'tagTranslation.refreshFailed'
                                    .trParams({'error': '$e'}),
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
