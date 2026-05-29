import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:web/web.dart' as web;

class WebSettingsDownloadMenuPage extends StatefulWidget {
  const WebSettingsDownloadMenuPage({super.key});

  @override
  State<WebSettingsDownloadMenuPage> createState() =>
      _WebSettingsDownloadMenuPageState();
}

class _WebSettingsDownloadMenuPageState
    extends State<WebSettingsDownloadMenuPage> {
  static const _galleryGroupKey = 'jh_web_default_gallery_group';
  static const _galleryPriorityKey = 'jh_web_default_gallery_priority';
  static const _galleryOriginalKey = 'jh_web_default_gallery_original';
  static const _archiveGroupKey = 'jh_web_default_archive_group';
  static const _archivePriorityKey = 'jh_web_default_archive_priority';

  final WebSettingsController controller = Get.find<WebSettingsController>();
  final galleryGroupController = TextEditingController();
  final galleryPriorityController = TextEditingController();
  bool galleryDownloadOriginalImage = false;
  final archiveGroupController = TextEditingController();
  final archivePriorityController = TextEditingController();
  bool restoreTasksAutomatically = false;
  bool isLoadingRestoreTasksAutomatically = true;
  bool restoreRunning = false;

  @override
  void initState() {
    super.initState();
    galleryGroupController.text = _readStorage(_galleryGroupKey, 'default');
    galleryPriorityController.text = _readStorage(_galleryPriorityKey, '0');
    galleryDownloadOriginalImage =
        _readStorage(_galleryOriginalKey, 'false') == 'true';
    archiveGroupController.text = _readStorage(_archiveGroupKey, 'default');
    archivePriorityController.text = _readStorage(_archivePriorityKey, '0');
    _loadRestoreTasksAutomatically();
  }

  @override
  void dispose() {
    galleryGroupController.dispose();
    galleryPriorityController.dispose();
    archiveGroupController.dispose();
    archivePriorityController.dispose();
    super.dispose();
  }

  String _readStorage(String key, String fallback) {
    final value = web.window.localStorage.getItem(key);
    return value == null || value.isEmpty ? fallback : value;
  }

  List<String> _groupCandidates() {
    final set = <String>{'default'};
    if (Get.isRegistered<WebDownloadService>()) {
      final svc = Get.find<WebDownloadService>();
      for (final t in svc.galleryTasks.values) {
        set.add((t['group_name'] ?? t['groupName'] ?? 'default').toString());
      }
      for (final t in svc.archiveTasks.values) {
        set.add((t['group_name'] ?? t['groupName'] ?? 'default').toString());
      }
    }
    final list = set.where((e) => e.trim().isNotEmpty).toList();
    list.sort((a, b) {
      if (a == 'default') return -1;
      if (b == 'default') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  Future<void> _loadRestoreTasksAutomatically() async {
    try {
      final value = await backendApiClient.getRestoreTasksAutomatically();
      if (!mounted) {
        return;
      }
      setState(() => restoreTasksAutomatically = value);
    } catch (_) {
      // Keep the server default: disabled.
    } finally {
      if (mounted) {
        setState(() => isLoadingRestoreTasksAutomatically = false);
      }
    }
  }

  void _saveDefaults() {
    final galleryGroup = galleryGroupController.text.trim().isEmpty
        ? 'default'
        : galleryGroupController.text.trim();
    final archiveGroup = archiveGroupController.text.trim().isEmpty
        ? 'default'
        : archiveGroupController.text.trim();
    final galleryPriority =
        int.tryParse(galleryPriorityController.text.trim()) ?? 0;
    final archivePriority =
        int.tryParse(archivePriorityController.text.trim()) ?? 0;

    web.window.localStorage.setItem(_galleryGroupKey, galleryGroup);
    web.window.localStorage.setItem(_galleryPriorityKey, '$galleryPriority');
    web.window.localStorage.setItem(
        _galleryOriginalKey, galleryDownloadOriginalImage ? 'true' : 'false');
    web.window.localStorage.setItem(_archiveGroupKey, archiveGroup);
    web.window.localStorage.setItem(_archivePriorityKey, '$archivePriority');

    galleryGroupController.text = galleryGroup;
    galleryPriorityController.text = '$galleryPriority';
    archiveGroupController.text = archiveGroup;
    archivePriorityController.text = '$archivePriority';
    Get.snackbar('common.success'.tr, 'settings.downloadDefaultsSaved'.tr,
        snackPosition: SnackPosition.BOTTOM);
  }

  void _resetDefaults() {
    setState(() {
      galleryGroupController.text = 'default';
      galleryPriorityController.text = '0';
      galleryDownloadOriginalImage = false;
      archiveGroupController.text = 'default';
      archivePriorityController.text = '0';
    });
    _saveDefaults();
  }

  Future<void> _restoreDownloadTasks() async {
    if (restoreRunning) return;
    setState(() => restoreRunning = true);
    try {
      final results = await Future.wait([
        backendApiClient.restoreGalleryDownloads(),
        backendApiClient.restoreArchiveDownloads(),
      ]);
      await Get.find<WebDownloadService>().refresh();
      final galleryCount =
          (results[0]['restoredGalleryCount'] as num?)?.toInt() ?? 0;
      final archiveCount =
          (results[1]['restoredArchiveCount'] as num?)?.toInt() ?? 0;
      Get.snackbar(
        'common.success'.tr,
        '${'restoredGalleryCount'.tr}: $galleryCount\n${'restoredArchiveCount'.tr}: $archiveCount',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    } finally {
      if (mounted) setState(() => restoreRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupCandidates();
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menuDownload'.tr),
        actions: [
          IconButton(
            tooltip: 'common.reset'.tr,
            onPressed: _resetDefaults,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Obx(() {
        final info = controller.serverInfo;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('settings.downloadWebIntro'.tr,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            _sectionTitle(context, 'settings.downloadDefaults'.tr),
            const SizedBox(height: 8),
            _defaultsCard(context, groups),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saveDefaults,
              icon: const Icon(Icons.save_outlined),
              label: Text('common.save'.tr),
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'settings.downloadServerRuntime'.tr),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('settings.downloadDir'.tr,
                        info['downloadDir']?.toString() ?? '-'),
                    _infoRow('settings.localGalleryDir'.tr,
                        info['localGalleryDir']?.toString() ?? '-'),
                    if (info['extraScanPaths'] is List &&
                        (info['extraScanPaths'] as List).isNotEmpty)
                      _infoRow('settings.extraScanPaths'.tr,
                          (info['extraScanPaths'] as List).join(', ')),
                    _infoRow(
                      'settings.galleryConcurrency'.tr,
                      '${info['maxConcurrentGalleryDownloads'] ?? '-'}',
                    ),
                    _infoRow(
                      'settings.archiveConcurrency'.tr,
                      '${info['maxConcurrentArchiveDownloads'] ?? '-'}',
                    ),
                    _infoRow(
                      'downloadAllGallerysOfSamePriority'.tr,
                      _enabledLabel(info['downloadAllGalleriesOfSamePriority']),
                    ),
                    _infoRow(
                      'useJH2UpdateGallery'.tr,
                      _enabledLabel(info['galleryUpgradeReuseImages']),
                    ),
                    _infoRow(
                      'settings.jhPublicApiBaseUrl'.tr,
                      info['jhPublicApiBaseUrl']?.toString() ?? '-',
                    ),
                    _infoRow(
                      'settings.jhAppId'.tr,
                      info['jhAppId']?.toString() ?? '-',
                    ),
                    _infoRow(
                      'settings.jhApiSecretConfigured'.tr,
                      info['jhApiSecretConfigured'] == true
                          ? 'settings.configured'.tr
                          : 'settings.notConfigured'.tr,
                    ),
                    const SizedBox(height: 8),
                    Text('settings.downloadRuntimeHint'.tr,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Get.toNamed('/web/downloads'),
              icon: const Icon(Icons.download_outlined),
              label: Text('settings.openDownloads'.tr),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: restoreRunning ? null : _restoreDownloadTasks,
              icon: restoreRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_outlined),
              label: Text('restoreDownloadTasks'.tr),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.settings_backup_restore_outlined),
              title: Text('restoreTasksAutomatically'.tr),
              subtitle: Text('restoreTasksAutomaticallyHint'.tr),
              value: restoreTasksAutomatically,
              onChanged: isLoadingRestoreTasksAutomatically
                  ? null
                  : (value) async {
                      setState(() => restoreTasksAutomatically = value);
                      try {
                        await backendApiClient
                            .setRestoreTasksAutomatically(value);
                      } catch (e) {
                        if (!mounted) {
                          return;
                        }
                        setState(() => restoreTasksAutomatically = !value);
                        Get.snackbar(
                          'common.error'.tr,
                          '${'common.failed'.tr}: $e',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.red.withValues(alpha: 0.7),
                        );
                      }
                    },
            ),
          ],
        );
      }),
    );
  }

  Widget _defaultsCard(BuildContext context, List<String> groups) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _downloadDefaultEditor(
              context: context,
              title: 'settings.defaultGalleryDownload'.tr,
              groupController: galleryGroupController,
              priorityController: galleryPriorityController,
              groups: groups,
              downloadOriginalImage: galleryDownloadOriginalImage,
              onDownloadOriginalImageChanged: (value) {
                setState(() => galleryDownloadOriginalImage = value);
              },
            ),
            const Divider(height: 32),
            _downloadDefaultEditor(
              context: context,
              title: 'settings.defaultArchiveDownload'.tr,
              groupController: archiveGroupController,
              priorityController: archivePriorityController,
              groups: groups,
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadDefaultEditor({
    required BuildContext context,
    required String title,
    required TextEditingController groupController,
    required TextEditingController priorityController,
    required List<String> groups,
    bool? downloadOriginalImage,
    ValueChanged<bool>? onDownloadOriginalImageChanged,
  }) {
    final selectedGroup =
        groups.contains(groupController.text) ? groupController.text : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: selectedGroup,
                decoration: InputDecoration(
                  labelText: 'downloads.groupLabel'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final group in groups)
                    DropdownMenuItem(
                      value: group,
                      child: Text(group, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) groupController.text = value;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: priorityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'downloads.setPriority'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: groupController,
          decoration: InputDecoration(
            labelText: 'settings.customGroupName'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        if (downloadOriginalImage != null &&
            onDownloadOriginalImageChanged != null) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: downloadOriginalImage,
            onChanged: (value) =>
                onDownloadOriginalImageChanged(value ?? false),
            title: Text('downloadOriginalImageByDefault'.tr),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  String _enabledLabel(dynamic value) {
    return value == true ? 'settings.enabled'.tr : 'settings.disabled'.tr;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 170,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(
              child: Text(value, style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}
