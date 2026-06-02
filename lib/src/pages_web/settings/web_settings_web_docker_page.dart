import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

/// Web-only / Docker operations hub.
class WebSettingsWebDockerPage extends StatefulWidget {
  const WebSettingsWebDockerPage({super.key});

  @override
  State<WebSettingsWebDockerPage> createState() =>
      _WebSettingsWebDockerPageState();
}

class _WebSettingsWebDockerPageState extends State<WebSettingsWebDockerPage>
    with WebScrollToTopState<WebSettingsWebDockerPage> {
  final WebSettingsController controller = Get.find<WebSettingsController>();

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
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'settings.menuWebDockerSubtitle'.tr,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _routeCard(
              context,
              icon: Icons.download_outlined,
              title: 'settings.menuDownload'.tr,
              body: 'settings.downloadWebSummary'.tr,
              route: '/web/settings/download',
            ),
            const SizedBox(height: 12),
            _serverInfoCard(context, info),
            const SizedBox(height: 12),
            _routeCard(
              context,
              icon: Icons.wifi_tethering,
              title: 'settings.menuNetwork'.tr,
              body: 'settings.networkWebSummary'.tr,
              route: '/web/settings/network',
            ),
            const SizedBox(height: 12),
            _routeCard(
              context,
              icon: Icons.speed,
              title: 'settings.menuPerformance'.tr,
              body: 'settings.performanceWebSummary'.tr,
              route: '/web/settings/performance',
            ),
            const SizedBox(height: 12),
            _routeCard(
              context,
              icon: Icons.security,
              title: 'settings.menuSecurity'.tr,
              body: 'settings.securityWebSummary'.tr,
              route: '/web/settings/security',
            ),
            const SizedBox(height: 12),
            _routeCard(
              context,
              icon: Icons.tune,
              title: 'settings.menuAdvanced'.tr,
              body: 'settings.advancedWebSummary'.tr,
              route: '/web/settings/advanced',
            ),
          ],
        );
      }),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _serverInfoCard(BuildContext context, Map<String, dynamic> info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'settings.serverInfo'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(
              'settings.dataDir'.tr,
              info['dataDir']?.toString() ?? '-',
            ),
            _infoRow(
              'settings.downloadDir'.tr,
              info['downloadDir']?.toString() ?? '-',
            ),
            _infoRow(
              'settings.localGalleryDir'.tr,
              info['localGalleryDir']?.toString() ?? '-',
            ),
            if (info['extraScanPaths'] is List &&
                (info['extraScanPaths'] as List).isNotEmpty)
              _infoRow(
                'settings.extraScanPaths'.tr,
                (info['extraScanPaths'] as List).join(', '),
              ),
          ],
        ),
      ),
    );
  }

  Widget _routeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required String route,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(body),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Get.toNamed(route),
      ),
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
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
