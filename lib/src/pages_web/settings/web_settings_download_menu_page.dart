import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
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
  static const _archiveGroupKey = 'jh_web_default_archive_group';
  static const _archivePriorityKey = 'jh_web_default_archive_priority';

  final WebSettingsController controller = Get.find<WebSettingsController>();
  final galleryGroupController = TextEditingController();
  final galleryPriorityController = TextEditingController();
  final archiveGroupController = TextEditingController();
  final archivePriorityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    galleryGroupController.text = _readStorage(_galleryGroupKey, 'default');
    galleryPriorityController.text = _readStorage(_galleryPriorityKey, '0');
    archiveGroupController.text = _readStorage(_archiveGroupKey, 'default');
    archivePriorityController.text = _readStorage(_archivePriorityKey, '0');
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
    galleryGroupController.text = 'default';
    galleryPriorityController.text = '0';
    archiveGroupController.text = 'default';
    archivePriorityController.text = '0';
    _saveDefaults();
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
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
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
