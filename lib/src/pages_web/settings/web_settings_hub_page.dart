import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

/// Main settings hub: mirrors native [SettingPage] entries plus data & tools shortcuts.
class WebSettingsPage extends GetView<WebSettingsController> {
  const WebSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text(
              'settings.sectionData'.tr,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: Text('settings.openDownloads'.tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed('/web/downloads'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text('settings.openHistory'.tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed('/web/history'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text('settings.openLocal'.tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed('/web/local'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: Text('settings.openQuickSearch'.tr),
                    subtitle: Text('quickSearch.title'.tr, style: Theme.of(context).textTheme.bodySmall),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed('/web/quick-search'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'settings.hubMenu'.tr,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text('settings.account'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/account'),
            ),
            Obx(() {
              if (!controller.isLoggedIn.value) return const SizedBox.shrink();
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
              leading: const Icon(Icons.wifi),
              title: Text('settings.menuNetwork'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/network'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text('settings.menuDownload'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/download'),
            ),
            ListTile(
              leading: const Icon(Icons.electric_bolt),
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
              leading: const Icon(Icons.settings_suggest),
              title: Text('settings.menuAdvanced'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/advanced'),
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: Text('settings.menuSecurity'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/security'),
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text('settings.about'.tr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed('/web/settings/about'),
            ),
          ],
        );
      }),
    );
  }
}
