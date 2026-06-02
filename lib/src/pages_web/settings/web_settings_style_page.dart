import 'dart:convert';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_downloads_page.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_local_page.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:jhentai/src/pages_web/web_theme_controller.dart';
import 'package:web/web.dart' as web;

class WebSettingsStylePage extends StatefulWidget {
  const WebSettingsStylePage({super.key});

  @override
  State<WebSettingsStylePage> createState() => _WebSettingsStylePageState();
}

class _WebSettingsStylePageState extends State<WebSettingsStylePage>
    with WebScrollToTopState<WebSettingsStylePage> {
  static const detailThumbnailColumnsStorageKey =
      'jh_web_detail_thumbnail_columns';
  static const moveCoverToRightStorageKey = 'jh_web_move_cover_to_right';

  late String listMode;
  int? gridColumns;
  int? downloadGridColumns;
  int? localGridColumns;
  int? detailThumbnailColumns;
  late bool showGalleryListTags;
  late bool moveCoverToRight;
  late Map<String, String> pageListModes;

  @override
  void initState() {
    super.initState();
    final home = Get.isRegistered<WebHomeController>()
        ? Get.find<WebHomeController>()
        : null;
    final savedMode =
        web.window.localStorage.getItem(WebHomeController.listModeStorageKey);
    listMode = home?.listMode.value ??
        (savedMode != null && WebHomeController.listModes.contains(savedMode)
            ? savedMode
            : 'grid');
    gridColumns = home?.gridColumns.value ??
        _parseGridColumns(web.window.localStorage
            .getItem(WebHomeController.gridColumnsStorageKey));
    downloadGridColumns = _parseDownloadGridColumns(
      web.window.localStorage
          .getItem(WebDownloadsController.gridColumnsStorageKey),
    );
    localGridColumns = _parseLocalGridColumns(
      web.window.localStorage.getItem(WebLocalController.gridColumnsStorageKey),
    );
    detailThumbnailColumns = _parseDetailThumbnailColumns(
      web.window.localStorage.getItem(detailThumbnailColumnsStorageKey),
    );
    showGalleryListTags = home?.showGalleryListTags.value ??
        (web.window.localStorage
                .getItem(WebHomeController.showGalleryListTagsStorageKey) !=
            'false');
    moveCoverToRight =
        web.window.localStorage.getItem(moveCoverToRightStorageKey) == 'true';
    pageListModes = _loadPageListModes();
  }

  int? _parseGridColumns(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 1 && value <= 6 ? value : null;
  }

  int? _parseDetailThumbnailColumns(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 2 && value <= 8 ? value : null;
  }

  int? _parseDownloadGridColumns(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 2 && value <= 8 ? value : null;
  }

  int? _parseLocalGridColumns(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 2 && value <= 8 ? value : null;
  }

  void _setListMode(String mode) {
    if (!WebHomeController.listModes.contains(mode)) {
      return;
    }
    setState(() => listMode = mode);
    if (Get.isRegistered<WebHomeController>()) {
      Get.find<WebHomeController>().setListMode(mode);
    } else {
      web.window.localStorage
          .setItem(WebHomeController.listModeStorageKey, mode);
    }
  }

  void _setGridColumns(int? count) {
    setState(() => gridColumns = count);
    if (Get.isRegistered<WebHomeController>()) {
      Get.find<WebHomeController>().setGridColumns(count);
    } else if (count == null) {
      web.window.localStorage
          .removeItem(WebHomeController.gridColumnsStorageKey);
    } else {
      web.window.localStorage
          .setItem(WebHomeController.gridColumnsStorageKey, '$count');
    }
  }

  void _setDetailThumbnailColumns(int? count) {
    setState(() => detailThumbnailColumns = count);
    if (count == null) {
      web.window.localStorage.removeItem(detailThumbnailColumnsStorageKey);
    } else {
      web.window.localStorage
          .setItem(detailThumbnailColumnsStorageKey, '$count');
    }
  }

  void _setDownloadGridColumns(int? count) {
    setState(() => downloadGridColumns = count);
    WebDownloadsController.setGridColumns(count);
  }

  void _setLocalGridColumns(int? count) {
    setState(() => localGridColumns = count);
    WebLocalController.setGridColumns(count);
  }

  void _setShowGalleryListTags(bool value) {
    setState(() => showGalleryListTags = value);
    if (Get.isRegistered<WebHomeController>()) {
      Get.find<WebHomeController>().setShowGalleryListTags(value);
    } else {
      web.window.localStorage.setItem(
        WebHomeController.showGalleryListTagsStorageKey,
        value ? 'true' : 'false',
      );
    }
  }

  void _setMoveCoverToRight(bool value) {
    setState(() => moveCoverToRight = value);
    web.window.localStorage
        .setItem(moveCoverToRightStorageKey, value ? 'true' : 'false');
  }

  Future<void> _showCustomSeedColorDialog({
    required Color initialColor,
    required ValueChanged<Color> onSelected,
  }) async {
    Color selectedColor = initialColor;
    final newColor = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => SimpleDialog(
          title: Text('custom'.tr),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: ColorPicker(
                color: selectedColor,
                pickersEnabled: const <ColorPickerType, bool>{
                  ColorPickerType.both: true,
                  ColorPickerType.primary: false,
                  ColorPickerType.accent: false,
                  ColorPickerType.bw: false,
                  ColorPickerType.custom: false,
                  ColorPickerType.wheel: true,
                },
                pickerTypeLabels: <ColorPickerType, String>{
                  ColorPickerType.both: 'preset'.tr,
                  ColorPickerType.wheel: 'custom'.tr,
                },
                enableTonalPalette: true,
                showColorCode: true,
                colorCodeHasColor: true,
                colorCodeTextStyle: const TextStyle(fontSize: 18),
                enableOpacity: false,
                width: 36,
                height: 36,
                columnSpacing: 16,
                onColorChanged: (color) {
                  setDialogState(() => selectedColor = color);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('common.cancel'.tr),
                ),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      selectedColor = ThemeController.seedColors.first;
                    });
                  },
                  child: Text('common.reset'.tr),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selectedColor),
                  child: Text('common.ok'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (newColor != null) {
      onSelected(newColor);
    }
  }

  Widget _buildSeedColorPicker({
    required BuildContext context,
    required Color selectedColor,
    required ValueChanged<Color> onSelected,
  }) {
    final selectedArgb = selectedColor.toARGB32();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...ThemeController.seedColors.map((color) {
          final colorArgb = color.toARGB32();
          final isSelected = selectedArgb == colorArgb;
          return Tooltip(
            message:
                '#${colorArgb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            child: GestureDetector(
              onTap: () => onSelected(color),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => _showCustomSeedColorDialog(
            initialColor: selectedColor,
            onSelected: onSelected,
          ),
          icon: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: selectedColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          label: Text('custom'.tr),
        ),
      ],
    );
  }

  Widget _buildThemePreview({
    required Brightness brightness,
    required Color seedColor,
    required String label,
  }) {
    final theme = ThemeController.buildTheme(brightness, seedColor);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Container(
            constraints: const BoxConstraints(minWidth: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      child: Icon(
                        brightness == Brightness.light
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: 0.64,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () {},
                      child: Text('common.ok'.tr),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: Text('common.cancel'.tr),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, String> _loadPageListModes() {
    final home = Get.isRegistered<WebHomeController>()
        ? Get.find<WebHomeController>()
        : null;
    if (home != null) {
      return Map<String, String>.from(home.pageListModes);
    }
    final raw = web.window.localStorage
        .getItem(WebHomeController.pageListModeStorageKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (WebHomeController.defaultSections.contains(entry.key) &&
              entry.value is String &&
              WebHomeController.listModes.contains(entry.value))
            entry.key: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  void _setPageListMode(String section, String? mode) {
    if (!WebHomeController.defaultSections.contains(section)) {
      return;
    }
    if (mode != null && !WebHomeController.listModes.contains(mode)) {
      return;
    }
    setState(() {
      if (mode == null) {
        pageListModes.remove(section);
      } else {
        pageListModes[section] = mode;
      }
    });
    if (Get.isRegistered<WebHomeController>()) {
      Get.find<WebHomeController>().setPageListMode(section, mode);
    } else {
      web.window.localStorage.setItem(
        WebHomeController.pageListModeStorageKey,
        jsonEncode(pageListModes),
      );
    }
  }

  String _sectionLabel(String value) => switch (value) {
        'popular' => 'home.popular'.tr,
        'ranklist' => 'home.ranklist'.tr,
        'favorites' => 'home.favorites'.tr,
        'watched' => 'home.watched'.tr,
        _ => 'home.home'.tr,
      };

  String _listModeLabel(String value) => switch (value) {
        'list' => 'settings.listModeList'.tr,
        'listCompact' => 'settings.listModeCompact'.tr,
        _ => 'settings.listModeGrid'.tr,
      };

  @override
  Widget build(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuStyle'.tr)),
      body: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('settings.themeMode'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Obx(() => SegmentedButton<ThemeMode>(
                              segments: [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('settings.system'.tr),
                                  icon: const Icon(Icons.settings_brightness),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('settings.light'.tr),
                                  icon: const Icon(Icons.light_mode),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('settings.dark'.tr),
                                  icon: const Icon(Icons.dark_mode),
                                ),
                              ],
                              selected: {tc.themeMode.value},
                              onSelectionChanged: (selected) =>
                                  tc.setThemeMode(selected.first),
                            )),
                        const SizedBox(height: 16),
                        Text('settings.accentColor'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text('settings.light'.tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Obx(() => _buildSeedColorPicker(
                              context: context,
                              selectedColor: tc.lightSeedColor.value,
                              onSelected: tc.setLightSeedColor,
                            )),
                        const SizedBox(height: 16),
                        Text('settings.dark'.tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Obx(() => _buildSeedColorPicker(
                              context: context,
                              selectedColor: tc.darkSeedColor.value,
                              onSelected: tc.setDarkSeedColor,
                            )),
                        const SizedBox(height: 16),
                        Obx(
                          () => Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildThemePreview(
                                brightness: Brightness.light,
                                seedColor: tc.lightSeedColor.value,
                                label: 'settings.light'.tr,
                              ),
                              _buildThemePreview(
                                brightness: Brightness.dark,
                                seedColor: tc.darkSeedColor.value,
                                label: 'settings.dark'.tr,
                              ),
                            ],
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
                        Text('settings.galleryListStyle'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'grid',
                              label: Text('settings.listModeGrid'.tr),
                              icon: const Icon(Icons.grid_view),
                            ),
                            ButtonSegment(
                              value: 'list',
                              label: Text('settings.listModeList'.tr),
                              icon: const Icon(Icons.view_list),
                            ),
                            ButtonSegment(
                              value: 'listCompact',
                              label: Text('settings.listModeCompact'.tr),
                              icon: const Icon(Icons.view_headline),
                            ),
                          ],
                          selected: {listMode},
                          onSelectionChanged: (selected) =>
                              _setListMode(selected.first),
                        ),
                        const SizedBox(height: 16),
                        Text('settings.gridColumns'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: gridColumns,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder()),
                          items: [
                            DropdownMenuItem<int?>(
                                value: null,
                                child: Text('settings.gridColumnsAuto'.tr)),
                            for (final n in [1, 2, 3, 4, 5, 6])
                              DropdownMenuItem<int?>(
                                  value: n, child: Text('$n')),
                          ],
                          onChanged:
                              listMode == 'grid' ? _setGridColumns : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'settings.galleryListStyleHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.label_outline),
                          title: Text('settings.showGalleryListTags'.tr),
                          subtitle: Text('settings.showGalleryListTagsHint'.tr),
                          value: showGalleryListTags,
                          onChanged: _setShowGalleryListTags,
                        ),
                        const Divider(height: 32),
                        Text('pageListStyle'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        for (final section in WebHomeController.defaultSections)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DropdownButtonFormField<String?>(
                              initialValue: pageListModes[section],
                              decoration: InputDecoration(
                                labelText: _sectionLabel(section),
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('global'.tr),
                                ),
                                for (final mode in WebHomeController.listModes)
                                  DropdownMenuItem<String?>(
                                    value: mode,
                                    child: Text(_listModeLabel(mode)),
                                  ),
                              ],
                              onChanged: (mode) =>
                                  _setPageListMode(section, mode),
                            ),
                          ),
                        Text(
                          'settings.pageListStyleHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const Divider(height: 32),
                        Text('settings.downloadGridColumns'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: downloadGridColumns,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder()),
                          items: [
                            DropdownMenuItem<int?>(
                                value: null,
                                child: Text('settings.gridColumnsAuto'.tr)),
                            for (final n in [2, 3, 4, 5, 6, 7, 8])
                              DropdownMenuItem<int?>(
                                  value: n, child: Text('$n')),
                          ],
                          onChanged: _setDownloadGridColumns,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'settings.downloadGridColumnsHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const Divider(height: 32),
                        Text('settings.localGridColumns'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: localGridColumns,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder()),
                          items: [
                            DropdownMenuItem<int?>(
                                value: null,
                                child: Text('settings.gridColumnsAuto'.tr)),
                            for (final n in [2, 3, 4, 5, 6, 7, 8])
                              DropdownMenuItem<int?>(
                                  value: n, child: Text('$n')),
                          ],
                          onChanged: _setLocalGridColumns,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'settings.localGridColumnsHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const Divider(height: 32),
                        Text('settings.detailThumbnailColumns'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: detailThumbnailColumns,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder()),
                          items: [
                            DropdownMenuItem<int?>(
                                value: null,
                                child: Text('settings.gridColumnsAuto'.tr)),
                            for (final n in [2, 3, 4, 5, 6, 7, 8])
                              DropdownMenuItem<int?>(
                                  value: n, child: Text('$n')),
                          ],
                          onChanged: _setDetailThumbnailColumns,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'settings.detailThumbnailColumnsHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const Divider(height: 32),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.flip_to_back_outlined),
                          title: Text('moveCover2RightSide'.tr),
                          subtitle: Text('settings.moveCoverWebHint'.tr),
                          value: moveCoverToRight,
                          onChanged: _setMoveCoverToRight,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: buildScrollToTopFab(),
    );
  }
}
