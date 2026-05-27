import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsNetworkPage extends GetView<WebSettingsController> {
  const WebSettingsNetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuNetwork'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = controller.networkInfo;
        final proxyEnv =
            (info['proxyEnv'] as List?)?.whereType<Map>().toList() ??
                const <Map>[];
        return RefreshIndicator(
          onRefresh: controller.refreshStatus,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _networkNote(context),
              const SizedBox(height: 16),
              _routingCard(context, info),
              const SizedBox(height: 16),
              _proxyEnvCard(context, proxyEnv),
              const SizedBox(height: 16),
              _runtimeFlagsCard(context, info),
            ],
          ),
        );
      }),
    );
  }

  Widget _networkNote(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'settings.networkNote'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'settings.networkWebBody'.tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _routingCard(BuildContext context, Map<String, dynamic> info) {
    final ehSource = info['ehProxySource']?.toString() ?? 'DIRECT';
    final hathSource = info['hathProxySource']?.toString() ?? 'DIRECT';
    final hathDedicated = info['hathProxyConfigured'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.proxyRouting'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _infoRow(
              context,
              'settings.ehProxyRoute'.tr,
              _sourceLabel(ehSource),
              active: ehSource != 'DIRECT',
            ),
            _infoRow(
              context,
              'settings.hathProxyRoute'.tr,
              _sourceLabel(hathSource),
              active: hathSource != 'DIRECT',
            ),
            const SizedBox(height: 10),
            Text(
              (hathDedicated
                      ? 'settings.hathProxyDedicatedHint'
                      : 'settings.hathProxyFallbackHint')
                  .tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proxyEnvCard(BuildContext context, List<Map> proxyEnv) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.proxyEnvironment'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (proxyEnv.isEmpty)
              Text(
                'settings.proxyEnvironmentEmpty'.tr,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              for (final item in proxyEnv)
                _infoRow(
                  context,
                  item['name']?.toString() ?? '-',
                  item['configured'] == true
                      ? (item['value']?.toString().isNotEmpty == true
                          ? item['value'].toString()
                          : 'settings.configured'.tr)
                      : 'settings.notConfigured'.tr,
                  active: item['configured'] == true,
                ),
            const SizedBox(height: 10),
            Text(
              'settings.proxyEnvironmentHint'.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runtimeFlagsCard(BuildContext context, Map<String, dynamic> info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.networkRuntimeFlags'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _infoRow(
              context,
              'JH_HATH_PREFER_IPV4',
              _boolLabel(info['hathPreferIpv4'] == true),
              active: info['hathPreferIpv4'] == true,
            ),
            _infoRow(
              context,
              'JH_IMAGE_PROXY_DEBUG',
              _boolLabel(info['imageProxyDebug'] == true),
              active: info['imageProxyDebug'] == true,
            ),
            const SizedBox(height: 10),
            Text(
              'settings.networkRestartHint'.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    required bool active,
  }) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Icon(
            active ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    if (source == 'DIRECT') return 'settings.directConnection'.tr;
    return source;
  }

  String _boolLabel(bool value) =>
      value ? 'settings.enabled'.tr : 'settings.disabled'.tr;
}
