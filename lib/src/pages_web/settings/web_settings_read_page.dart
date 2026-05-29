import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_reader_wheel.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_reader_setting_keys.dart';

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
                          'settings.defaultFavoriteHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Obx(() => SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('enableDefaultFavorite'.tr),
                              subtitle: Text(
                                  controller.enableDefaultFavorite.value
                                      ? 'enableDefaultFavoriteHint'.tr
                                      : 'disableDefaultFavoriteHint'.tr),
                              value: controller.enableDefaultFavorite.value,
                              onChanged: controller.setEnableDefaultFavorite,
                            )),
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
  final autoModeStyle = 'turnPage'.obs;
  final turnPageMode = 'adaptive'.obs;
  final displayFirstPageAlone = false.obs;
  final showThumbnails = true.obs;
  final showScrollBar = true.obs;
  final showStatusInfo = true.obs;
  final keepScreenAwake = true.obs;
  final enableBottomMenu = true.obs;
  final enablePageTurnAnimation = true.obs;
  final enableDoubleTapZoom = true.obs;
  final enableTapDragZoom = false.obs;
  final reverseTapPageTurn = false.obs;
  final disableTapPageTurn = false.obs;
  final gestureRegionWidthRatio = 60.obs;
  final imageRegionWidthRatio = 100.obs;
  final imageSpacing = 0.obs;
  final loaded = false.obs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await backendApiClient.getSetting(kWebReadDirectionKey);
      if (d != null) direction.value = int.tryParse(d) ?? 0;
      final p = await backendApiClient.getSetting(kWebPreloadPagesKey);
      if (p != null) preloadPages.value = int.tryParse(p) ?? 3;
      final local = await backendApiClient.getSetting(kWebPreloadPagesLocalKey);
      if (local != null) {
        preloadPagesLocal.value = int.tryParse(local) ?? 3;
      }
      final a = await backendApiClient.getSetting(kWebAutoIntervalKey);
      if (a != null) autoInterval.value = double.tryParse(a) ?? 5.0;
      final autoStyle = await backendApiClient.getSetting(kWebAutoModeStyleKey);
      if (autoStyle == 'scroll' || autoStyle == 'turnPage') {
        autoModeStyle.value = autoStyle!;
      }
      final turnMode = await backendApiClient.getSetting(kWebTurnPageModeKey);
      if (turnMode == 'image' ||
          turnMode == 'screen' ||
          turnMode == 'adaptive') {
        turnPageMode.value = turnMode!;
      }
      final first =
          await backendApiClient.getSetting(kWebDisplayFirstPageAloneKey);
      if (first != null) displayFirstPageAlone.value = first == 'true';
      final thumbs = await backendApiClient.getSetting(kWebShowThumbnailsKey);
      if (thumbs != null) showThumbnails.value = thumbs != 'false';
      final scrollbar = await backendApiClient.getSetting(kWebShowScrollBarKey);
      if (scrollbar != null) showScrollBar.value = scrollbar != 'false';
      final status = await backendApiClient.getSetting(kWebShowStatusInfoKey);
      if (status != null) showStatusInfo.value = status != 'false';
      final awake = await backendApiClient.getSetting(kWebKeepScreenAwakeKey);
      if (awake != null) keepScreenAwake.value = awake != 'false';
      final bottomMenu =
          await backendApiClient.getSetting(kWebEnableBottomMenuKey);
      if (bottomMenu != null) {
        enableBottomMenu.value = bottomMenu != 'false';
      }
      final animation =
          await backendApiClient.getSetting(kWebEnablePageTurnAnimationKey);
      if (animation != null) {
        enablePageTurnAnimation.value = animation != 'false';
      }
      final doubleTap =
          await backendApiClient.getSetting(kWebEnableDoubleTapZoomKey);
      if (doubleTap != null) {
        enableDoubleTapZoom.value = doubleTap != 'false';
      }
      final tapDrag =
          await backendApiClient.getSetting(kWebEnableTapDragZoomKey);
      if (tapDrag != null) {
        enableTapDragZoom.value = tapDrag == 'true';
      }
      final reverse =
          await backendApiClient.getSetting(kWebReverseTapPageTurnKey);
      if (reverse != null) reverseTapPageTurn.value = reverse == 'true';
      final disable =
          await backendApiClient.getSetting(kWebDisableTapPageTurnKey);
      if (disable != null) disableTapPageTurn.value = disable == 'true';
      final gestureRatio =
          await backendApiClient.getSetting(kWebGestureRegionWidthRatioKey);
      if (gestureRatio != null) {
        gestureRegionWidthRatio.value =
            (int.tryParse(gestureRatio) ?? 60).clamp(1, 99).toInt();
      }
      final imageRatio =
          await backendApiClient.getSetting(kWebImageRegionWidthRatioKey);
      if (imageRatio != null) {
        imageRegionWidthRatio.value =
            (int.tryParse(imageRatio) ?? 100).clamp(1, 100).toInt();
      }
      final spacing = await backendApiClient.getSetting(kWebImageSpacingKey);
      if (spacing != null) imageSpacing.value = int.tryParse(spacing) ?? 0;
    } catch (_) {}
    loaded.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final dirLabels = [
      'reader.ltr'.tr,
      'reader.rtl'.tr,
      'reader.vertical'.tr,
      'reader.fitWidth'.tr,
      'reader.doubleColumn'.tr,
    ];

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
                              .putSetting(kWebReadDirectionKey, i)
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
                          .putSetting(kWebPreloadPagesKey, v.round())
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('gestureRegionWidthRatio'.tr)),
                      Text('${gestureRegionWidthRatio.value}%'),
                    ],
                  )),
              Obx(() => Slider(
                    value: gestureRegionWidthRatio.value.toDouble(),
                    min: 1,
                    max: 99,
                    divisions: 98,
                    label: '${gestureRegionWidthRatio.value}%',
                    onChanged: (v) {
                      final rounded = v.round();
                      gestureRegionWidthRatio.value = rounded;
                      backendApiClient
                          .putSetting(kWebGestureRegionWidthRatioKey, rounded)
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => Row(
                    children: [
                      Expanded(child: Text('imageRegionWidthRatio'.tr)),
                      Text('${imageRegionWidthRatio.value}%'),
                    ],
                  )),
              Obx(() => Slider(
                    value: imageRegionWidthRatio.value.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '${imageRegionWidthRatio.value}%',
                    onChanged: (v) {
                      final rounded = v.round();
                      imageRegionWidthRatio.value = rounded;
                      backendApiClient
                          .putSetting(kWebImageRegionWidthRatioKey, rounded)
                          .catchError((_) {});
                    },
                  )),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'settings.imageRegionWidthRatioHint'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
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
                          .putSetting(kWebPreloadPagesLocalKey, v.round())
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
                          .putSetting(kWebAutoIntervalKey, v)
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => DropdownButtonFormField<String>(
                    initialValue: autoModeStyle.value,
                    decoration: InputDecoration(
                      labelText: 'autoModeStyle'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'scroll',
                        child: Text('scroll'.tr),
                      ),
                      DropdownMenuItem(
                        value: 'turnPage',
                        child: Text('turnPage'.tr),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) {
                        return;
                      }
                      autoModeStyle.value = v;
                      backendApiClient
                          .putSetting(kWebAutoModeStyleKey, v)
                          .catchError((_) {});
                    },
                  )),
              const SizedBox(height: 8),
              Obx(() => DropdownButtonFormField<String>(
                    initialValue: turnPageMode.value,
                    decoration: InputDecoration(
                      labelText: 'turnPageMode'.tr,
                      helperText: 'turnPageModeHint'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'image',
                        child: Text('image'.tr),
                      ),
                      DropdownMenuItem(
                        value: 'screen',
                        child: Text('screen'.tr),
                      ),
                      DropdownMenuItem(
                        value: 'adaptive',
                        child: Text('adaptive'.tr),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) {
                        return;
                      }
                      turnPageMode.value = v;
                      backendApiClient
                          .putSetting(kWebTurnPageModeKey, v)
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
                          .putSetting(kWebDisplayFirstPageAloneKey, v)
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
                          .putSetting(kWebShowThumbnailsKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('showScrollBar'.tr),
                    value: showScrollBar.value,
                    onChanged: (v) {
                      showScrollBar.value = v;
                      backendApiClient
                          .putSetting(kWebShowScrollBarKey, v)
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
                          .putSetting(kWebShowStatusInfoKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('keepScreenAwakeWhenReading'.tr),
                    value: keepScreenAwake.value,
                    onChanged: (v) {
                      keepScreenAwake.value = v;
                      backendApiClient
                          .putSetting(kWebKeepScreenAwakeKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('enableBottomMenu'.tr),
                    value: enableBottomMenu.value,
                    onChanged: (v) {
                      enableBottomMenu.value = v;
                      backendApiClient
                          .putSetting(kWebEnableBottomMenuKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('enablePageTurnAnime'.tr),
                    value: enablePageTurnAnimation.value,
                    onChanged: (v) {
                      enablePageTurnAnimation.value = v;
                      backendApiClient
                          .putSetting(kWebEnablePageTurnAnimationKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('enableDoubleTapToScaleUp'.tr),
                    value: enableDoubleTapZoom.value,
                    onChanged: (v) {
                      enableDoubleTapZoom.value = v;
                      backendApiClient
                          .putSetting(kWebEnableDoubleTapZoomKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('enableTapDragToScaleUp'.tr),
                    value: enableTapDragZoom.value,
                    onChanged: (v) {
                      enableTapDragZoom.value = v;
                      backendApiClient
                          .putSetting(kWebEnableTapDragZoomKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('reverseTurnPageDirection'.tr),
                    value: reverseTapPageTurn.value,
                    onChanged: (v) {
                      reverseTapPageTurn.value = v;
                      backendApiClient
                          .putSetting(kWebReverseTapPageTurnKey, v)
                          .catchError((_) {});
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              Obx(() => SwitchListTile(
                    title: Text('disablePageTurningOnTap'.tr),
                    value: disableTapPageTurn.value,
                    onChanged: (v) {
                      disableTapPageTurn.value = v;
                      backendApiClient
                          .putSetting(kWebDisableTapPageTurnKey, v)
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
                          .putSetting(kWebImageSpacingKey, rounded)
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
