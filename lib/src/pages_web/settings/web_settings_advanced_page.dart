import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

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

  @override
  void initState() {
    super.initState();
    _loadLogs();
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
    if (ok != true) return;
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

  Future<void> _openLog(Map<String, dynamic> item) async {
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty) return;
    try {
      final content = await backendApiClient.readServerLog(name);
      if (!mounted) return;
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
                    'settings.loadLogsFailed'.trParams({'error': logsError!}),
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
                      if (i != logs.length - 1) const Divider(height: 1),
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
    if (date == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
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
