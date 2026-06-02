import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebSettingsEhPage extends StatefulWidget {
  const WebSettingsEhPage({super.key});

  @override
  State<WebSettingsEhPage> createState() => _WebSettingsEhPageState();
}

class _WebSettingsEhPageState extends State<WebSettingsEhPage>
    with WebScrollToTopState<WebSettingsEhPage> {
  final WebSettingsController controller = Get.find<WebSettingsController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuEH'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.isLoggedIn.value) {
          return Center(
              child: Text('settings.ehRequiresLogin'.tr,
                  textAlign: TextAlign.center));
        }
        final site = controller.site.value;
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  _siteCard(context),
                  const SizedBox(height: 12),
                  _linkCard(context),
                  const SizedBox(height: 12),
                  _EhProfileCard(key: ValueKey(site), site: site),
                ],
              ),
            ),
          ),
        );
      }),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _siteCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.site'.tr,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'EH', label: Text('E-Hentai')),
                    ButtonSegment(value: 'EX', label: Text('ExHentai')),
                  ],
                  selected: {controller.site.value},
                  onSelectionChanged: (selected) =>
                      controller.switchSite(selected.first),
                )),
            Obx(() {
              if (controller.site.value != 'EX') {
                return const SizedBox.shrink();
              }
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('redirect2Eh'.tr),
                subtitle: Text('redirect2EhHint'.tr),
                value: controller.redirectToEh.value,
                onChanged: controller.setRedirectToEh,
              );
            }),
            const SizedBox(height: 8),
            Obx(() {
              final status = controller.cookieStatus.value;
              if (status.isEmpty) {
                return const SizedBox.shrink();
              }
              final good = status.contains('igneous') ||
                  status == 'settings.cookieStatusFull'.tr;
              return Row(
                children: [
                  Icon(
                    good ? Icons.check_circle : Icons.warning_amber,
                    size: 16,
                    color: good ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall,
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

  Widget _linkCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text('settings.ehMyTags'.tr),
            subtitle: Text('settings.ehMyTagsHint'.tr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed('/web/tag-sets'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text('settings.ehSiteSetting'.tr),
            subtitle: Text('settings.ehSiteSettingHint'.tr),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => web.window.open(
              controller.site.value == 'EX'
                  ? 'https://exhentai.org/uconfig.php'
                  : 'https://e-hentai.org/uconfig.php',
              '_blank',
            ),
          ),
          const Divider(height: 1),
          _EhStatusTile(controller: controller),
        ],
      ),
    );
  }
}

class _EhProfileCard extends StatefulWidget {
  final String site;

  const _EhProfileCard({super.key, required this.site});

  @override
  State<_EhProfileCard> createState() => _EhProfileCardState();
}

class _EhProfileCardState extends State<_EhProfileCard> {
  bool _loading = true;
  bool _saving = false;
  String _error = '';
  List<Map<String, dynamic>> _profiles = [];

  int? get _selectedProfile {
    for (final profile in _profiles) {
      if (profile['selected'] == true) {
        return (profile['number'] as num?)?.toInt();
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading && _profiles.isNotEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      _profiles = await backendApiClient.listProfiles();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(int profile) async {
    setState(() => _saving = true);
    try {
      await backendApiClient.selectProfile(profile);
      setState(() {
        for (final item in _profiles) {
          item['selected'] = (item['number'] as num?)?.toInt() == profile;
        }
      });
      Get.snackbar('common.success'.tr, 'settings.ehProfileSaved'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.ehProfileSaveFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProfile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'settings.ehProfile'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'common.refresh'.tr,
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading || _saving ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error.isNotEmpty)
              Text(
                'settings.ehProfileLoadFailed'.trParams({'error': _error}),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_profiles.isEmpty)
              Text('settings.ehProfileEmpty'.tr)
            else
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: 'settings.ehSelectedProfile'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: _profiles
                    .map((profile) => DropdownMenuItem<int>(
                          value: (profile['number'] as num?)?.toInt(),
                          child: Text(profile['name']?.toString() ?? ''),
                        ))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null || value == selected) {
                          return;
                        }
                        _select(value);
                      },
              ),
            const SizedBox(height: 8),
            Text(
              'settings.ehProfileHint'.trParams({'site': widget.site}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EhStatusTile extends StatefulWidget {
  final WebSettingsController controller;

  const _EhStatusTile({required this.controller});

  @override
  State<_EhStatusTile> createState() => _EhStatusTileState();
}

class _EhStatusTileState extends State<_EhStatusTile> {
  bool _loading = false;
  bool _resetting = false;
  String _error = '';
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      _status = await backendApiClient.fetchEhStatus();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetLimit() async {
    if (_resetting) {
      return;
    }
    setState(() => _resetting = true);
    try {
      await backendApiClient.resetImageLimit();
      await _load();
      Get.snackbar('common.success'.tr, 'settings.ehQuotaReset'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'settings.ehQuotaResetFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  Future<void> _confirmResetLimit(Object? resetCost) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('common.reset'.tr),
        content: Text(
          'settings.ehQuotaResetConfirm'.trParams({
            'cost': resetCost?.toString() ?? '-',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('common.confirm'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _resetLimit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDonator = _status['isDonator'] == true;
    final current = _status['currentConsumption'];
    final total = _status['totalLimit'];
    final resetCost = _status['resetCost'];
    final gp = _status['gp']?.toString() ?? '-';
    final credit = _status['credit']?.toString() ?? '-';
    final subtitle = _error.isNotEmpty
        ? 'settings.ehStatusFailed'.trParams({'error': _error})
        : _loading
            ? 'common.loading'.tr
            : [
                '${'settings.ehAssets'.tr}: GP $gp / Credits $credit',
                if (isDonator && current != null && total != null)
                  '${'settings.ehImageQuota'.tr}: $current / $total',
                if (isDonator && resetCost != null)
                  '${'settings.ehResetCost'.tr}: $resetCost GP',
                if (!isDonator) 'settings.ehQuotaUnavailable'.tr,
              ].join('\n');

    return ListTile(
      leading: _loading || _resetting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.account_circle_outlined),
      title: Text('settings.ehProfileAndQuota'.tr),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          if (isDonator)
            IconButton(
              tooltip: 'common.reset'.tr,
              icon: const Icon(Icons.restart_alt),
              onPressed:
                  _resetting ? null : () => _confirmResetLimit(resetCost),
            ),
        ],
      ),
    );
  }
}
