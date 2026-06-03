import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scan_roots_dialog.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebSettingsDownloadMenuPage extends StatefulWidget {
  const WebSettingsDownloadMenuPage({super.key});

  @override
  State<WebSettingsDownloadMenuPage> createState() =>
      _WebSettingsDownloadMenuPageState();
}

class _WebSettingsDownloadMenuPageState
    extends State<WebSettingsDownloadMenuPage>
    with WebScrollToTopState<WebSettingsDownloadMenuPage> {
  static const _galleryGroupKey = 'jh_web_default_gallery_group';
  static const _galleryPriorityKey = 'jh_web_default_gallery_priority';
  static const _galleryOriginalKey = 'jh_web_default_gallery_original';
  static const _archiveGroupKey = 'jh_web_default_archive_group';
  static const _archivePriorityKey = 'jh_web_default_archive_priority';
  static const _archiveParseSourceKey = 'jh_web_default_archive_parse_source';

  final WebSettingsController controller = Get.find<WebSettingsController>();
  final galleryGroupController = TextEditingController();
  final galleryPriorityController = TextEditingController();
  bool galleryDownloadOriginalImage = false;
  final archiveGroupController = TextEditingController();
  final archivePriorityController = TextEditingController();
  bool restoreTasksAutomatically = false;
  bool isLoadingRestoreTasksAutomatically = true;
  String restoreTasksAutomaticallyError = '';
  bool restoreRunning = false;
  int speedLimitMaximum = 99;
  int speedLimitPeriodSeconds = 1;
  bool isLoadingSpeedLimit = true;
  String speedLimitError = '';
  int galleryConcurrency = 3;
  int archiveConcurrency = 2;
  bool downloadAllGalleriesOfSamePriority = false;
  bool galleryUpgradeReuseImages = true;
  bool deleteArchiveFileAfterDownload = true;
  bool isLoadingRuntimeSettings = true;
  String runtimeSettingsError = '';
  final archiveBotApiAddressController = TextEditingController();
  final archiveBotApiKeyController = TextEditingController();
  String archiveBotType = 'archiveAtHome';
  bool archiveBotApiKeyConfigured = false;
  bool isLoadingArchiveBot = true;
  bool archiveBotSaving = false;
  bool archiveBotActionRunning = false;
  String archiveBotError = '';
  String archiveBotResult = '';

  @override
  void initState() {
    super.initState();
    galleryGroupController.text =
        _displayGroupName(_readStorage(_galleryGroupKey, 'default'));
    galleryPriorityController.text = _readStorage(_galleryPriorityKey, '0');
    galleryDownloadOriginalImage =
        _readStorage(_galleryOriginalKey, 'false') == 'true';
    archiveGroupController.text =
        _displayGroupName(_readStorage(_archiveGroupKey, 'default'));
    archivePriorityController.text = _readStorage(_archivePriorityKey, '0');
    _loadRestoreTasksAutomatically();
    _loadSpeedLimit();
    _loadRuntimeSettings();
    _loadArchiveBotSettings();
  }

  @override
  void dispose() {
    galleryGroupController.dispose();
    galleryPriorityController.dispose();
    archiveGroupController.dispose();
    archivePriorityController.dispose();
    archiveBotApiAddressController.dispose();
    archiveBotApiKeyController.dispose();
    super.dispose();
  }

  String _readStorage(String key, String fallback) {
    final value = web.window.localStorage.getItem(key);
    return value == null || value.isEmpty ? fallback : value;
  }

  String _displayGroupName(String group) {
    return group == 'default' ? 'downloads.defaultGroup'.tr : group;
  }

  String _normalizeGroupName(String group) {
    final text = group.trim();
    if (text.isEmpty ||
        text == 'default' ||
        text == 'downloads.defaultGroup'.tr ||
        text == '默认' ||
        text == '預設') {
      return 'default';
    }
    return text;
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
      if (a == 'default') {
        return -1;
      }
      if (b == 'default') {
        return 1;
      }
      return a.compareTo(b);
    });
    return list;
  }

  Future<void> _loadRestoreTasksAutomatically() async {
    setState(() {
      isLoadingRestoreTasksAutomatically = true;
      restoreTasksAutomaticallyError = '';
    });
    try {
      final value = await backendApiClient.getRestoreTasksAutomatically();
      if (!mounted) {
        return;
      }
      setState(() => restoreTasksAutomatically = value);
    } catch (e) {
      if (mounted) {
        setState(
          () => restoreTasksAutomaticallyError =
              'settings.restoreTasksLoadFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingRestoreTasksAutomatically = false);
      }
    }
  }

  Future<void> _loadSpeedLimit() async {
    setState(() {
      isLoadingSpeedLimit = true;
      speedLimitError = '';
    });
    try {
      final value = await backendApiClient.getDownloadSpeedLimit();
      if (!mounted) {
        return;
      }
      setState(() {
        speedLimitMaximum = value.maximum;
        speedLimitPeriodSeconds = value.periodSeconds;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => speedLimitError =
              'settings.speedLimitLoadFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingSpeedLimit = false);
      }
    }
  }

  Future<void> _loadRuntimeSettings() async {
    setState(() {
      isLoadingRuntimeSettings = true;
      runtimeSettingsError = '';
    });
    try {
      final value = await backendApiClient.getDownloadRuntimeSettings();
      if (!mounted) {
        return;
      }
      setState(() {
        galleryConcurrency = value.galleryConcurrency;
        archiveConcurrency = value.archiveConcurrency;
        downloadAllGalleriesOfSamePriority =
            value.downloadAllGalleriesOfSamePriority;
        galleryUpgradeReuseImages = value.galleryUpgradeReuseImages;
        deleteArchiveFileAfterDownload = value.deleteArchiveFileAfterDownload;
      });
      await controller.refreshStatus();
    } catch (e) {
      if (mounted) {
        setState(
          () => runtimeSettingsError =
              'settings.runtimeLoadFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingRuntimeSettings = false);
      }
    }
  }

  Future<void> _loadArchiveBotSettings() async {
    setState(() {
      isLoadingArchiveBot = true;
      archiveBotError = '';
      archiveBotResult = '';
    });
    try {
      final settings = await backendApiClient.getArchiveBotSettings();
      if (!mounted) {
        return;
      }
      setState(() {
        archiveBotType = settings['type']?.toString() ?? 'archiveAtHome';
        archiveBotApiAddressController.text =
            settings['apiAddress']?.toString() ??
                _archiveBotDefaultAddress(archiveBotType);
        archiveBotApiKeyConfigured = settings['apiKeyConfigured'] == true;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => archiveBotError =
              'settings.archiveBotLoadFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingArchiveBot = false);
      }
    }
  }

  Future<void> _saveArchiveBotSettings() async {
    if (archiveBotSaving) {
      return;
    }
    setState(() {
      archiveBotSaving = true;
      archiveBotError = '';
      archiveBotResult = '';
    });
    try {
      final result = await backendApiClient.updateArchiveBotSettings(
        type: archiveBotType,
        apiAddress: archiveBotApiAddressController.text.trim(),
        apiKey: archiveBotApiKeyController.text.trim().isEmpty
            ? null
            : archiveBotApiKeyController.text.trim(),
      );
      final settings = result['settings'] is Map
          ? Map<String, dynamic>.from(result['settings'] as Map)
          : const <String, dynamic>{};
      if (!mounted) {
        return;
      }
      setState(() {
        archiveBotType = settings['type']?.toString() ?? archiveBotType;
        archiveBotApiAddressController.text =
            settings['apiAddress']?.toString() ??
                _archiveBotDefaultAddress(archiveBotType);
        archiveBotApiKeyConfigured = settings['apiKeyConfigured'] == true;
        archiveBotApiKeyController.clear();
        archiveBotResult = 'settings.archiveBotSaved'.tr;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => archiveBotError =
              'settings.archiveBotSaveFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => archiveBotSaving = false);
      }
    }
  }

  Future<void> _runArchiveBotAction(
    Future<Map<String, dynamic>> Function() run,
  ) async {
    if (archiveBotActionRunning) {
      return;
    }
    setState(() {
      archiveBotActionRunning = true;
      archiveBotError = '';
      archiveBotResult = '';
    });
    try {
      final result = await run();
      if (!mounted) {
        return;
      }
      final response = result['response'] is Map
          ? Map<String, dynamic>.from(result['response'] as Map)
          : const <String, dynamic>{};
      final message = response['message']?.toString() ??
          result['message']?.toString() ??
          (result['success'] == true ? 'OK' : '');
      final balance = result['balance'];
      setState(() {
        archiveBotResult = balance == null
            ? message
            : 'settings.archiveBotBalanceResult'
                .trParams({'balance': '$balance'});
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => archiveBotError =
              'settings.archiveBotActionFailed'.trParams({'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => archiveBotActionRunning = false);
      }
    }
  }

  Future<void> _saveRuntimeSettings({
    int? galleryConcurrency,
    int? archiveConcurrency,
    bool? downloadAllGalleriesOfSamePriority,
    bool? galleryUpgradeReuseImages,
    bool? deleteArchiveFileAfterDownload,
  }) async {
    final previousGalleryConcurrency = this.galleryConcurrency;
    final previousArchiveConcurrency = this.archiveConcurrency;
    final previousDownloadAllGalleriesOfSamePriority =
        this.downloadAllGalleriesOfSamePriority;
    final previousGalleryUpgradeReuseImages = this.galleryUpgradeReuseImages;
    final previousDeleteArchiveFileAfterDownload =
        this.deleteArchiveFileAfterDownload;
    setState(() {
      if (galleryConcurrency != null) {
        this.galleryConcurrency = galleryConcurrency;
      }
      if (archiveConcurrency != null) {
        this.archiveConcurrency = archiveConcurrency;
      }
      if (downloadAllGalleriesOfSamePriority != null) {
        this.downloadAllGalleriesOfSamePriority =
            downloadAllGalleriesOfSamePriority;
      }
      if (galleryUpgradeReuseImages != null) {
        this.galleryUpgradeReuseImages = galleryUpgradeReuseImages;
      }
      if (deleteArchiveFileAfterDownload != null) {
        this.deleteArchiveFileAfterDownload = deleteArchiveFileAfterDownload;
      }
    });
    try {
      await backendApiClient.setDownloadRuntimeSettings(
        galleryConcurrency: galleryConcurrency,
        archiveConcurrency: archiveConcurrency,
        downloadAllGalleriesOfSamePriority: downloadAllGalleriesOfSamePriority,
        galleryUpgradeReuseImages: galleryUpgradeReuseImages,
        deleteArchiveFileAfterDownload: deleteArchiveFileAfterDownload,
      );
      await controller.refreshStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          this.galleryConcurrency = previousGalleryConcurrency;
          this.archiveConcurrency = previousArchiveConcurrency;
          this.downloadAllGalleriesOfSamePriority =
              previousDownloadAllGalleriesOfSamePriority;
          this.galleryUpgradeReuseImages = previousGalleryUpgradeReuseImages;
          this.deleteArchiveFileAfterDownload =
              previousDeleteArchiveFileAfterDownload;
        });
      }
      Get.snackbar(
        'common.error'.tr,
        '${'common.failed'.tr}: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    }
  }

  Future<void> _saveSpeedLimit({
    int? maximum,
    int? periodSeconds,
  }) async {
    final nextMaximum = maximum ?? speedLimitMaximum;
    final nextPeriodSeconds = periodSeconds ?? speedLimitPeriodSeconds;
    setState(() {
      speedLimitMaximum = nextMaximum;
      speedLimitPeriodSeconds = nextPeriodSeconds;
    });
    try {
      await backendApiClient.setDownloadSpeedLimit(
        maximum: nextMaximum,
        periodSeconds: nextPeriodSeconds,
      );
    } catch (e) {
      await _loadSpeedLimit();
      Get.snackbar(
        'common.error'.tr,
        '${'common.failed'.tr}: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    }
  }

  void _saveDefaults() {
    final galleryGroup = _normalizeGroupName(galleryGroupController.text);
    final archiveGroup = _normalizeGroupName(archiveGroupController.text);
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

    galleryGroupController.text = _displayGroupName(galleryGroup);
    galleryPriorityController.text = '$galleryPriority';
    archiveGroupController.text = _displayGroupName(archiveGroup);
    archivePriorityController.text = '$archivePriority';
    Get.snackbar('common.success'.tr, 'settings.downloadDefaultsSaved'.tr,
        snackPosition: SnackPosition.BOTTOM);
  }

  void _resetDefaults() {
    setState(() {
      galleryGroupController.text = _displayGroupName('default');
      galleryPriorityController.text = '0';
      galleryDownloadOriginalImage = false;
      archiveGroupController.text = _displayGroupName('default');
      archivePriorityController.text = '0';
    });
    _saveDefaults();
  }

  Future<void> _restoreDownloadTasks() async {
    if (restoreRunning) {
      return;
    }
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
      if (mounted) {
        setState(() => restoreRunning = false);
      }
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
          controller: scrollController,
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
            _sectionTitle(context, 'speedLimit'.tr),
            const SizedBox(height: 8),
            _speedLimitCard(),
            const SizedBox(height: 24),
            _sectionTitle(context, 'settings.downloadServerRuntime'.tr),
            const SizedBox(height: 8),
            _runtimeCard(info),
            const SizedBox(height: 24),
            _sectionTitle(context, 'settings.archiveBotTitle'.tr),
            const SizedBox(height: 8),
            _archiveBotCard(context),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showWebScanRootsDialog(
                context,
                onChanged: controller.refreshStatus,
              ),
              icon: const Icon(Icons.folder_copy_outlined),
              label: Text('local.scanRoots'.tr),
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
              subtitle: _settingSubtitle(
                context,
                'restoreTasksAutomaticallyHint'.tr,
                restoreTasksAutomaticallyError,
                _loadRestoreTasksAutomatically,
              ),
              value: restoreTasksAutomatically,
              onChanged: isLoadingRestoreTasksAutomatically ||
                      restoreTasksAutomaticallyError.isNotEmpty
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
      floatingActionButton: buildScrollToTopFab(),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _readStorage(_archiveParseSourceKey, 'official'),
              decoration: InputDecoration(
                labelText: 'settings.archiveParseSource'.tr,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'official',
                  child: Text('settings.archiveParseOfficial'.tr),
                ),
                DropdownMenuItem(
                  value: 'bot',
                  child: Text('settings.archiveParseBot'.tr),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  web.window.localStorage
                      .setItem(_archiveParseSourceKey, value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedLimitCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.speedLimitWebHint'.tr,
                style: Theme.of(context).textTheme.bodySmall),
            if (speedLimitError.isNotEmpty) ...[
              const SizedBox(height: 12),
              _loadErrorBanner(context, speedLimitError, _loadSpeedLimit),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: speedLimitMaximum,
                    decoration: InputDecoration(
                      labelText: 'settings.speedLimitMaximum'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in [1, 2, 3, 5, 10, 99])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                              value == 99 ? 'settings.unlimited'.tr : '$value'),
                        ),
                    ],
                    onChanged: isLoadingSpeedLimit || speedLimitError.isNotEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              _saveSpeedLimit(maximum: value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: speedLimitPeriodSeconds,
                    decoration: InputDecoration(
                      labelText: 'settings.speedLimitPeriod'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in [1, 2, 3])
                        DropdownMenuItem(
                          value: value,
                          child: Text('${value}s'),
                        ),
                    ],
                    onChanged: isLoadingSpeedLimit || speedLimitError.isNotEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              _saveSpeedLimit(periodSeconds: value);
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _runtimeCard(Map<String, dynamic> info) {
    return Card(
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
            if (runtimeSettingsError.isNotEmpty) ...[
              const SizedBox(height: 12),
              _loadErrorBanner(
                context,
                runtimeSettingsError,
                _loadRuntimeSettings,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: galleryConcurrency,
                    decoration: InputDecoration(
                      labelText: 'settings.galleryConcurrency'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (var value = 1; value <= 16; value++)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: isLoadingRuntimeSettings ||
                            runtimeSettingsError.isNotEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              _saveRuntimeSettings(
                                galleryConcurrency: value,
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: archiveConcurrency,
                    decoration: InputDecoration(
                      labelText: 'settings.archiveConcurrency'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in [1, 2, 3, 4, 5, 6, 7, 8])
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: isLoadingRuntimeSettings ||
                            runtimeSettingsError.isNotEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              _saveRuntimeSettings(
                                archiveConcurrency: value,
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.stacked_line_chart_outlined),
              title: Text('downloadAllGallerysOfSamePriority'.tr),
              subtitle: Text('downloadAllGallerysOfSamePriorityHint'.tr),
              value: downloadAllGalleriesOfSamePriority,
              onChanged:
                  isLoadingRuntimeSettings || runtimeSettingsError.isNotEmpty
                      ? null
                      : (value) => _saveRuntimeSettings(
                            downloadAllGalleriesOfSamePriority: value,
                          ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.published_with_changes_outlined),
              title: Text('useJH2UpdateGallery'.tr),
              value: galleryUpgradeReuseImages,
              onChanged:
                  isLoadingRuntimeSettings || runtimeSettingsError.isNotEmpty
                      ? null
                      : (value) => _saveRuntimeSettings(
                            galleryUpgradeReuseImages: value,
                          ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.archive_outlined),
              title: Text('deleteArchiveFileAfterDownload'.tr),
              subtitle: Text('settings.deleteArchiveZipAfterDownloadHint'.tr),
              value: deleteArchiveFileAfterDownload,
              onChanged:
                  isLoadingRuntimeSettings || runtimeSettingsError.isNotEmpty
                      ? null
                      : (value) => _saveRuntimeSettings(
                            deleteArchiveFileAfterDownload: value,
                          ),
            ),
            const Divider(height: 24),
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
    );
  }

  Widget _archiveBotCard(BuildContext context) {
    final busy = isLoadingArchiveBot || archiveBotSaving;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.archiveBotHint'.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: archiveBotType,
              decoration: InputDecoration(
                labelText: 'settings.archiveBotProtocol'.tr,
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'archiveAtHome',
                  child: Text('Archive-at-Home'),
                ),
                DropdownMenuItem(
                  value: 'ehArBot',
                  child: Text('EH-ArBot'),
                ),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        archiveBotType = value;
                        archiveBotApiAddressController.text =
                            _archiveBotDefaultAddress(value);
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: archiveBotApiAddressController,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: 'settings.archiveBotApiAddress'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: archiveBotApiKeyController,
              enabled: !busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'settings.archiveBotApiKey'.tr,
                helperText: archiveBotApiKeyConfigured
                    ? 'settings.archiveBotApiKeyConfigured'.tr
                    : 'settings.archiveBotApiKeyNotConfigured'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            if (archiveBotError.isNotEmpty) ...[
              const SizedBox(height: 12),
              _loadErrorBanner(
                  context, archiveBotError, _loadArchiveBotSettings),
            ],
            if (archiveBotResult.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(archiveBotResult)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : _saveArchiveBotSettings,
                  icon: archiveBotSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text('common.save'.tr),
                ),
                OutlinedButton.icon(
                  onPressed: archiveBotActionRunning
                      ? null
                      : () => _runArchiveBotAction(
                          backendApiClient.requestArchiveBotBalance),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text('settings.archiveBotTestBalance'.tr),
                ),
                OutlinedButton.icon(
                  onPressed: archiveBotActionRunning
                      ? null
                      : () => _runArchiveBotAction(
                          backendApiClient.requestArchiveBotCheckIn),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: Text('settings.archiveBotCheckIn'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _archiveBotDefaultAddress(String type) {
    return type == 'ehArBot'
        ? 'https://eh-arc-api.mhdy.icu'
        : 'https://api.archive-at-home.org';
  }

  Widget _settingSubtitle(
    BuildContext context,
    String text,
    String error,
    VoidCallback onRetry,
  ) {
    if (error.isEmpty) {
      return Text(text);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        const SizedBox(height: 8),
        _loadErrorBanner(context, error, onRetry),
      ],
    );
  }

  Widget _loadErrorBanner(
    BuildContext context,
    String error,
    VoidCallback onRetry,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('common.retry'.tr),
          ),
        ],
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
    final normalizedGroup = _normalizeGroupName(groupController.text);
    final selectedGroup =
        groups.contains(normalizedGroup) ? normalizedGroup : null;
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
                initialValue: selectedGroup,
                decoration: InputDecoration(
                  labelText: 'downloads.groupLabel'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final group in groups)
                    DropdownMenuItem(
                      value: group,
                      child: Text(
                        _displayGroupName(group),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    groupController.text = _displayGroupName(value);
                  }
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
