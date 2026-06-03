import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:js_interop';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebSettingsAdvancedPage extends StatefulWidget {
  const WebSettingsAdvancedPage({super.key});

  @override
  State<WebSettingsAdvancedPage> createState() =>
      _WebSettingsAdvancedPageState();
}

class _WebSettingsAdvancedPageState extends State<WebSettingsAdvancedPage>
    with WebScrollToTopState<WebSettingsAdvancedPage> {
  final WebSettingsController controller = Get.find<WebSettingsController>();
  final logs = <Map<String, dynamic>>[];
  bool logsLoading = false;
  String? logsError;
  int totalLogSize = 0;
  bool pageCacheLoading = false;
  String? pageCacheError;
  int pageCacheSize = 0;
  int pageCacheCount = 0;
  bool exportingData = false;
  bool exportingAppData = false;
  bool importingData = false;
  String? importDataStatus;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _loadPageCacheStats();
  }

  Future<void> _loadLogs() async {
    setState(() {
      logsLoading = true;
      logsError = null;
    });
    try {
      final data = await backendApiClient.listServerLogs();
      final rawLogs = data['logs'] as List? ?? [];
      logs
        ..clear()
        ..addAll(rawLogs.map((e) => Map<String, dynamic>.from(e as Map)));
      totalLogSize = (data['totalSize'] as num?)?.toInt() ?? 0;
    } catch (e) {
      logsError = '$e';
    } finally {
      if (mounted) {
        setState(() => logsLoading = false);
      }
    }
  }

  Future<void> _clearLogs() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings.clearLogsTitle'.tr),
        content: Text('settings.clearLogsConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await backendApiClient.clearServerLogs();
      await _loadLogs();
      Get.snackbar(
        'common.success'.tr,
        'clearSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.clearLogsFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _loadPageCacheStats() async {
    setState(() {
      pageCacheLoading = true;
      pageCacheError = null;
    });
    try {
      final data = await backendApiClient.getPageCacheStats();
      pageCacheSize = (data['size'] as num?)?.toInt() ?? 0;
      pageCacheCount = (data['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      pageCacheError = '$e';
    } finally {
      if (mounted) {
        setState(() => pageCacheLoading = false);
      }
    }
  }

  Future<void> _clearPageCache() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings.clearPageCacheTitle'.tr),
        content: Text('settings.clearPageCacheConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await backendApiClient.clearPageCache();
      await _loadPageCacheStats();
      Get.snackbar(
        'common.success'.tr,
        'clearSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.clearPageCacheFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _exportData() async {
    setState(() => exportingData = true);
    try {
      await _downloadWebDataExport('jhentai-web-export');
      Get.snackbar(
        'common.success'.tr,
        'settings.exportDataSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.exportDataFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => exportingData = false);
      }
    }
  }

  Future<void> _exportAppData() async {
    setState(() => exportingAppData = true);
    try {
      final data = await backendApiClient.exportAppUserData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now().toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName = 'JHenTaiConfig-${now.year}${two(now.month)}'
          '${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      _downloadTextFile(fileName, json, mimeType: 'application/json');
      Get.snackbar(
        'common.success'.tr,
        'settings.exportAppDataSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.exportDataFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => exportingAppData = false);
      }
    }
  }

  Future<void> _importData() async {
    try {
      final picked = await _pickJsonFile();
      if (picked == null) {
        return;
      }
      setState(() {
        importingData = true;
        importDataStatus = 'settings.importStatusAnalyzing'.trParams({
          'name': picked.name,
          'size': _formatBytes(picked.size),
        });
      });
      final decoded = jsonDecode(picked.text);
      final data = _normalizeImportData(decoded);
      if (data == null) {
        throw const FormatException('Unsupported JSON import format');
      }
      final preview = await backendApiClient.importUserData(data, dryRun: true);
      if (!mounted) {
        return;
      }
      final ok = await Get.dialog<bool>(
        _ImportPreviewDialog(
          preview: preview,
          fileName: picked.name,
          fileSize: picked.size,
        ),
      );
      if (ok != true) {
        if (mounted) {
          setState(() {
            importDataStatus = 'settings.importStatusCancelled'.trParams({
              'name': picked.name,
            });
          });
        }
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        importDataStatus = 'settings.importStatusBackingUp'.tr;
      });
      await _downloadWebDataExport('jhentai-web-backup-before-import');
      if (!mounted) {
        return;
      }
      setState(() {
        importDataStatus = 'settings.importStatusImporting'.trParams({
          'name': picked.name,
        });
      });
      final result = await backendApiClient.importUserData(data);
      final imported = result['imported'] is Map
          ? Map<String, dynamic>.from(result['imported'] as Map)
          : const <String, dynamic>{};
      final count = imported.values.fold<int>(
        0,
        (sum, value) => sum + ((value as num?)?.toInt() ?? 0),
      );
      await controller.refreshStatus();
      final source = result['source']?.toString() == 'app'
          ? 'settings.importSourceApp'.tr
          : 'settings.importSourceWeb'.tr;
      final detail = _formatImportCounts(imported);
      if (mounted) {
        setState(() {
          importDataStatus = count > 0
              ? 'settings.importStatusDone'.trParams({
                  'source': source,
                  'count': '$count',
                  'detail': detail,
                })
              : 'settings.importStatusNoChange'.trParams({
                  'source': source,
                });
        });
      }
      Get.snackbar(
        count > 0 ? 'common.success'.tr : 'common.warning'.tr,
        count > 0
            ? 'settings.importDataSuccessDetail'.trParams({
                'count': '$count',
                'detail': detail,
              })
            : 'settings.importNoChange'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          importDataStatus = 'settings.importStatusFailed'.trParams({
            'error': '$e',
          });
        });
      }
      Get.snackbar(
        'common.error'.tr,
        'settings.importDataFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => importingData = false);
      }
    }
  }

  Future<void> _downloadWebDataExport(String prefix) async {
    final data = await backendApiClient.exportUserData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final now = DateTime.now().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final fileName = '$prefix-${now.year}${two(now.month)}'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    _downloadTextFile(fileName, json, mimeType: 'application/json');
  }

  Future<void> _openLog(Map<String, dynamic> item) async {
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty) {
      return;
    }
    try {
      final content = await backendApiClient.readServerLog(name);
      if (!mounted) {
        return;
      }
      await Get.to(() => _WebLogPage(name: name, content: content));
      await _loadLogs();
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.loadLogFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menuAdvanced'.tr),
        actions: [
          IconButton(
            tooltip: 'reload'.tr,
            onPressed: logsLoading ? null : _loadLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
              'settings.advancedWebIntro'.tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.image_not_supported_outlined),
                    title: Text('settings.noImageMode'.tr),
                    subtitle: Text('settings.noImageModeHint'.tr),
                    value: controller.noImageMode.value,
                    onChanged: controller.setNoImageMode,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.content_paste_search),
                    title: Text('checkClipboard'.tr),
                    subtitle: Text('settings.checkClipboardHint'.tr),
                    value: controller.checkClipboard.value,
                    onChanged: controller.setCheckClipboard,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text('settings.exportData'.tr),
                    subtitle: Text('settings.exportDataHint'.tr),
                    trailing: exportingData
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    onTap: exportingData ? null : _exportData,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.phone_android_outlined),
                    title: Text('settings.exportAppData'.tr),
                    subtitle: Text('settings.exportAppDataHint'.tr),
                    trailing: exportingAppData
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    onTap: exportingAppData ? null : _exportAppData,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: Text('settings.cloudSync'.tr),
                    subtitle: Text('settings.cloudSyncHint'.tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed('/web/settings/cloud-sync'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: Text('settings.importData'.tr),
                    subtitle: Text(
                      [
                        'settings.importDataHint'.tr,
                        if (importDataStatus != null) importDataStatus!,
                      ].join('\n'),
                    ),
                    trailing: importingData
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    onTap: importingData ? null : _importData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildPageCacheSection(context),
            const SizedBox(height: 24),
            _buildLogsSection(context),
            const SizedBox(height: 24),
            Text(
              'settings.serverInfo'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            ),
          ],
        );
      }),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _buildPageCacheSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'settings.pageCache'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'reload'.tr,
              onPressed: pageCacheLoading ? null : _loadPageCacheStats,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cached_outlined),
            title: Text('settings.clearPageCache'.tr),
            subtitle: pageCacheError != null
                ? Text(
                    'settings.loadPageCacheFailed'
                        .trParams({'error': pageCacheError!}),
                  )
                : Text(
                    'settings.pageCacheSummary'.trParams({
                      'count': '$pageCacheCount',
                      'size': _formatBytes(pageCacheSize),
                    }),
                  ),
            trailing: pageCacheLoading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'settings.clearPageCache'.tr,
                    onPressed: pageCacheCount == 0 ? null : _clearPageCache,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
            onTap: pageCacheError == null ? null : _loadPageCacheStats,
          ),
        ),
      ],
    );
  }

  Widget _buildLogsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'settings.serverLogs'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              _formatBytes(totalLogSize),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IconButton(
              tooltip: 'clearLogs'.tr,
              onPressed: logs.isEmpty || logsLoading ? null : _clearLogs,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: logsLoading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : logsError != null
                  ? ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(
                        'settings.loadLogsFailed'
                            .trParams({'error': logsError!}),
                      ),
                      trailing: const Icon(Icons.refresh),
                      onTap: _loadLogs,
                    )
                  : logs.isEmpty
                      ? ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text('settings.noLogs'.tr),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < logs.length; i++) ...[
                              _logTile(logs[i]),
                              if (i != logs.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _logTile(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '-';
    final size = (item['size'] as num?)?.toInt() ?? 0;
    final modified = item['modified']?.toString() ?? '';
    return ListTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_formatBytes(size)}${modified.isEmpty ? '' : ' · ${_formatModified(modified)}'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openLog(item),
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
            child: Text(value, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 10 ? 1 : 2);
    return '$text ${units[unit]}';
  }

  String _formatModified(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) {
      return raw;
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  Object? _normalizeImportData(Object? decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      if (decoded['format'] == 'jhentai-web-export-v1' &&
          decoded['sections'] is Map) {
        return decoded;
      }
      for (final key in ['data', 'configs', 'items']) {
        final value = decoded[key];
        if (value is List) {
          return value;
        }
      }
    }
    return null;
  }

  String _formatImportCounts(Map<String, dynamic> imported) {
    final labels = {
      'config': 'settings.importSectionConfig'.tr,
      'blockRules': 'settings.importSectionBlockRules'.tr,
      'history': 'settings.importSectionHistory'.tr,
      'searchHistory': 'settings.importSectionSearchHistory'.tr,
      'quickSearch': 'settings.importSectionQuickSearch'.tr,
      'readProgress': 'settings.importSectionReadProgress'.tr,
    };
    return labels.entries
        .map((entry) {
          final count = (imported[entry.key] as num?)?.toInt() ?? 0;
          return count > 0 ? '${entry.value} $count' : '';
        })
        .where((text) => text.isNotEmpty)
        .join(' · ');
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value >= 10 ? 1 : 2);
  return '$text ${units[unit]}';
}

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({
    required this.preview,
    required this.fileName,
    required this.fileSize,
  });

  final Map<String, dynamic> preview;
  final String fileName;
  final int fileSize;

  @override
  Widget build(BuildContext context) {
    final summary = preview['summary'] is Map
        ? Map<String, dynamic>.from(preview['summary'] as Map)
        : const <String, dynamic>{};
    final sections = summary['sections'] is Map
        ? Map<String, dynamic>.from(summary['sections'] as Map)
        : const <String, dynamic>{};
    final source = preview['source']?.toString() == 'app'
        ? 'settings.importSourceApp'.tr
        : 'settings.importSourceWeb'.tr;
    final rows = [
      _summaryRow('settings.importSectionConfig'.tr, sections['config']),
      _summaryRow(
          'settings.importSectionBlockRules'.tr, sections['blockRules']),
      _summaryRow('settings.importSectionHistory'.tr, sections['history']),
      _summaryRow(
          'settings.importSectionSearchHistory'.tr, sections['searchHistory']),
      _summaryRow(
          'settings.importSectionQuickSearch'.tr, sections['quickSearch']),
      _summaryRow(
          'settings.importSectionReadProgress'.tr, sections['readProgress']),
    ].where((row) => row != null).cast<_ImportPreviewRow>().toList();

    return AlertDialog(
      title: Text('settings.importPreviewTitle'.tr),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('settings.importPreviewSource'.trParams({'source': source})),
              const SizedBox(height: 8),
              Text(
                'settings.importPreviewFile'.trParams({
                  'name': fileName,
                  'size': _formatBytes(fileSize),
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'settings.importPreviewSummary'.trParams({
                  'count': '${_intValue(summary['importable'])}',
                  'replace': '${_intValue(summary['replacing'])}',
                  'skip': '${_intValue(summary['skipped'])}',
                }),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text(
                  'settings.importPreviewEmpty'.tr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              if (rows.isEmpty) const SizedBox(height: 12),
              if (rows.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        _ImportPreviewRowTile(row: rows[i]),
                        if (i != rows.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'settings.importPreviewLocalReadHint'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'settings.importPreviewBackupHint'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'settings.importPreviewOverwriteHint'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text('common.cancel'.tr),
        ),
        FilledButton.icon(
          onPressed: _intValue(summary['importable']) <= 0
              ? null
              : () => Get.back(result: true),
          icon: const Icon(Icons.backup_outlined),
          label: Text('settings.importConfirmWithBackup'.tr),
        ),
      ],
    );
  }

  static _ImportPreviewRow? _summaryRow(String label, Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final section = Map<String, dynamic>.from(raw);
    final importable = _intValue(section['importable']);
    final replacing = _intValue(section['replacing']);
    final skipped = _intValue(section['skipped']);
    if (importable == 0 && replacing == 0 && skipped == 0) {
      return null;
    }
    return _ImportPreviewRow(
      label: label,
      importable: importable,
      replacing: replacing,
      skipped: skipped,
    );
  }

  static int _intValue(Object? raw) => (raw as num?)?.toInt() ?? 0;
}

class _PickedJsonFile {
  const _PickedJsonFile({
    required this.name,
    required this.size,
    required this.text,
  });

  final String name;
  final int size;
  final String text;
}

class _ImportPreviewRow {
  const _ImportPreviewRow({
    required this.label,
    required this.importable,
    required this.replacing,
    required this.skipped,
  });

  final String label;
  final int importable;
  final int replacing;
  final int skipped;
}

class _ImportPreviewRowTile extends StatelessWidget {
  const _ImportPreviewRowTile({required this.row});

  final _ImportPreviewRow row;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(row.label),
      subtitle: Text(
        'settings.importSectionSummary'.trParams({
          'count': '${row.importable}',
          'replace': '${row.replacing}',
          'skip': '${row.skipped}',
        }),
      ),
    );
  }
}

Future<_PickedJsonFile?> _pickJsonFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'application/json,.json'
    ..style.display = 'none';
  web.document.body?.appendChild(input);
  try {
    final changed = input.onChange.first;
    input.click();
    await changed;
    final file = input.files?.item(0);
    if (file == null) {
      return null;
    }
    final reader = web.FileReader();
    final completer = Completer<String>();
    reader.onLoadEnd.first.then((_) {
      final error = reader.error;
      if (error != null) {
        completer.completeError(error.message);
        return;
      }
      final result = reader.result;
      completer.complete(result == null ? '' : (result as JSString).toDart);
    });
    reader.readAsText(file);
    final text = await completer.future;
    return _PickedJsonFile(
      name: file.name,
      size: file.size,
      text: text,
    );
  } finally {
    input.remove();
  }
}

void _downloadTextFile(
  String name,
  String content, {
  String mimeType = 'text/plain',
}) {
  final blob =
      web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = objectUrl;
  anchor.download = name;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(objectUrl);
}

class _WebLogPage extends StatefulWidget {
  const _WebLogPage({required this.name, required this.content});

  final String name;
  final String content;

  @override
  State<_WebLogPage> createState() => _WebLogPageState();
}

class _WebLogPageState extends State<_WebLogPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _matches = <TextRange>[];
  var _activeMatch = -1;
  var _query = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    Get.snackbar(
      'common.success'.tr,
      'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _download() {
    if (widget.content.isEmpty) {
      return;
    }
    _downloadTextFile(widget.name, widget.content);
  }

  void _updateSearch(String value) {
    final query = value.trim();
    final nextMatches = <TextRange>[];
    if (query.isNotEmpty) {
      final source = widget.content.toLowerCase();
      final target = query.toLowerCase();
      var index = source.indexOf(target);
      while (index != -1) {
        nextMatches.add(TextRange(start: index, end: index + target.length));
        index = source.indexOf(target, index + target.length);
      }
    }
    setState(() {
      _query = query;
      _matches
        ..clear()
        ..addAll(nextMatches);
      _activeMatch = _matches.isEmpty ? -1 : 0;
    });
    _jumpToActiveMatch();
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearch('');
  }

  void _previousMatch() {
    if (_matches.isEmpty) {
      return;
    }
    setState(() {
      _activeMatch = (_activeMatch - 1 + _matches.length) % _matches.length;
    });
    _jumpToActiveMatch();
  }

  void _nextMatch() {
    if (_matches.isEmpty) {
      return;
    }
    setState(() {
      _activeMatch = (_activeMatch + 1) % _matches.length;
    });
    _jumpToActiveMatch();
  }

  Future<void> _jumpToActiveMatch() async {
    if (_activeMatch < 0 || !_scrollController.hasClients) {
      return;
    }
    final offset = _estimateMatchOffset(_matches[_activeMatch].start);
    await _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  double _estimateMatchOffset(int charIndex) {
    final before = widget.content.substring(0, charIndex);
    final line = '\n'.allMatches(before).length;
    return (line * 16.2 - 120)
        .clamp(0, _scrollController.position.maxScrollExtent)
        .toDouble();
  }

  Widget _buildSearchBar() {
    final counter = _query.isEmpty
        ? ''
        : _matches.isEmpty
            ? 'settings.noLogMatches'.tr
            : 'settings.logMatchCounter'.trParams({
                'current': '${_activeMatch + 1}',
                'total': '${_matches.length}',
              });
    final searchField = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'settings.searchLog'.tr,
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'common.clear'.tr,
                onPressed: _clearSearch,
                icon: const Icon(Icons.clear),
              ),
      ),
      onChanged: _updateSearch,
    );
    final matchControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            counter,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'settings.previousMatch'.tr,
          onPressed: _matches.isEmpty ? null : _previousMatch,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'settings.nextMatch'.tr,
          onPressed: _matches.isEmpty ? null : _nextMatch,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: matchControls,
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                matchControls,
              ],
            ),
          );
        },
      ),
    );
  }

  SelectableText _buildLogText(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ) ??
        const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35);
    if (_matches.isEmpty) {
      return SelectableText(widget.content, style: style);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      if (match.start > cursor) {
        spans
            .add(TextSpan(text: widget.content.substring(cursor, match.start)));
      }
      final active = i == _activeMatch;
      spans.add(
        TextSpan(
          text: widget.content.substring(match.start, match.end),
          style: TextStyle(
            color: active
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onTertiaryContainer,
            backgroundColor: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.tertiaryContainer,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.content.length) {
      spans.add(TextSpan(text: widget.content.substring(cursor)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: 'settings.copyLog'.tr,
            onPressed: _copy,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'settings.downloadLog'.tr,
            onPressed: widget.content.isEmpty ? null : _download,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: widget.content.isEmpty
          ? Center(child: Text('settings.emptyLog'.tr))
          : Column(
              children: [
                _buildSearchBar(),
                const Divider(height: 1),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      child: _buildLogText(context),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
