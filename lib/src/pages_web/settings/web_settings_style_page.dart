import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_theme_controller.dart';

class WebSettingsStylePage extends StatelessWidget {
  const WebSettingsStylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuStyle'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('settings.themeMode'.tr, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Obx(() => SegmentedButton<ThemeMode>(
                          segments: [
                            ButtonSegment(
                                value: ThemeMode.system,
                                label: Text('settings.system'.tr),
                                icon: const Icon(Icons.settings_brightness)),
                            ButtonSegment(
                                value: ThemeMode.light,
                                label: Text('settings.light'.tr),
                                icon: const Icon(Icons.light_mode)),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text('settings.dark'.tr),
                                icon: const Icon(Icons.dark_mode)),
                          ],
                          selected: {tc.themeMode.value},
                          onSelectionChanged: (selected) => tc.setThemeMode(selected.first),
                        )),
                    const SizedBox(height: 16),
                    Text('settings.accentColor'.tr, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Obx(() => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ThemeController.seedColors.map((color) {
                            final isSelected = tc.seedColor.value.toARGB32() == color.toARGB32();
                            return GestureDetector(
                              onTap: () => tc.setSeedColor(color),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                                    : null,
                              ),
                            );
                          }).toList(),
                        )),
                    const SizedBox(height: 16),
                    Text(
                      'settings.styleWebMoreSoon'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
