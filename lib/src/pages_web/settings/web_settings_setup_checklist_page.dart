import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsSetupChecklistPage extends StatefulWidget {
  const WebSettingsSetupChecklistPage({super.key});

  @override
  State<WebSettingsSetupChecklistPage> createState() =>
      _WebSettingsSetupChecklistPageState();
}

class _WebSettingsSetupChecklistPageState
    extends State<WebSettingsSetupChecklistPage>
    with WebScrollToTopState<WebSettingsSetupChecklistPage> {
  Map<String, dynamic> checklist = {};
  bool loading = true;
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
      final data = await backendApiClient.getSetupChecklist();
      if (!mounted) return;
      setState(() => checklist = data);
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _copyChecklist() async {
    final checks = checklist['checks'] as List? ?? const [];
    final payload = {
      'title': 'JHenTai Docker setup checklist',
      'generatedAt': checklist['generatedAt'],
      'status': checklist['status'],
      'summary': checklist['summary'],
      'checks': [
        for (final item in checks.whereType<Map>())
          {
            'group': item['group'],
            'label': item['label'],
            'status': item['status'],
            'detail': item['detail'],
            'hint': item['hint'],
          },
      ],
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    Get.snackbar('common.success'.tr, 'settings.setupChecklistCopied'.tr,
        snackPosition: SnackPosition.BOTTOM);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.setupChecklist'.tr),
        actions: [
          IconButton(
            tooltip: 'settings.copySetupChecklist'.tr,
            onPressed: checklist.isEmpty ? null : _copyChecklist,
            icon: const Icon(Icons.copy_outlined),
          ),
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
              ? _errorView()
              : _content(context),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(
              'settings.setupChecklistLoadFailed'.trParams({'error': error!}),
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

  Widget _content(BuildContext context) {
    final checks = (checklist['checks'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in checks) {
      grouped.putIfAbsent(item['group']?.toString() ?? 'other', () => []);
      grouped[item['group']?.toString() ?? 'other']!.add(item);
    }
    final summary = checklist['summary'] is Map
        ? Map<String, dynamic>.from(checklist['summary'] as Map)
        : const <String, dynamic>{};
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(context, summary),
        const SizedBox(height: 12),
        Text(
          'settings.setupChecklistHint'.tr,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        for (final entry in grouped.entries) ...[
          _groupTitle(context, entry.key),
          const SizedBox(height: 8),
          for (final item in entry.value) _checkTile(context, item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _summaryCard(BuildContext context, Map<String, dynamic> summary) {
    final status = checklist['status']?.toString() ?? 'warn';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_statusIcon(status), color: _statusColor(context, status)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.setupChecklistSummary'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'settings.setupChecklistSummaryBody'.trParams({
                      'errors': '${summary['errorCount'] ?? 0}',
                      'warnings': '${summary['warningCount'] ?? 0}',
                      'total': '${summary['total'] ?? 0}',
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(BuildContext context, String group) {
    return Text(
      _groupLabel(group),
      style: Theme.of(context).textTheme.titleSmall,
    );
  }

  Widget _checkTile(BuildContext context, Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'warn';
    final route = item['route']?.toString();
    final copyText = item['copyText']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(status),
                      color: _statusColor(context, status), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item['label']?.toString() ?? '-',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Chip(
                    label: Text(_statusLabel(status)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(item['detail']?.toString() ?? '-'),
              const SizedBox(height: 4),
              Text(
                item['hint']?.toString() ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if ((route != null && route.isNotEmpty) || copyText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (route != null && route.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => Get.toNamed(route),
                          icon: const Icon(Icons.open_in_new),
                          label: Text('settings.troubleshootingOpenTarget'.tr),
                        ),
                      if (copyText.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: copyText),
                            );
                            Get.snackbar(
                              'common.success'.tr,
                              'hasCopiedToClipboard'.tr,
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: Text('settings.troubleshootingCopyFix'.tr),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _groupLabel(String group) {
    return switch (group) {
      'service' => 'settings.diagnosticsGroupService'.tr,
      'account' => 'settings.account'.tr,
      'storage' => 'settings.diagnosticsGroupStorage'.tr,
      'database' => 'settings.diagnosticsGroupDatabase'.tr,
      'maintenance' => 'settings.maintenanceCenter'.tr,
      'network' => 'settings.diagnosticsGroupNetwork'.tr,
      'superResolution' => 'superResolution.title'.tr,
      'downloads' => 'settings.menuDownload'.tr,
      _ => group,
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

  IconData _statusIcon(String status) {
    return switch (status) {
      'ok' => Icons.check_circle_outline,
      'error' => Icons.error_outline,
      'skipped' => Icons.radio_button_unchecked,
      _ => Icons.warning_amber_outlined,
    };
  }

  Color _statusColor(BuildContext context, String status) {
    return switch (status) {
      'ok' => Colors.green,
      'error' => Theme.of(context).colorScheme.error,
      'skipped' => Colors.grey,
      _ => Colors.orange,
    };
  }
}
