import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WebSettingsDownloadMenuPage extends StatelessWidget {
  const WebSettingsDownloadMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuDownload'.tr)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('settings.downloadWebStub'.tr, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Get.toNamed('/web/downloads'),
              icon: const Icon(Icons.download_outlined),
              label: Text('settings.openDownloads'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
