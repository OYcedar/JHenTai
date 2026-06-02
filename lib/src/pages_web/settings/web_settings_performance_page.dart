import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_downloads_page.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsPerformancePage extends StatefulWidget {
  const WebSettingsPerformancePage({super.key});

  @override
  State<WebSettingsPerformancePage> createState() =>
      _WebSettingsPerformancePageState();
}

class _WebSettingsPerformancePageState extends State<WebSettingsPerformancePage>
    with WebScrollToTopState<WebSettingsPerformancePage> {
  late final TextEditingController _maxGalleryNumController;

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
}
