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
  List<Map<String, dynamic>> models = [];
  bool loading = true;
  bool downloading = false;
  String? error;

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
      final modelList = await backendApiClient.listSuperResolutionModels();
      await _downloads.refresh();
      if (!mounted) return;
      setState(() {
        capabilities = caps;
        models = modelList;
      });
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _downloadModel(String model) async {
    setState(() => downloading = true);
    try {
      await backendApiClient.downloadSuperResolutionModel(model);
      await _load();
      Get.snackbar('common.success'.tr, 'superResolution.modelReady'.tr,
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
    if (ok != true) return;
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
        .map((e) => e.toString())
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
            _row('/dev/dri', gpu['hasDevDri'] == true ? 'yes' : 'no'),
            _row('NVIDIA',
                gpu['nvidiaVisible'] == true ? 'visible' : 'not visible'),
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
            for (final model in models)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    Text(model['label']?.toString() ?? model['id'].toString()),
                subtitle: Text(model['installed'] == true
                    ? 'superResolution.installed'.tr
                    : 'superResolution.notInstalled'.tr),
                trailing: FilledButton.icon(
                  onPressed: downloading
                      ? null
                      : () => _downloadModel(model['id'].toString()),
                  icon: downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(model['installed'] == true
                      ? 'common.update'.tr
                      : 'common.download'.tr),
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
}
