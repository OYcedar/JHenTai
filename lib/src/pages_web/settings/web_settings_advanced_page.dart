import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:js_interop';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:web/web.dart' as web;

class WebSettingsAdvancedPage extends StatefulWidget {
  const WebSettingsAdvancedPage({super.key});

  @override
  State<WebSettingsAdvancedPage> createState() =>
      _WebSettingsAdvancedPageState();
}

class _WebSettingsAdvancedPageState extends State<WebSettingsAdvancedPage> {
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
      final data = await backendApiClient.exportUserData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now().toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName = 'jhentai-web-export-${now.year}${two(now.month)}'
          '${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      _downloadTextFile(fileName, json, mimeType: 'application/json');
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
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings.importDataTitle'.tr),
        content: Text('settings.importDataConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('settings.importData'.tr),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }

    try {
      final text = await _pickJsonFileText();
      if (text == null) {
        return;
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map && decoded is! List) {
        throw const FormatException('JSON root must be an object or list');
      }
      setState(() => importingData = true);
      final result = await backendApiClient.importUserData(decoded as Object);
      final imported = result['imported'] is Map
          ? Map<String, dynamic>.from(result['imported'] as Map)
          : const <String, dynamic>{};
      final count = imported.values.fold<int>(
        0,
        (sum, value) => sum + ((value as num?)?.toInt() ?? 0),
      );
      await controller.refreshStatus();
      Get.snackbar(
        'common.success'.tr,
        'settings.importDataSuccess'.trParams({'count': '$count'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
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
                    leading: const Icon(Icons.upload_file_outlined),
                    title: Text('settings.importData'.tr),
                    subtitle: Text('settings.importDataHint'.tr),
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
}

Future<String?> _pickJsonFileText() async {
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
    return completer.future;
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

class _WebLogPage extends StatelessWidget {
  const _WebLogPage({required this.name, required this.content});

  final String name;
  final String content;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: content));
    Get.snackbar(
      'common.success'.tr,
      'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _download() {
    if (content.isEmpty) {
      return;
    }
    _downloadTextFile(name, content);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: 'settings.copyLog'.tr,
            onPressed: _copy,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'settings.downloadLog'.tr,
            onPressed: content.isEmpty ? null : _download,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: content.isEmpty
          ? Center(child: Text('settings.emptyLog'.tr))
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ),
    );
  }
}
