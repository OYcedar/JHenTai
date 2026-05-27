import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_theme_controller.dart';
import 'package:web/web.dart' as web;

class WebSettingsStylePage extends StatefulWidget {
  const WebSettingsStylePage({super.key});

  @override
  State<WebSettingsStylePage> createState() => _WebSettingsStylePageState();
}

class _WebSettingsStylePageState extends State<WebSettingsStylePage> {
  late String listMode;
  int? gridColumns;

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
  }

  int? _parseGridColumns(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 1 && value <= 6 ? value : null;
  }

  void _setListMode(String mode) {
    if (!WebHomeController.listModes.contains(mode)) return;
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

  @override
  Widget build(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuStyle'.tr)),
      body: SingleChildScrollView(
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
                        Obx(() => Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ThemeController.seedColors.map((color) {
                                final isSelected =
                                    tc.seedColor.value.toARGB32() ==
                                        color.toARGB32();
                                return GestureDetector(
                                  onTap: () => tc.setSeedColor(color),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                              width: 3)
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 18)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            )),
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
                          value: gridColumns,
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
