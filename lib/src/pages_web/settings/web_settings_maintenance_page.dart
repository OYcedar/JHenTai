import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebSettingsMaintenancePage extends StatefulWidget {
  const WebSettingsMaintenancePage({super.key});

  @override
  State<WebSettingsMaintenancePage> createState() =>
      _WebSettingsMaintenancePageState();
}

class _WebSettingsMaintenancePageState extends State<WebSettingsMaintenancePage>
    with WebScrollToTopState<WebSettingsMaintenancePage> {
  Map<String, dynamic> status = {};
  Map<String, dynamic>? updateCheck;
  bool loading = true;
  bool checkingUpdate = false;
  bool downloadingBackup = false;
  String? error;

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
      status = await backendApiClient.getMaintenanceStatus();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => checkingUpdate = true);
    try {
      final result = await backendApiClient.checkMaintenanceUpdate();
      if (mounted) {
        setState(() => updateCheck = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          updateCheck = {
            'status': 'warn',
            'message': '$e',
            'updateAvailable': false,
          };
        });
      }
    } finally {
      if (mounted) {
        setState(() => checkingUpdate = false);
      }
    }
  }

  Future<void> _downloadBackup() async {
    setState(() => downloadingBackup = true);
    try {
      final backup = await backendApiClient.downloadSqliteBackup();
      _downloadBytes(backup.bytes, backup.fileName);
      Get.snackbar(
        'common.success'.tr,
        'settings.sqliteBackupDownloaded'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.sqliteBackupFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => downloadingBackup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.maintenanceCenter'.tr),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
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
                      _runtimeCard(context),
                      const SizedBox(height: 12),
                      _updateCard(context),
                      const SizedBox(height: 12),
                      _backupCard(context),
                      const SizedBox(height: 12),
                      _storageCard(context),
                      const SizedBox(height: 12),
                      _pathCard(context),
                      const SizedBox(height: 12),
                      _tipsCard(context),
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
              'settings.maintenanceLoadFailed'.trParams({'error': error!}),
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

  Widget _runtimeCard(BuildContext context) {
    final runtime = _map(status['runtime']);
    return _sectionCard(
      context,
      icon: Icons.info_outline,
      title: 'settings.maintenanceRuntime'.tr,
      children: [
        _infoRow('settings.appVersionLabel'.tr,
            runtime['appVersion']?.toString() ?? 'local/dev'),
        _infoRow('settings.dockerImageTag'.tr,
            runtime['dockerTag']?.toString() ?? 'local/dev'),
        _infoRow('settings.forkRevision'.tr,
            runtime['forkRevision']?.toString() ?? 'local/dev'),
        _infoRow('settings.imageChannel'.tr,
            runtime['imageChannel']?.toString() ?? 'local/dev'),
      ],
    );
  }

  Widget _updateCard(BuildContext context) {
    final result = updateCheck;
    final updateAvailable = result?['updateAvailable'] == true;
    final statusValue = result?['status']?.toString() ?? 'idle';
    final color = statusValue == 'warn'
        ? Colors.orange
        : updateAvailable
            ? Theme.of(context).colorScheme.primary
            : Colors.green;
    return _sectionCard(
      context,
      icon: Icons.system_update_alt_outlined,
      title: 'settings.maintenanceUpdate'.tr,
      trailing: checkingUpdate
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : OutlinedButton.icon(
              onPressed: _checkUpdate,
              icon: const Icon(Icons.search),
              label: Text('settings.checkDockerUpdate'.tr),
            ),
      children: [
        if (result == null)
          Text('settings.updateCheckManualHint'.tr)
        else ...[
          Row(
            children: [
              Icon(
                statusValue == 'warn'
                    ? Icons.warning_amber_outlined
                    : updateAvailable
                        ? Icons.new_releases_outlined
                        : Icons.check_circle_outline,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(result['message']?.toString() ?? '-')),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow('settings.currentImageTag'.tr,
              result['currentTag']?.toString() ?? '-'),
          _infoRow('settings.latestImageTag'.tr,
              result['latestTag']?.toString() ?? '-'),
        ],
      ],
    );
  }

  Widget _backupCard(BuildContext context) {
    return _sectionCard(
      context,
      icon: Icons.backup_outlined,
      title: 'settings.maintenanceBackup'.tr,
      children: [
        Text('settings.sqliteBackupSensitiveHint'.tr),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: downloadingBackup ? null : _downloadBackup,
          icon: downloadingBackup
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text('settings.downloadSqliteBackup'.tr),
        ),
      ],
    );
  }

  Widget _storageCard(BuildContext context) {
    final storage = _map(status['storage']);
    return _sectionCard(
      context,
      icon: Icons.storage_outlined,
      title: 'settings.maintenanceStorage'.tr,
      children: [
        _infoRow('settings.databaseSize'.tr,
            _formatBytes(_intValue(storage['databaseBytes']))),
        _infoRow('settings.logsSize'.tr,
            _formatBytes(_intValue(storage['logsBytes']))),
        _infoRow('settings.pageCacheSize'.tr,
            _formatBytes(_intValue(storage['pageCacheBytes']))),
        _infoRow('settings.pageCacheCount'.tr,
            '${_intValue(storage['pageCacheCount'])}'),
      ],
    );
  }

  Widget _pathCard(BuildContext context) {
    final checks = (status['checks'] as List? ?? [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    return _sectionCard(
      context,
      icon: Icons.folder_outlined,
      title: 'settings.maintenancePaths'.tr,
      children: [
        for (final check in checks) _pathRow(context, check),
      ],
    );
  }

  Widget _tipsCard(BuildContext context) {
    return _sectionCard(
      context,
      icon: Icons.tips_and_updates_outlined,
      title: 'settings.maintenanceTips'.tr,
      children: [
        Text('settings.maintenanceTipPinVersion'.tr),
        const SizedBox(height: 6),
        Text('settings.maintenanceTipBackup'.tr),
        const SizedBox(height: 6),
        Text('settings.maintenanceTipNoImageBackup'.tr),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/diagnostics'),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text('settings.deploymentDiagnostics'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/web/settings/advanced'),
              icon: const Icon(Icons.article_outlined),
              label: Text('settings.serverLogs'.tr),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
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
                Icon(icon, color: Theme.of(context).colorScheme.primary),
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

  Widget _pathRow(BuildContext context, Map<String, dynamic> check) {
    final ok = check['status'] == 'ok';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: ok ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check['id']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                SelectableText(
                  check['path']?.toString() ?? '-',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  check['message']?.toString() ?? '-',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
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

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  int _intValue(Object? raw) => (raw as num?)?.toInt() ?? 0;

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

  void _downloadBytes(Uint8List bytes, String fileName) {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
