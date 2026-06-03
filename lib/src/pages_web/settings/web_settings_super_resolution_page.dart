import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsSuperResolutionPage extends StatefulWidget {
  const WebSettingsSuperResolutionPage({super.key});

  @override
  State<WebSettingsSuperResolutionPage> createState() =>
      _WebSettingsSuperResolutionPageState();
}

class _WebSettingsSuperResolutionPageState
    extends State<WebSettingsSuperResolutionPage>
    with WebScrollToTopState<WebSettingsSuperResolutionPage> {
  Map<String, dynamic> capabilities = {};
  Map<String, dynamic> autoSettings = {};
  List<Map<String, dynamic>> models = [];
  bool loading = true;
  bool downloading = false;
  bool importing = false;
  bool savingSettings = false;
  String? error;
  Timer? _modelPollTimer;
  final TextEditingController _gpuIdController = TextEditingController();

  WebDownloadService get _downloads => Get.find<WebDownloadService>();

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
      final caps = await backendApiClient.getSuperResolutionCapabilities();
      final settings = await backendApiClient.getSuperResolutionSettings();
      final modelList = await backendApiClient.listSuperResolutionModels();
      await _downloads.refresh();
      if (!mounted) {
        return;
      }
      setState(() {
        capabilities = caps;
        autoSettings = settings;
        models = modelList;
        _gpuIdController.text = settings['gpuId']?.toString() ?? '';
      });
      _syncModelPolling();
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

  @override
  void dispose() {
    _modelPollTimer?.cancel();
    _gpuIdController.dispose();
    super.dispose();
  }

  Future<void> _downloadModel(String model) async {
    setState(() => downloading = true);
    try {
      await backendApiClient.downloadSuperResolutionModel(model);
      await _refreshModels();
      Get.snackbar(
          'common.success'.tr, 'superResolution.modelDownloadStarted'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  Future<void> _importModel(String model) async {
    setState(() => importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        return;
      }
      await backendApiClient.importSuperResolutionModel(
        model: model,
        bytes: bytes,
        fileName: file.name,
      );
      await _load();
      Get.snackbar('common.success'.tr, 'superResolution.modelReady'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() => importing = false);
      }
    }
  }

  Future<void> _repairModelPermission(String model) async {
    try {
      await backendApiClient.repairSuperResolutionModelPermission(model);
      await _load();
      Get.snackbar(
          'common.success'.tr, 'superResolution.modelPermissionRepaired'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _refreshModels() async {
    try {
      final modelList = await backendApiClient.listSuperResolutionModels();
      if (!mounted) {
        return;
      }
      setState(() {
        models = modelList;
        downloading = _hasActiveModelOperation(modelList);
      });
      _syncModelPolling();
    } catch (_) {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  void _syncModelPolling() {
    final active = _hasActiveModelOperation(models);
    if (!active) {
      _modelPollTimer?.cancel();
      _modelPollTimer = null;
      return;
    }
    _modelPollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshModels(),
    );
  }

  bool _hasActiveModelOperation(List<Map<String, dynamic>> modelList) {
    return modelList.any((model) {
      final state = _map(model['downloadState']);
      final status = state['status']?.toString();
      return status == 'downloading' || status == 'importing';
    });
  }

  Future<void> _saveAutoSettings() async {
    setState(() => savingSettings = true);
    try {
      final result = await backendApiClient.updateSuperResolutionSettings({
        'autoEnabled': autoSettings['autoEnabled'] == true,
        'model': autoSettings['model']?.toString() ?? 'realcugan',
        'gpuId': int.tryParse(_gpuIdController.text.trim()),
        'tileSize': (autoSettings['tileSize'] as num?)?.toInt() ?? 0,
        'allowCpuOnly': autoSettings['allowCpuOnly'] == true,
      });
      if (mounted) {
        setState(() {
          autoSettings =
              Map<String, dynamic>.from(result['settings'] as Map? ?? {});
          _gpuIdController.text = autoSettings['gpuId']?.toString() ?? '';
        });
      }
      Get.snackbar('common.success'.tr, 'superResolution.autoSettingsSaved'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() => savingSettings = false);
      }
    }
  }

  Future<void> _pause(String id) async {
    await backendApiClient.pauseSuperResolutionJob(id);
    await _downloads.refresh();
  }

  Future<void> _resume(String id) async {
    await backendApiClient.resumeSuperResolutionJob(id);
    await _downloads.refresh();
  }

  Future<void> _delete(String id) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('common.delete'.tr),
        content: Text('superResolution.deleteHint'.tr),
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
    await backendApiClient.deleteSuperResolutionJob(id, deleteFiles: true);
    await _downloads.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('superResolution.title'.tr),
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
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _capabilityCard(context),
                      const SizedBox(height: 12),
                      _modelCard(context),
                      const SizedBox(height: 12),
                      _autoCard(context),
                      const SizedBox(height: 12),
                      _jobsCard(context),
                    ],
                  ),
                ),
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
            Text(error!, textAlign: TextAlign.center),
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

  Widget _capabilityCard(BuildContext context) {
    final status = capabilities['status']?.toString() ?? 'warn';
    final gpu = _map(capabilities['gpu']);
    final runtime = _map(capabilities['runtime']);
    final warnings = ((capabilities['warnings'] as List?) ?? const [])
        .map((e) => _localizedCapabilityWarning(e.toString()))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              Icons.health_and_safety_outlined,
              'superResolution.capability'.tr,
              status == 'ok'
                  ? 'settings.diagnosticsStatusOk'.tr
                  : 'settings.diagnosticsStatusWarn'.tr,
            ),
            const SizedBox(height: 12),
            _row('superResolution.arch'.tr, runtime['arch']?.toString() ?? '-'),
            _row('superResolution.gpu'.tr,
                gpu['available'] == true ? 'common.yes'.tr : 'common.no'.tr),
            _row('/dev/dri',
                gpu['hasDevDri'] == true ? 'common.yes'.tr : 'common.no'.tr),
            _row(
                'NVIDIA',
                gpu['nvidiaVisible'] == true
                    ? 'common.visible'.tr
                    : 'common.notVisible'.tr),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'superResolution.safetyHint'.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelCard(BuildContext context) {
    final grouped = _groupedModelOptions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              Icons.auto_fix_high_outlined,
              'superResolution.models'.tr,
              '',
            ),
            const SizedBox(height: 8),
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  entry.key.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final model in entry.value) _modelTile(context, model),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modelTile(BuildContext context, Map<String, dynamic> model) {
    final id = model['id']?.toString() ?? 'realcugan';
    final state = _map(model['downloadState']);
    final status = state['status']?.toString() ??
        (model['installed'] == true ? 'installed' : 'idle');
    final progress = (state['progress'] as num?)?.toDouble() ?? 0;
    final active = status == 'downloading' || status == 'importing';
    final failed = status == 'failed';
    final installed = model['installed'] == true;
    final executable = model['executable'] == true;
    final received = (state['receivedBytes'] as num?)?.toInt() ?? 0;
    final total = (state['totalBytes'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(model['label']?.toString() ?? id),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_modelStatusLabel(model, state)),
            if ((model['downloadSource']?.toString() ?? '').isNotEmpty)
              Text(
                'superResolution.modelSource'.trParams({
                  'source': model['downloadSource'].toString(),
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (active && total > 0)
              Text(
                '${_formatBytes(received)} / ${_formatBytes(total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (active) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
            ],
            if (installed && !executable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'superResolution.installedNotExecutable'.tr,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (failed && (state['error']?.toString().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state['error'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (installed && !executable)
              OutlinedButton.icon(
                onPressed: active || importing || downloading
                    ? null
                    : () => _repairModelPermission(id),
                icon: const Icon(Icons.build_outlined),
                label: Text('superResolution.repairPermission'.tr),
              ),
            OutlinedButton.icon(
              onPressed: active || importing ? null : () => _importModel(id),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text('superResolution.importModel'.tr),
            ),
            FilledButton.icon(
              onPressed:
                  active || downloading ? null : () => _downloadModel(id),
              icon: active
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(failed
                  ? 'common.retry'.tr
                  : model['installed'] == true
                      ? 'common.update'.tr
                      : 'common.download'.tr),
            ),
          ],
        ),
      ),
    );
  }

  String _modelStatusLabel(
    Map<String, dynamic> model,
    Map<String, dynamic> state,
  ) {
    final status = state['status']?.toString() ??
        (model['installed'] == true ? 'installed' : 'idle');
    final progress = ((state['progress'] as num?)?.toDouble() ?? 0) * 100;
    return switch (status) {
      'downloading' => 'superResolution.modelDownloading'
          .trParams({'progress': progress.toStringAsFixed(0)}),
      'importing' => 'superResolution.modelImporting'.tr,
      'failed' => 'superResolution.modelDownloadFailed'.tr,
      'installed' => model['executable'] == true
          ? 'superResolution.installed'.tr
          : 'superResolution.installedNotExecutable'.tr,
      _ => model['installed'] == true
          ? 'superResolution.installed'.tr
          : 'superResolution.notInstalled'.tr,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GiB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '$bytes B';
  }

  Widget _autoCard(BuildContext context) {
    final model = autoSettings['model']?.toString() ?? 'realcugan';
    final tileSize = (autoSettings['tileSize'] as num?)?.toInt() ?? 0;
    final gpu = _map(capabilities['gpu']);
    final gpuAvailable = gpu['available'] == true;
    final selectedModelInstalled = models
        .where((item) => item['id'] == model)
        .any((item) => item['installed'] == true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              Icons.download_done_outlined,
              'superResolution.autoAfterDownload'.tr,
              autoSettings['autoEnabled'] == true
                  ? 'settings.enabled'.tr
                  : 'settings.disabled'.tr,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('superResolution.autoEnabled'.tr),
              subtitle: Text('superResolution.autoEnabledHint'.tr),
              value: autoSettings['autoEnabled'] == true,
              onChanged: (value) {
                setState(() => autoSettings['autoEnabled'] = value);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('auto-model-$model-${models.length}'),
              initialValue: _modelOptions.any((item) => item['id'] == model)
                  ? model
                  : 'realcugan',
              decoration: InputDecoration(
                labelText: 'superResolution.model'.tr,
              ),
              items: [
                for (final item in _modelOptions)
                  DropdownMenuItem(
                    value: item['id'].toString(),
                    child: Text(
                      '${item['label']} · ${item['installed'] == true ? 'superResolution.installed'.tr : 'superResolution.notInstalled'.tr}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => autoSettings['model'] = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              'superResolution.autoAfterDownloadHint'.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('auto-tile-$tileSize'),
              initialValue: tileSize,
              decoration: InputDecoration(
                labelText: 'superResolution.tileSize'.tr,
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Auto')),
                DropdownMenuItem(value: 128, child: Text('128')),
                DropdownMenuItem(value: 256, child: Text('256')),
                DropdownMenuItem(value: 512, child: Text('512')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => autoSettings['tileSize'] = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gpuIdController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'GPU id',
                hintText: 'superResolution.gpuAutoHint'.tr,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('superResolution.allowCpuOnlyAuto'.tr),
              subtitle: Text('superResolution.allowCpuOnlyAutoHint'.tr),
              value: autoSettings['allowCpuOnly'] == true,
              onChanged: (value) {
                setState(() => autoSettings['allowCpuOnly'] = value);
              },
            ),
            if (!gpuAvailable || !selectedModelInstalled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    if (!gpuAvailable) 'superResolution.noGpuWarning'.tr,
                    if (!selectedModelInstalled)
                      'superResolution.modelMissingHint'.tr,
                  ].join('\n'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: savingSettings ? null : _saveAutoSettings,
                icon: savingSettings
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('common.save'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              Icons.queue_outlined,
              'superResolution.jobs'.tr,
              '',
            ),
            const SizedBox(height: 8),
            Obx(() {
              _downloads.superResolutionJobsVersion.value;
              final jobs = _downloads.superResolutionJobs.values.toList();
              if (jobs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('superResolution.noJobs'.tr),
                );
              }
              return Column(
                children: [
                  for (final job in jobs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        job['title']?.toString().isNotEmpty == true
                            ? job['title'].toString()
                            : '${job['sourceType']} #${job['gid']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${job['model']} · ${job['status']} · ${job['successCount']}/${job['totalCount']}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'downloads.pause'.tr,
                            onPressed: job['status'] == 'running'
                                ? () => _pause(job['id'].toString())
                                : null,
                            icon: const Icon(Icons.pause),
                          ),
                          IconButton(
                            tooltip: 'downloads.resume'.tr,
                            onPressed: job['status'] == 'paused' ||
                                    job['status'] == 'failed'
                                ? () => _resume(job['id'].toString())
                                : null,
                            icon: const Icon(Icons.play_arrow),
                          ),
                          IconButton(
                            tooltip: 'common.delete'.tr,
                            onPressed: () => _delete(job['id'].toString()),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    IconData icon,
    String title,
    String badge,
  ) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (badge.isNotEmpty)
          Chip(
            label: Text(badge),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Map<String, dynamic> _map(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String _localizedCapabilityWarning(String warning) {
    return switch (warning) {
      'Current official Ubuntu packages are treated as amd64-only here. Provide a custom binary for this architecture.' =>
        'superResolution.warningUbuntuAmd64Only'.tr,
      'No Vulkan/GPU device was detected. CPU-only mode is experimental and disabled by default.' =>
        'superResolution.warningNoGpuCpuDisabled'.tr,
      _ => warning,
    };
  }

  List<Map<String, dynamic>> get _modelOptions {
    if (models.isNotEmpty) {
      return models;
    }
    return const [
      {'id': 'realcugan', 'label': 'Real-CUGAN', 'installed': false},
      {
        'id': 'realesrgan-x4plus-anime',
        'label': 'Real-ESRGAN anime',
        'installed': false,
      },
      {
        'id': 'realesrgan-x4plus',
        'label': 'Real-ESRGAN x4plus',
        'installed': false,
      },
      {'id': 'waifu2x', 'label': 'waifu2x', 'installed': false},
    ];
  }

  Map<String, List<Map<String, dynamic>>> get _groupedModelOptions {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final model in _modelOptions) {
      final category = model['category']?.toString() ?? 'basic';
      final key = category == 'advanced'
          ? 'superResolution.modelGroupAdvanced'
          : 'superResolution.modelGroupBasic';
      result.putIfAbsent(key, () => []).add(model);
    }
    return result;
  }
}
