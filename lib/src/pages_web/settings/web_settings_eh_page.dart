import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:web/web.dart' as web;

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
          return Center(
              child: Text('settings.ehRequiresLogin'.tr,
                  textAlign: TextAlign.center));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  _siteCard(context),
                  const SizedBox(height: 12),
                  _linkCard(context),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _siteCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.site'.tr,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'EH', label: Text('E-Hentai')),
                    ButtonSegment(value: 'EX', label: Text('ExHentai')),
                  ],
                  selected: {controller.site.value},
                  onSelectionChanged: (selected) =>
                      controller.switchSite(selected.first),
                )),
            const SizedBox(height: 8),
            Obx(() {
              final status = controller.cookieStatus.value;
              if (status.isEmpty) return const SizedBox.shrink();
              final good = status.contains('igneous') ||
                  status == 'settings.cookieStatusFull'.tr;
              return Row(
                children: [
                  Icon(
                    good ? Icons.check_circle : Icons.warning_amber,
                    size: 16,
                    color: good ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _linkCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text('settings.ehMyTags'.tr),
            subtitle: Text('settings.ehMyTagsHint'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed('/web/tag-sets'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text('settings.ehSiteSetting'.tr),
            subtitle: Text('settings.ehSiteSettingHint'.tr),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => web.window.open(
              controller.site.value == 'EX'
                  ? 'https://exhentai.org/uconfig.php'
                  : 'https://e-hentai.org/uconfig.php',
              '_blank',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text('settings.ehProfileAndQuota'.tr),
            subtitle: Text('settings.ehProfileAndQuotaHint'.tr),
          ),
        ],
      ),
    );
  }
}
