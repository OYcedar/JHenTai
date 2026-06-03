import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsTroubleshootingPage extends StatefulWidget {
  const WebSettingsTroubleshootingPage({super.key});

  @override
  State<WebSettingsTroubleshootingPage> createState() =>
      _WebSettingsTroubleshootingPageState();
}

class _WebSettingsTroubleshootingPageState
    extends State<WebSettingsTroubleshootingPage>
    with WebScrollToTopState<WebSettingsTroubleshootingPage> {
  final _hathUrlController = TextEditingController();
  Map<String, dynamic> snapshot = {};
  Map<String, dynamic> probe = {};
  bool loading = true;
  bool probing = false;
  String? error;

  WebDownloadService get _downloads => Get.find<WebDownloadService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hathUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await backendApiClient.getTroubleshootingStatus();
      if (!mounted) {
        return;
      }
      setState(() => snapshot = data);
    } catch (e) {
      if (mounted) {
        error = '$e';
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _runProbe() async {
    setState(() => probing = true);
    try {
      final result = await backendApiClient.probeTroubleshooting(
        probes: const ['network', 'hath', 'superResolution'],
        imageUrl: _hathUrlController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() => probe = result);
      await _load();
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.troubleshootingProbeFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => probing = false);
      }
    }
  }

  Future<void> _copyDiagnostics() async {
    final data = {
      'snapshot': snapshot,
      if (probe.isNotEmpty) 'probe': probe,
      'webSocket': _webSocketDetail(_downloads.connectionStatus.value),
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

  Future<void> _copyGpuCompose() async {
    final snippet = _gpuComposeSnippet();
    if (snippet.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: snippet));
    Get.snackbar(
      'common.success'.tr,
      'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.troubleshootingWorkbench'.tr),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'settings.copyDeploymentDiagnostics'.tr,
            onPressed: loading || snapshot.isEmpty ? null : _copyDiagnostics,
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
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summaryCard(context),
                      const SizedBox(height: 12),
                      _probeCard(context),
                      const SizedBox(height: 12),
                      _networkCard(context),
                      const SizedBox(height: 12),
                      _superResolutionCard(context),
                      const SizedBox(height: 12),
                      _logsCard(context),
                      const SizedBox(height: 12),
                      _actionsCard(context),
                    ],
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
              'settings.troubleshootingLoadFailed'.trParams({'error': error!}),
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
    final status = snapshot['status']?.toString() ?? 'warn';
    final summary = _map(snapshot['summary']);
    final issues = (summary['issueCount'] as num?)?.toInt() ?? 0;
    return _sectionCard(
      context,
      icon: _statusIcon(status),
      iconColor: _statusColor(context, status),
      title: 'settings.troubleshootingSummary'.tr,
      trailing: _statusChip(context, status),
      children: [
        Text('settings.troubleshootingSummaryBody'
            .trParams({'count': '$issues'})),
        const SizedBox(height: 8),
        Obx(() {
          final status = _downloads.connectionStatus.value;
          return _infoRow(
            'settings.websocketStatus'.tr,
            _webSocketDetail(status),
          );
        }),
      ],
    );
  }

  Widget _probeCard(BuildContext context) {
    final results = _map(probe['results']);
    return _sectionCard(
      context,
      icon: Icons.science_outlined,
      title: 'settings.troubleshootingActiveProbe'.tr,
      children: [
        Text('settings.troubleshootingActiveProbeHint'.tr),
        const SizedBox(height: 12),
        TextField(
          controller: _hathUrlController,
          decoration: InputDecoration(
            labelText: 'settings.troubleshootingHathUrl'.tr,
            hintText: 'https://...hath.network/...',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: probing ? null : _runProbe,
            icon: probing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_outlined),
            label: Text('settings.runTroubleshootingProbe'.tr),
          ),
        ),
        if (results.isNotEmpty) ...[
          const Divider(height: 24),
          _probeResultTile(context, 'network', _map(results['network'])),
          _probeResultTile(context, 'hath', _map(results['hath'])),
          _probeResultTile(
              context, 'superResolution', _map(results['superResolution'])),
        ],
      ],
    );
  }

  Widget _networkCard(BuildContext context) {
    final network = _map(snapshot['network']);
    return _sectionCard(
      context,
      icon: Icons.wifi_tethering,
      title: 'settings.diagnosticsGroupNetwork'.tr,
      children: [
        _infoRow('settings.ehProxyRoute'.tr,
            network['ehProxySource']?.toString() ?? 'DIRECT'),
        _infoRow('settings.hathProxyRoute'.tr,
            network['hathProxySource']?.toString() ?? 'DIRECT'),
        _infoRow('JH_HATH_PROXY',
            _boolLabel(network['hathProxyConfigured'] == true)),
        _infoRow('JH_IMAGE_PROXY_DEBUG',
            _boolLabel(network['imageProxyDebug'] == true)),
      ],
    );
  }

  Widget _superResolutionCard(BuildContext context) {
    final sr = _map(snapshot['superResolution']);
    final caps = _map(sr['capabilities']);
    final gpu = _map(caps['gpu']);
    final runtime = _map(caps['runtime']);
    final jobs = _map(sr['jobs']);
    final devices = (gpu['devices'] as List? ?? const []).whereType<Map>();
    return _sectionCard(
      context,
      icon: Icons.auto_fix_high_outlined,
      title: 'superResolution.title'.tr,
      trailing: _statusChip(context, caps['status']?.toString() ?? 'warn'),
      children: [
        _infoRow('superResolution.arch'.tr, runtime['arch']?.toString() ?? '-'),
        _infoRow('superResolution.gpu'.tr,
            gpu['available'] == true ? 'common.yes'.tr : 'common.no'.tr),
        _infoRow('/dev/dri', gpu['hasDevDri'] == true ? 'yes' : 'no'),
        _infoRow('settings.troubleshootingFailedJobs'.tr,
            '${(jobs['failed'] as num?)?.toInt() ?? 0}'),
        if (devices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('settings.troubleshootingGpuDevices'.tr,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final item in devices)
            Text(
              '${item['path']} · gid=${item['gid'] ?? '-'} · r=${item['readable']} w=${item['writable']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        if (_gpuComposeSnippet().isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _copyGpuCompose,
            icon: const Icon(Icons.copy_all_outlined),
            label: Text('settings.copyGpuComposeSnippet'.tr),
          ),
        ],
      ],
    );
  }

  Widget _logsCard(BuildContext context) {
    final logs = _map(snapshot['logs']);
    final problems =
        (logs['recentProblems'] as List? ?? const []).whereType<Map>().toList();
    return _sectionCard(
      context,
      icon: Icons.article_outlined,
      title: 'settings.troubleshootingRecentProblems'.tr,
      children: [
        if (problems.isEmpty)
          Text('settings.troubleshootingNoRecentProblems'.tr)
        else
          for (final item in problems.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${item['file'] ?? '-'}: ${item['line'] ?? '-'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
      ],
    );
  }

  Widget _actionsCard(BuildContext context) {
    return _sectionCard(
      context,
      icon: Icons.build_outlined,
      title: 'settings.troubleshootingActions'.tr,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/network'),
              icon: const Icon(Icons.wifi_tethering),
              label: Text('settings.menuNetwork'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/super-resolution'),
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: Text('superResolution.title'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/advanced'),
              icon: const Icon(Icons.article_outlined),
              label: Text('settings.serverLogs'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/diagnostics'),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text('settings.deploymentDiagnostics'.tr),
            ),
          ],
        ),
      ],
    );
  }

  Widget _probeResultTile(
    BuildContext context,
    String key,
    Map<String, dynamic> result,
  ) {
    if (result.isEmpty) {
      return const SizedBox.shrink();
    }
    final status = result['status']?.toString() ?? 'warn';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_statusIcon(status), color: _statusColor(context, status)),
      title: Text('settings.troubleshootingProbe_$key'.tr),
      subtitle: Text(result['detail']?.toString() ?? '-'),
      trailing: _statusChip(context, status),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: iconColor ?? Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
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
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: SelectableText(value)),
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
      'skipped' => Icons.do_not_disturb_on_outlined,
      _ => Icons.warning_amber_outlined,
    };
  }

  Color _statusColor(BuildContext context, String status) {
    return switch (status) {
      'ok' => Colors.green,
      'error' => Theme.of(context).colorScheme.error,
      'skipped' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => Colors.orange,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'ok' => 'settings.diagnosticsStatusOk'.tr,
      'error' => 'settings.diagnosticsStatusError'.tr,
      'skipped' => 'settings.troubleshootingSkipped'.tr,
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

  String _boolLabel(bool value) {
    return value ? 'settings.enabled'.tr : 'settings.disabled'.tr;
  }

  String _gpuComposeSnippet() {
    final sr = _map(snapshot['superResolution']);
    final caps = _map(sr['capabilities']);
    final gpu = _map(caps['gpu']);
    final fromProbe = _map(_map(probe['results'])['superResolution']);
    return gpu['composeSnippet']?.toString().isNotEmpty == true
        ? gpu['composeSnippet'].toString()
        : fromProbe['composeSnippet']?.toString() ?? '';
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }
}
