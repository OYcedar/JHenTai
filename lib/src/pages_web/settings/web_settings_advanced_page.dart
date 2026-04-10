import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsAdvancedPage extends GetView<WebSettingsController> {
  const WebSettingsAdvancedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuAdvanced'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = controller.serverInfo;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'settings.advancedWebStub'.tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text('settings.serverInfo'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('settings.dataDir'.tr, info['dataDir']?.toString() ?? '-'),
                    _infoRow('settings.downloadDir'.tr, info['downloadDir']?.toString() ?? '-'),
                    _infoRow('settings.localGalleryDir'.tr, info['localGalleryDir']?.toString() ?? '-'),
                    if (info['extraScanPaths'] is List && (info['extraScanPaths'] as List).isNotEmpty)
                      _infoRow('settings.extraScanPaths'.tr, (info['extraScanPaths'] as List).join(', ')),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}
