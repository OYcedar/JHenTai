import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_downloads_page.dart';
import 'package:jhentai/src/pages_web/web_reader_setting_keys.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

enum _PerformancePreset {
  nas,
  balanced,
  fast,
}

class _PerformancePresetValues {
  const _PerformancePresetValues({
    required this.onlinePreloadPages,
    required this.localPreloadPages,
    required this.onlinePreloadDistance,
    required this.localPreloadDistance,
    required this.maxGalleryNum4Animation,
  });

  final int onlinePreloadPages;
  final int localPreloadPages;
  final int onlinePreloadDistance;
  final int localPreloadDistance;
  final int maxGalleryNum4Animation;
}

class WebSettingsPerformancePage extends StatefulWidget {
  const WebSettingsPerformancePage({super.key});

  @override
  State<WebSettingsPerformancePage> createState() =>
      _WebSettingsPerformancePageState();
}

class _WebSettingsPerformancePageState extends State<WebSettingsPerformancePage>
    with WebScrollToTopState<WebSettingsPerformancePage> {
  static const _presetValues = {
    _PerformancePreset.nas: _PerformancePresetValues(
      onlinePreloadPages: 1,
      localPreloadPages: 3,
      onlinePreloadDistance: 0,
      localPreloadDistance: 2,
      maxGalleryNum4Animation: 12,
    ),
    _PerformancePreset.balanced: _PerformancePresetValues(
      onlinePreloadPages: 2,
      localPreloadPages: 4,
      onlinePreloadDistance: 1,
      localPreloadDistance: 4,
      maxGalleryNum4Animation: 30,
    ),
    _PerformancePreset.fast: _PerformancePresetValues(
      onlinePreloadPages: 4,
      localPreloadPages: 6,
      onlinePreloadDistance: 3,
      localPreloadDistance: 6,
      maxGalleryNum4Animation: 60,
    ),
  };

  late final TextEditingController _maxGalleryNumController;
  final applyingPreset = Rxn<_PerformancePreset>();

  @override
  void initState() {
    super.initState();
    _maxGalleryNumController = TextEditingController(
      text: '${WebDownloadsController.maxGalleryNum4Animation}',
    );
  }

  @override
  void dispose() {
    _maxGalleryNumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuPerformance'.tr)),
      body: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.speed,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'settings.webPerformance'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'settings.performanceWebIntro'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.performancePresetTitle'.tr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'settings.performancePresetHint'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Obx(
                    () => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: applyingPreset.value == null
                                  ? () => _applyPreset(_PerformancePreset.nas)
                                  : null,
                              icon: _presetIcon(
                                _PerformancePreset.nas,
                                Icons.dns_outlined,
                              ),
                              label: Text('settings.performancePresetNas'.tr),
                            ),
                            OutlinedButton.icon(
                              onPressed: applyingPreset.value == null
                                  ? () =>
                                      _applyPreset(_PerformancePreset.balanced)
                                  : null,
                              icon: _presetIcon(
                                _PerformancePreset.balanced,
                                Icons.tune,
                              ),
                              label: Text(
                                'settings.performancePresetBalanced'.tr,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: applyingPreset.value == null
                                  ? () => _applyPreset(_PerformancePreset.fast)
                                  : null,
                              icon: _presetIcon(
                                _PerformancePreset.fast,
                                Icons.bolt_outlined,
                              ),
                              label: Text('settings.performancePresetFast'.tr),
                            ),
                          ],
                        ),
                        if (applyingPreset.value != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'settings.performancePresetApplying'.trParams({
                              'preset': _presetLabel(applyingPreset.value!),
                            }),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _maxGalleryNumController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'settings.webMaxGalleryNum4Animation'.tr,
              helperText: 'settings.webMaxGalleryNum4AnimationHint'.tr,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'save'.tr,
                icon: const Icon(Icons.check),
                onPressed: _save,
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: Text('settings.resetPerformanceDefaults'.tr),
          ),
        ],
      ),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  void _save() {
    final value = int.tryParse(_maxGalleryNumController.text.trim());
    if (value == null) {
      return;
    }
    WebDownloadsController.setMaxGalleryNum4Animation(value);
    _maxGalleryNumController.text = '$value';
    Get.snackbar(
      'common.success'.tr,
      'settings.performanceSaved'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _reset() {
    const value = WebDownloadsController.defaultMaxGalleryNum4Animation;
    WebDownloadsController.setMaxGalleryNum4Animation(value);
    _maxGalleryNumController.text = '$value';
    Get.snackbar(
      'common.success'.tr,
      'settings.performanceSaved'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _applyPreset(_PerformancePreset preset) async {
    if (applyingPreset.value != null) {
      return;
    }
    final values = _presetValues[preset]!;
    applyingPreset.value = preset;
    try {
      await Future.wait([
        backendApiClient.putSetting(
          kWebPreloadPagesKey,
          values.onlinePreloadPages,
        ),
        backendApiClient.putSetting(
          kWebPreloadPagesLocalKey,
          values.localPreloadPages,
        ),
        backendApiClient.putSetting(
          kWebPreloadDistanceKey,
          values.onlinePreloadDistance,
        ),
        backendApiClient.putSetting(
          kWebPreloadDistanceLocalKey,
          values.localPreloadDistance,
        ),
      ]);
      _cacheReaderSetting(kWebPreloadPagesKey, values.onlinePreloadPages);
      _cacheReaderSetting(kWebPreloadPagesLocalKey, values.localPreloadPages);
      _cacheReaderSetting(
        kWebPreloadDistanceKey,
        values.onlinePreloadDistance,
      );
      _cacheReaderSetting(
        kWebPreloadDistanceLocalKey,
        values.localPreloadDistance,
      );
      WebDownloadsController.setMaxGalleryNum4Animation(
        values.maxGalleryNum4Animation,
      );
      _maxGalleryNumController.text = '${values.maxGalleryNum4Animation}';
      Get.snackbar(
        'common.success'.tr,
        'settings.performanceSaved'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.performancePresetFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      applyingPreset.value = null;
    }
  }

  Widget _presetIcon(_PerformancePreset preset, IconData icon) {
    if (applyingPreset.value != preset) {
      return Icon(icon);
    }
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  String _presetLabel(_PerformancePreset preset) {
    return switch (preset) {
      _PerformancePreset.nas => 'settings.performancePresetNas'.tr,
      _PerformancePreset.balanced => 'settings.performancePresetBalanced'.tr,
      _PerformancePreset.fast => 'settings.performancePresetFast'.tr,
    };
  }

  void _cacheReaderSetting(String key, int value) {
    web.window.localStorage.setItem(key, '$value');
  }
}
