import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebSettingsCloudSyncPage extends StatefulWidget {
  const WebSettingsCloudSyncPage({super.key});

  @override
  State<WebSettingsCloudSyncPage> createState() =>
      _WebSettingsCloudSyncPageState();
}

class _WebSettingsCloudSyncPageState extends State<WebSettingsCloudSyncPage>
    with WebScrollToTopState<WebSettingsCloudSyncPage> {
  final shareCodeController = TextEditingController();
  final configs = <Map<String, dynamic>>[];
  bool loading = false;
  bool uploading = false;
  bool serviceAlive = false;
  String? error;
  int? typeFilter;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    shareCodeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    resetScrollToTopState();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final alive = await backendApiClient.checkCloudConfigService();
      serviceAlive = alive['code'] == 0 || alive['success'] == true;
      final list = await backendApiClient.listCloudConfigs(type: typeFilter);
      configs
        ..clear()
        ..addAll(list);
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _fetchShareCode() async {
    final code = shareCodeController.text.trim();
    if (code.isEmpty) {
      return;
    }
    resetScrollToTopState();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final config = await backendApiClient.getCloudConfigByShareCode(code);
      configs
        ..clear()
        ..addAll(config == null ? [] : [config]);
      if (config == null) {
        Get.snackbar(
          'common.error'.tr,
          'settings.cloudConfigNotFound'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _importConfig(Map<String, dynamic> config) async {
    try {
      final result = await backendApiClient.importUserData([config]);
      final imported = result['imported'] is Map
          ? Map<String, dynamic>.from(result['imported'] as Map)
          : const <String, dynamic>{};
      final count = imported.values.fold<int>(
        0,
        (sum, value) => sum + ((value as num?)?.toInt() ?? 0),
      );
      if (Get.isRegistered<WebSettingsController>()) {
        await Get.find<WebSettingsController>().refreshStatus();
      }
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
    }
  }

  Future<void> _deleteConfig(Map<String, dynamic> config) async {
    final id = (config['id'] as num?)?.toInt();
    if (id == null || id < 0) {
      return;
    }
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings.deleteCloudConfigTitle'.tr),
        content: Text('settings.deleteCloudConfigConfirm'.tr),
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
      await backendApiClient.deleteCloudConfig(id);
      await _refresh();
      Get.snackbar(
        'common.success'.tr,
        'deleteSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.deleteCloudConfigFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _showUploadDialog() async {
    final selectedTypes = <int>{1, 2, 3, 4, 5};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('settings.uploadCloudConfigTitle'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('settings.uploadCloudConfigConfirm'.tr),
                const SizedBox(height: 12),
                for (final type in [1, 2, 3, 4, 5])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selectedTypes.contains(type),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(type);
                        } else {
                          selectedTypes.remove(type);
                        }
                      });
                    },
                    title: Text(_typeLabel(type)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed:
                  selectedTypes.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text('settings.uploadCloudConfig'.tr),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _uploadConfigs(selectedTypes.toList()..sort());
    }
  }

  Future<void> _uploadConfigs(List<int> types) async {
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      await backendApiClient.uploadCloudConfigs(types);
      await _refresh();
      Get.snackbar(
        'common.success'.tr,
        'settings.uploadCloudConfigSuccess'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.uploadCloudConfigFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => uploading = false);
      }
    }
  }

  void _downloadConfig(Map<String, dynamic> config) {
    final type = _typeLabel((config['type'] as num?)?.toInt());
    final version = config['version']?.toString() ?? '1.0.0';
    final shareCode = config['shareCode']?.toString() ?? 'local';
    final fileName = '$type-$version-$shareCode.json'
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    _downloadTextFile(
      fileName,
      config['config']?.toString() ?? '',
      mimeType: 'application/json',
    );
  }

  void _downloadTextFile(String fileName, String text,
      {required String mimeType}) {
    final bytes = utf8.encode(text);
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
    );
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

  String _typeLabel(int? type) {
    switch (type) {
      case 1:
        return 'readIndexRecord'.tr;
      case 2:
        return 'quickSearch'.tr;
      case 3:
        return 'blockingRules'.tr;
      case 4:
        return 'searchHistory'.tr;
      case 5:
        return 'galleryHistory'.tr;
      default:
        return 'settings.cloudConfigUnknownType'.tr;
    }
  }

  String _formatTime(Object? raw) {
    DateTime? time;
    if (raw is num) {
      time = DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true)
          .toLocal();
    } else if (raw is String) {
      time = DateTime.tryParse(raw)?.toLocal();
    }
    if (time == null) {
      return '';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.cloudSync'.tr),
        actions: [
          IconButton(
            tooltip: 'reload'.tr,
            onPressed: loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                serviceAlive ? Icons.cloud_done : Icons.cloud_off,
                color: serviceAlive ? Colors.green : null,
              ),
              title: Text('serverCondition'.tr),
              subtitle: Text(serviceAlive
                  ? 'settings.cloudServiceAvailable'.tr
                  : 'settings.cloudServiceUnavailable'.tr),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: shareCodeController,
                    decoration: InputDecoration(
                      labelText: 'settings.cloudShareCode'.tr,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'search'.tr,
                        onPressed: loading ? null : _fetchShareCode,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) => _fetchShareCode(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: typeFilter,
                    decoration: InputDecoration(
                      labelText: 'settings.cloudConfigType'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('all'.tr),
                      ),
                      for (final type in [1, 2, 3, 4, 5])
                        DropdownMenuItem<int?>(
                          value: type,
                          child: Text(_typeLabel(type)),
                        ),
                    ],
                    onChanged: (value) {
                      typeFilter = value;
                      _refresh();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('common.error'.tr),
                subtitle: Text(error!),
              ),
            )
          else if (configs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text('settings.cloudConfigEmpty'.tr)),
              ),
            )
          else
            ...configs.map(_buildConfigTile),
        ],
      ),
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  Widget? _buildFloatingActionButtons() {
    final canUpload = serviceAlive;
    if (!shouldShowScrollToTop && !canUpload) {
      return null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shouldShowScrollToTop) ...[
          buildWebScrollToTopFab(
            visible: true,
            heroTag: 'cloudSyncScrollToTop',
            onPressed: scrollToTop,
          ),
          if (canUpload) const SizedBox(height: 12),
        ],
        if (canUpload)
          FloatingActionButton(
            heroTag: 'cloudSyncUpload',
            tooltip: 'settings.uploadCloudConfig'.tr,
            onPressed: loading || uploading ? null : _showUploadDialog,
            child: uploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
      ],
    );
  }

  Widget _buildConfigTile(Map<String, dynamic> config) {
    final shareCode = config['shareCode']?.toString() ?? '';
    final id = (config['id'] as num?)?.toInt() ?? -1;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_queue),
        title: Text(_typeLabel((config['type'] as num?)?.toInt())),
        subtitle: Text([
          if (shareCode.isNotEmpty) shareCode,
          if (config['version'] != null) 'v${config['version']}',
          _formatTime(config['ctime']),
        ].where((value) => value.isNotEmpty).join('\n')),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'copyShareCode'.tr,
              onPressed: shareCode.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: shareCode));
                      Get.snackbar(
                        'common.success'.tr,
                        'hasCopiedToClipboard'.tr,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: 'download'.tr,
              onPressed: () => _downloadConfig(config),
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: 'import'.tr,
              onPressed: () => _importConfig(config),
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton(
              tooltip: 'delete'.tr,
              onPressed: id < 0 ? null : () => _deleteConfig(config),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
