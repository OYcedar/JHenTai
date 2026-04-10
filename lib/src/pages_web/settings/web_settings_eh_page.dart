import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsEhPage extends GetView<WebSettingsController> {
  const WebSettingsEhPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuEH'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.isLoggedIn.value) {
          return Center(child: Text('settings.ehRequiresLogin'.tr, textAlign: TextAlign.center));
        }
        return SingleChildScrollView(
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
                      Text('settings.site'.tr, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Obx(() => SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'EH', label: Text('E-Hentai')),
                              ButtonSegment(value: 'EX', label: Text('ExHentai')),
                            ],
                            selected: {controller.site.value},
                            onSelectionChanged: (selected) => controller.switchSite(selected.first),
                          )),
                      const SizedBox(height: 8),
                      Obx(() {
                        final status = controller.cookieStatus.value;
                        if (status.isEmpty) return const SizedBox.shrink();
                        return Row(
                          children: [
                            Icon(
                              status.contains('igneous') || status == 'settings.cookieStatusFull'.tr
                                  ? Icons.check_circle
                                  : Icons.warning_amber,
                              size: 16,
                              color: status.contains('igneous') || status == 'settings.cookieStatusFull'.tr
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
                          ],
                        );
                      }),
                      const SizedBox(height: 16),
                      Text(
                        'settings.ehWebMoreSoon'.tr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
