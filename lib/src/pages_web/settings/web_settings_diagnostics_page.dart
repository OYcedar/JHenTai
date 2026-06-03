import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsDiagnosticsPage extends StatefulWidget {
  const WebSettingsDiagnosticsPage({super.key});

  @override
  State<WebSettingsDiagnosticsPage> createState() =>
      _WebSettingsDiagnosticsPageState();
}

class _WebSettingsDiagnosticsPageState extends State<WebSettingsDiagnosticsPage>
    with WebScrollToTopState<WebSettingsDiagnosticsPage> {
  Map<String, dynamic> diagnostics = {};
  bool loading = true;
  String? error;

  WebDownloadService get _downloadService => Get.find<WebDownloadService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      diagnostics = await backendApiClient.getDeploymentDiagnostics();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.deploymentDiagnostics'.tr),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'settings.copyDeploymentDiagnostics'.tr,
            onPressed: loading || diagnostics.isEmpty ? null : _copyDiagnostics,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorView(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Obx(
                    () => ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _summaryCard(context),
                        const SizedBox(height: 12),
                        _webSocketCard(context),
                        const SizedBox(height: 12),
                        for (final group in _orderedGroups()) ...[
                          _groupCard(context, group),
                          const SizedBox(height: 12),
                        ],
                        _networkCard(context),
                        const SizedBox(height: 12),
                        _logsCard(context),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _errorView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(
              'settings.diagnosticsLoadFailed'.trParams({'error': error!}),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text('common.retry'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    final status = diagnostics['status']?.toString() ?? 'warn';
    final summary = diagnostics['summary'] is Map
        ? Map<String, dynamic>.from(diagnostics['summary'] as Map)
        : const <String, dynamic>{};
    final warningCount = (summary['warningCount'] as num?)?.toInt() ?? 0;
    final errorCount = (summary['errorCount'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _statusIcon(status),
                  color: _statusColor(context, status),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'settings.deploymentDiagnosticsSummary'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _statusChip(context, status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'settings.deploymentDiagnosticsSummaryBody'.trParams({
                'warnings': '$warningCount',
                'errors': '$errorCount',
              }),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${'settings.generatedAt'.tr}: ${diagnostics['generatedAt'] ?? '-'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webSocketCard(BuildContext context) {
    final status = _downloadService.connectionStatus.value;
    final normalized = switch (status) {
      WebDownloadConnectionStatus.connected => 'ok',
      WebDownloadConnectionStatus.connecting ||
      WebDownloadConnectionStatus.reconnecting =>
        'warn',
      WebDownloadConnectionStatus.disconnected => 'warn',
    };
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.sync_alt_outlined,
          color: _statusColor(context, normalized),
        ),
        title: Text('settings.websocketStatus'.tr),
        subtitle: Text(_webSocketDetail(status)),
        trailing: _statusChip(context, normalized),
      ),
    );
  }

  Widget _groupCard(BuildContext context, String group) {
    final checks = _checksForGroup(group);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _groupLabel(group),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < checks.length; i++) ...[
              _checkTile(context, checks[i]),
              if (i != checks.length - 1) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checkTile(BuildContext context, Map<String, dynamic> check) {
    final status = check['status']?.toString() ?? 'warn';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _statusIcon(status),
          color: _statusColor(context, status),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      check['label']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _statusChip(context, status),
                ],
              ),
              const SizedBox(height: 4),
              Text(check['detail']?.toString() ?? '-'),
              finalHint(context, check['hint']?.toString()),
            ],
          ),
        ),
      ],
    );
  }

  Widget finalHint(BuildContext context, String? hint) {
    if (hint == null || hint.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        hint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _networkCard(BuildContext context) {
    final network = diagnostics['network'] is Map
        ? Map<String, dynamic>.from(diagnostics['network'] as Map)
        : const <String, dynamic>{};
    final proxyEnv =
        (network['proxyEnv'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.diagnosticsGroupNetwork'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _infoRow(
              context,
              'settings.ehProxyRoute'.tr,
              _sourceLabel(network['ehProxySource']?.toString() ?? 'DIRECT'),
            ),
            _infoRow(
              context,
              'settings.hathProxyRoute'.tr,
              _sourceLabel(network['hathProxySource']?.toString() ?? 'DIRECT'),
            ),
            _infoRow(
              context,
              'JH_HATH_PROXY',
              _boolLabel(network['hathProxyConfigured'] == true),
            ),
            const Divider(height: 18),
            if (proxyEnv.isEmpty)
              Text('settings.proxyEnvironmentEmpty'.tr)
            else
              for (final item in proxyEnv)
                _infoRow(
                  context,
                  item['name']?.toString() ?? '-',
                  _proxyEnvLabel(item),
                ),
          ],
        ),
      ),
    );
  }

  Widget _logsCard(BuildContext context) {
    final logs = diagnostics['logs'] is Map
        ? Map<String, dynamic>.from(diagnostics['logs'] as Map)
        : const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.diagnosticsGroupLogs'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _infoRow(
              context,
              'settings.logCount'.tr,
              '${(logs['count'] as num?)?.toInt() ?? 0}',
            ),
            _infoRow(
              context,
              'settings.logTotalSize'.tr,
              _formatBytes((logs['totalSize'] as num?)?.toInt() ?? 0),
            ),
            _infoRow(
              context,
              'settings.logLatestModified'.tr,
              logs['latestModified']?.toString() ?? '-',
            ),
          ],
        ),
      ),
    );
  }

  List<String> _orderedGroups() {
    final groups = _checks()
        .map((e) => e['group']?.toString() ?? 'other')
        .where((g) => g != 'network' && g != 'logs')
        .toSet();
    const order = ['service', 'storage', 'database', 'localGallery'];
    return [
      for (final group in order)
        if (groups.contains(group)) group,
      for (final group in groups)
        if (!order.contains(group)) group,
    ];
  }

  List<Map<String, dynamic>> _checks() {
    final checks = diagnostics['checks'] as List? ?? [];
    return checks.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  List<Map<String, dynamic>> _checksForGroup(String group) {
    return _checks().where((e) => e['group']?.toString() == group).toList();
  }

  String _groupLabel(String group) {
    return switch (group) {
      'service' => 'settings.diagnosticsGroupService'.tr,
      'storage' => 'settings.diagnosticsGroupStorage'.tr,
      'database' => 'settings.diagnosticsGroupDatabase'.tr,
      'localGallery' => 'settings.diagnosticsGroupLocalGallery'.tr,
      'logs' => 'settings.diagnosticsGroupLogs'.tr,
      'network' => 'settings.diagnosticsGroupNetwork'.tr,
      _ => group,
    };
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'ok' => Icons.check_circle_outline,
      'error' => Icons.error_outline,
      _ => Icons.warning_amber_outlined,
    };
  }

  Color _statusColor(BuildContext context, String status) {
    return switch (status) {
      'ok' => Colors.green,
      'error' => Theme.of(context).colorScheme.error,
      _ => Colors.orange,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'ok' => 'settings.diagnosticsStatusOk'.tr,
      'error' => 'settings.diagnosticsStatusError'.tr,
      _ => 'settings.diagnosticsStatusWarn'.tr,
    };
  }

  String _webSocketDetail(WebDownloadConnectionStatus status) {
    return switch (status) {
      WebDownloadConnectionStatus.connecting =>
        'settings.websocketConnecting'.tr,
      WebDownloadConnectionStatus.connected => 'settings.websocketConnected'.tr,
      WebDownloadConnectionStatus.reconnecting =>
        'settings.websocketReconnecting'.tr,
      WebDownloadConnectionStatus.disconnected =>
        'settings.websocketDisconnected'.tr,
    };
  }

  String _sourceLabel(String source) {
    return source == 'DIRECT' ? 'DIRECT' : source;
  }

  String _boolLabel(bool value) {
    return value ? 'settings.enabled'.tr : 'settings.disabled'.tr;
  }

  String _proxyEnvLabel(Map item) {
    if (item['configured'] != true) {
      return 'settings.disabled'.tr;
    }
    final value = item['value']?.toString();
    final suffix = item['hasCredentials'] == true
        ? ' (${'settings.proxyHasCredentials'.tr})'
        : '';
    return '${value == null || value.isEmpty ? 'configured' : value}$suffix';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KiB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MiB';
    }
    return '${(mb / 1024).toStringAsFixed(1)} GiB';
  }

  Future<void> _copyDiagnostics() async {
    final network = diagnostics['network'] is Map
        ? Map<String, dynamic>.from(diagnostics['network'] as Map)
        : const <String, dynamic>{};
    final logs = diagnostics['logs'] is Map
        ? Map<String, dynamic>.from(diagnostics['logs'] as Map)
        : const <String, dynamic>{};
    final data = {
      'title': 'JHenTai Web deployment diagnostics',
      'generatedAt': diagnostics['generatedAt'],
      'status': diagnostics['status'],
      'summary': diagnostics['summary'],
      'webSocket': _webSocketDetail(_downloadService.connectionStatus.value),
      'checks': _checks().map((check) {
        return {
          'group': check['group'],
          'label': check['label'],
          'status': check['status'],
          'detail': check['detail'],
          'hint': check['hint'],
        };
      }).toList(),
      'network': network,
      'logs': logs,
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
    );
    Get.snackbar(
      'common.success'.tr,
      'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
