import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

/// Settings hub: entries that are not duplicated from the home drawer (downloads, history, local).
class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key});

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<WebSettingsPage>
    with WebScrollToTopState<WebSettingsPage> {
  final WebSettingsController controller = Get.find<WebSettingsController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text('settings.account'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/account'),
            ),
            Obx(() {
              if (!controller.isLoggedIn.value) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading: const Icon(Icons.mood),
                title: Text('settings.menuEH'.tr),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.toNamed('/web/settings/eh'),
              );
            }),
            ListTile(
              leading: const Icon(Icons.style),
              title: Text('settings.menuStyle'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/style'),
            ),
            ListTile(
              leading: const Icon(Icons.local_library),
              title: Text('settings.menuRead'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/read'),
            ),
            ListTile(
              leading: const Icon(Icons.stars),
              title: Text('settings.menuPreference'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/preference'),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: Text('settings.menuNetwork'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/network'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text('settings.menuDownload'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/download'),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text('settings.menuPerformance'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/performance'),
            ),
            ListTile(
              leading: const Icon(Icons.mouse),
              title: Text('settings.menuMouseWheel'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/mouse-wheel'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text('settings.menuAdvanced'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/advanced'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text('settings.cloudSync'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/cloud-sync'),
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: Text('settings.menuSecurity'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/security'),
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: Text('settings.menuWebDocker'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/web-docker'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('settings.about'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/about'),
            ),
          ],
        );
      }),
      floatingActionButton: buildScrollToTopFab(),
    );
  }
}
