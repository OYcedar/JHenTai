import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsNetworkPage extends GetView<WebSettingsController> {
  const WebSettingsNetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menuNetwork'.tr),
        actions: [
          Obx(
            () => IconButton(
              tooltip: 'settings.copyNetworkDiagnostics'.tr,
              onPressed: controller.isLoading.value
                  ? null
                  : () => _copyNetworkDiagnostics(context),
              icon: const Icon(Icons.copy_all_outlined),
            ),
          ),
        ],
      ),
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
              _networkTimeoutCard(context, info),
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
                  _proxyEnvLabel(item),
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

  Widget _networkTimeoutCard(BuildContext context, Map<String, dynamic> info) {
    final connectTimeout = _timeoutValue(info['connectTimeout']);
    final receiveTimeout = _timeoutValue(info['receiveTimeout']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text('settings.networkTimeouts'.tr),
        subtitle: Text(
          'settings.networkTimeoutsSummary'.trParams({
            'connect': '$connectTimeout',
            'receive': '$receiveTimeout',
          }),
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _showTimeoutDialog(
          context,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      ),
    );
  }

  int _timeoutValue(Object? raw) {
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return (value ?? 6000).clamp(1000, 600000).toInt();
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

  Future<void> _copyNetworkDiagnostics(BuildContext context) async {
    final info = controller.networkInfo;
    final proxyEnv =
        (info['proxyEnv'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final lines = <String>[
      'JHenTai Web network diagnostics',
      '${'settings.ehProxyRoute'.tr}: '
          '${_sourceLabel(info['ehProxySource']?.toString() ?? 'DIRECT')}',
      '${'settings.hathProxyRoute'.tr}: '
          '${_sourceLabel(info['hathProxySource']?.toString() ?? 'DIRECT')}',
      'JH_HATH_PROXY: '
          '${_boolLabel(info['hathProxyConfigured'] == true)}',
      '',
      '${'settings.proxyEnvironment'.tr}:',
      if (proxyEnv.isEmpty)
        '- ${'settings.proxyEnvironmentEmpty'.tr}'
      else
        for (final item in proxyEnv)
          '- ${item['name']?.toString() ?? '-'}: ${_proxyEnvLabel(item)}',
      '',
      '${'settings.networkRuntimeFlags'.tr}:',
      '- JH_HATH_PREFER_IPV4: ${_boolLabel(info['hathPreferIpv4'] == true)}',
      '- JH_IMAGE_PROXY_DEBUG: ${_boolLabel(info['imageProxyDebug'] == true)}',
      '- ${'connectTimeout'.tr}: ${_timeoutValue(info['connectTimeout'])}ms',
      '- ${'receiveTimeout'.tr}: ${_timeoutValue(info['receiveTimeout'])}ms',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) {
      return;
    }
    Get.snackbar(
      'common.success'.tr,
      'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _showTimeoutDialog(
    BuildContext context, {
    required int connectTimeout,
    required int receiveTimeout,
  }) async {
    final connectController =
        TextEditingController(text: connectTimeout.toString());
    final receiveController =
        TextEditingController(text: receiveTimeout.toString());
    try {
      final result = await Get.dialog<({int connect, int receive})>(
        AlertDialog(
          title: Text('settings.networkTimeouts'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: connectController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'connectTimeout'.tr,
                  suffixText: 'ms',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: receiveController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'receiveTimeout'.tr,
                  suffixText: 'ms',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'settings.networkTimeoutsHint'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed: () {
                Get.back(
                  result: (
                    connect: _timeoutValue(connectController.text),
                    receive: _timeoutValue(receiveController.text),
                  ),
                );
              },
              child: Text('common.save'.tr),
            ),
          ],
        ),
      );
      if (result == null) {
        return;
      }
      await backendApiClient.setNetworkTimeouts(
        connectTimeout: result.connect,
        receiveTimeout: result.receive,
      );
      await controller.refreshStatus();
      Get.snackbar(
        'common.success'.tr,
        'saveSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        '${'common.failed'.tr}: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      connectController.dispose();
      receiveController.dispose();
    }
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
    if (source == 'DIRECT') {
      return 'settings.directConnection'.tr;
    }
    return source;
  }

  String _proxyEnvLabel(Map item) {
    if (item['configured'] != true) {
      return 'settings.notConfigured'.tr;
    }
    final value = item['value']?.toString();
    final label =
        value != null && value.isNotEmpty ? value : 'settings.configured'.tr;
    if (item['hasCredentials'] == true) {
      return '$label (${'settings.proxyAuthConfigured'.tr})';
    }
    return label;
  }

  String _boolLabel(bool value) =>
      value ? 'settings.enabled'.tr : 'settings.disabled'.tr;
}
