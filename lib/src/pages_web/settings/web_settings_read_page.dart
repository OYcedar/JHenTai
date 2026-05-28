import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_reader_wheel.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsReadPage extends GetView<WebSettingsController> {
  const WebSettingsReadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuRead'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: WebReaderWheelSettingSection(),
                  ),
                ),
                const SizedBox(height: 16),
                const _WebReaderCoreSettings(),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('home.favorites'.tr,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'detail.favQuickAddTooltip'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Obx(() => DropdownButtonFormField<int?>(
                              decoration: InputDecoration(
                                labelText: 'settings.defaultFavoriteSlot'.tr,
                                border: const OutlineInputBorder(),
                              ),
                              value: controller.defaultFavoriteSlot.value,
                              items: [
                                DropdownMenuItem<int?>(
                                  value: null,
                                  child:
                                      Text('settings.defaultFavoriteNone'.tr),
                                ),
                                ...List.generate(
                                  10,
                                  (i) => DropdownMenuItem<int?>(
                                    value: i,
                                    child: Text(
                                        'detail.favSlot'.trParams({'n': '$i'})),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  controller.setDefaultFavoriteSlot(v),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebReaderCoreSettings extends StatefulWidget {
  const _WebReaderCoreSettings();

  @override
  State<_WebReaderCoreSettings> createState() => _WebReaderCoreSettingsState();
}

class _WebReaderCoreSettingsState extends State<_WebReaderCoreSettings> {
  final direction = 0.obs;
  final preloadPages = 3.obs;
  final preloadPagesLocal = 3.obs;
  final autoInterval = 5.0.obs;
  final displayFirstPageAlone = false.obs;
  final showThumbnails = true.obs;
  final showStatusInfo = true.obs;
  final imageSpacing = 0.obs;
  final loaded = false.obs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await backendApiClient.getSetting('web_read_direction');
      if (d != null) direction.value = int.tryParse(d) ?? 0;
      final p = await backendApiClient.getSetting('web_preload_pages');
      if (p != null) preloadPages.value = int.tryParse(p) ?? 3;
      final local =
          await backendApiClient.getSetting('web_preload_pages_local');
      if (local != null) {
        preloadPagesLocal.value = int.tryParse(local) ?? 3;
      }
      final a = await backendApiClient.getSetting('web_auto_interval');
      if (a != null) autoInterval.value = double.tryParse(a) ?? 5.0;
      final first =
          await backendApiClient.getSetting('web_display_first_page_alone');
      if (first != null) displayFirstPageAlone.value = first == 'true';
      final thumbs = await backendApiClient.getSetting('web_show_thumbnails');
      if (thumbs != null) showThumbnails.value = thumbs != 'false';
      final status = await backendApiClient.getSetting('web_show_status_info');
      if (status != null) showStatusInfo.value = status != 'false';
      final spacing = await backendApiClient.getSetting('web_image_spacing');
      if (spacing != null) imageSpacing.value = int.tryParse(spacing) ?? 0;
    } catch (_) {}
    loaded.value = true;
  }

  @override
  Widget build(BuildContext context) {
    const dirLabels = ['LTR', 'RTL', 'Vertical', 'Fit Width', 'Double'];

    return Obx(() {
      if (!loaded.value) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('settings.defaultDirection'.tr,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Obx(() => Wrap(
                    spacing: 6,
                    children: List.generate(
                      dirLabels.length,
                      (i) => ChoiceChip(
                        label: Text(dirLabels[i],
                            style: const TextStyle(fontSize: 12)),
                        selected: direction.value == i,
                        onSelected: (_) {
                          direction.value = i;
                          backendApiClient
                              .putSetting('web_read_direction', i)
                              .catchError((_) {});
                        },
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('settings.preloadPages'.tr)),
                      Text('${preloadPages.value}'),
                    ],
                  )),
              Obx(() => Slider(
                    value: preloadPages.value.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${preloadPages.value}',
                    onChanged: (v) {
                      preloadPages.value = v.round();
                      backendApiClient
                          .putSetting('web_preload_pages', v.round())
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('settings.preloadPagesLocal'.tr)),
                      Text('${preloadPagesLocal.value}'),
                    ],
                  )),
              Obx(() => Slider(
                    value: preloadPagesLocal.value.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${preloadPagesLocal.value}',
                    onChanged: (v) {
                      preloadPagesLocal.value = v.round();
                      backendApiClient
                          .putSetting('web_preload_pages_local', v.round())
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('settings.autoInterval'.tr)),
                      Text('${autoInterval.value.toStringAsFixed(1)}s'),
                    ],
                  )),
              Obx(() => Slider(
                    value: autoInterval.value,
                    min: 2,
                    max: 15,
                    divisions: 26,
                    label: '${autoInterval.value.toStringAsFixed(1)}s',
                    onChanged: (v) {
                      autoInterval.value = v;
                      backendApiClient
                          .putSetting('web_auto_interval', v)
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => SwitchListTile(
                    title: Text('displayFirstPageAlone'.tr),
                    value: displayFirstPageAlone.value,
                    onChanged: (v) {
                      displayFirstPageAlone.value = v;
                      backendApiClient
                          .putSetting('web_display_first_page_alone', v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('showThumbnails'.tr),
                    value: showThumbnails.value,
                    onChanged: (v) {
                      showThumbnails.value = v;
                      backendApiClient
                          .putSetting('web_show_thumbnails', v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('showStatusInfo'.tr),
                    value: showStatusInfo.value,
                    onChanged: (v) {
                      showStatusInfo.value = v;
                      backendApiClient
                          .putSetting('web_show_status_info', v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              const SizedBox(height: 8),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('spaceBetweenImages'.tr)),
                      Text('${imageSpacing.value}px'),
                    ],
                  )),
              Obx(() => Slider(
                    value: imageSpacing.value.toDouble(),
                    min: 0,
                    max: 32,
                    divisions: 16,
                    label: '${imageSpacing.value}px',
                    onChanged: (v) {
                      final rounded = v.round();
                      imageSpacing.value = rounded;
                      backendApiClient
                          .putSetting('web_image_spacing', rounded)
                          .catchError((_) {});
                    },
                  )),
            ],
          ),
        ),
      );
    });
  }
}
