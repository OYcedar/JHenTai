import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

/// Single page for Web-only / Docker notes: replaces separate stub screens linked from the hub.
class WebSettingsWebDockerPage extends GetView<WebSettingsController> {
  const WebSettingsWebDockerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuWebDocker'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = controller.serverInfo;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('settings.menuWebDockerSubtitle'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 20),
            Text('settings.menuDownload'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('settings.downloadWebStub'.tr, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Get.toNamed('/web/downloads'),
              icon: const Icon(Icons.download_outlined),
              label: Text('settings.openDownloads'.tr),
            ),
            const SizedBox(height: 24),
            Text('settings.serverInfo'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('settings.advancedWebStub'.tr, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
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
            const SizedBox(height: 24),
            Text('settings.menuNetwork'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wifi_tethering, color: Theme.of(context).colorScheme.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('settings.networkNote'.tr, style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('settings.networkWebBody'.tr, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'settings.networkWebStub'.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Text('settings.menuPerformance'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('settings.performanceWebStub'.tr, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            Text('settings.menuSecurity'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('settings.securityWebStub'.tr, style: Theme.of(context).textTheme.bodyMedium),
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
