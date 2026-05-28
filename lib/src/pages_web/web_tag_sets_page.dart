import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';
import 'package:jhentai/src/pages_web/web_watched_tag_styles_controller.dart';

/// Watched / hidden tags (EH My Tags), proxied by the server.
class WebTagSetsPage extends StatefulWidget {
  const WebTagSetsPage({super.key});

  @override
  State<WebTagSetsPage> createState() => _WebTagSetsPageState();
}

class _WebTagSetsPageState extends State<WebTagSetsPage> {
  int _tagSetNo = 1;
  bool _enableDefaultTagSet = true;
  int? _defaultTagSetNo;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  final _tagCtrl = TextEditingController();
  bool _watch = true;
  bool _hidden = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enableDefaultTagSet = WebPreferenceSettings.enableDefaultTagSet;
    _defaultTagSetNo = WebPreferenceSettings.defaultTagSetNo;
    if (_enableDefaultTagSet && _defaultTagSetNo != null) {
      _tagSetNo = _defaultTagSetNo!;
    }
    _load();
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await backendApiClient.listUsertags(tagset: _tagSetNo);
      setState(() {
        _data = m;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'usertags.loadFailed'.trParams({'error': '$e'});
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final t = _tagCtrl.text.trim();
    if (t.isEmpty) {
      return;
    }
    final targetTagSetNo = _enableDefaultTagSet && _defaultTagSetNo != null
        ? _defaultTagSetNo!
        : _tagSetNo;
    setState(() => _busy = true);
    try {
      await backendApiClient.addUsertag(
        tag: t,
        tagSetNo: targetTagSetNo,
        watch: _watch,
        hidden: _hidden,
      );
      _tagCtrl.clear();
      Get.snackbar('common.success'.tr, 'usertags.added'.tr,
          snackPosition: SnackPosition.BOTTOM);
      unawaited(Get.find<WebWatchedTagStylesController>().refresh());
      if (_tagSetNo != targetTagSetNo) {
        setState(() => _tagSetNo = targetTagSetNo);
      }
      await _load();
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(int watchedTagId) async {
    setState(() => _busy = true);
    try {
      await backendApiClient.deleteUsertag(
          watchedTagId: watchedTagId, tagSetNo: _tagSetNo);
      Get.snackbar('common.success'.tr, 'usertags.deleted'.tr,
          snackPosition: SnackPosition.BOTTOM);
      unawaited(Get.find<WebWatchedTagStylesController>().refresh());
      await _load();
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _updateTag({
    required int tagId,
    required String apikey,
    required String status,
    required int weight,
    required String tagColor,
  }) async {
    setState(() => _busy = true);
    try {
      await backendApiClient.updateUsertag(
        tagId: tagId,
        apikey: apikey,
        watch: status == 'watch',
        hidden: status == 'hidden',
        weight: weight,
        tagColor: tagColor,
      );
      Get.snackbar('common.success'.tr, 'usertags.updated'.tr,
          snackPosition: SnackPosition.BOTTOM);
      unawaited(Get.find<WebWatchedTagStylesController>().refresh());
      await _load();
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _searchTag(String label) {
    if (label.trim().isEmpty) {
      return;
    }
    Get.offAllNamed('/web/home', arguments: {'search': label});
  }

  Future<void> _showEditDialog(Map<String, dynamic> tag) async {
    final apikey = _data?['apikey']?.toString() ?? '';
    final id = (tag['tagId'] as num?)?.toInt() ?? 0;
    if (apikey.isEmpty || id == 0) {
      Get.snackbar('common.error'.tr, 'common.unknown'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final weightCtrl = TextEditingController(
      text: ((tag['weight'] as num?)?.toInt() ?? 10).toString(),
    );
    final initialStatus = tag['hidden'] == true
        ? 'hidden'
        : tag['watched'] == true
            ? 'watch'
            : 'none';
    var status = initialStatus;
    final tagColor = tag['tagColor']?.toString() ?? '';
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: Text('usertags.editTitle'.tr),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'watch',
                        icon: const Icon(Icons.favorite_outline),
                        label: Text('usertags.watch'.tr),
                      ),
                      ButtonSegment(
                        value: 'hidden',
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: Text('usertags.hidden'.tr),
                      ),
                      ButtonSegment(
                        value: 'none',
                        icon: const Icon(Icons.remove_circle_outline),
                        label: Text('usertags.none'.tr),
                      ),
                    ],
                    selected: {status},
                    onSelectionChanged: (values) {
                      setDialogState(() => status = values.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: weightCtrl,
                    decoration: InputDecoration(
                      labelText: 'usertags.weight'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    final rawWeight = weightCtrl.text.trim();
    weightCtrl.dispose();
    if (result != true) {
      return;
    }
    final weight = int.tryParse(rawWeight) ?? 10;
    await _updateTag(
      tagId: id,
      apikey: apikey,
      status: status,
      weight: weight.clamp(-99, 99).toInt(),
      tagColor: tagColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('usertags.title'.tr),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _busy ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tags = (_data!['tags'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final sets =
        (_data!['tagSets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sets.length > 1)
          DropdownButtonFormField<int>(
            initialValue: _tagSetNo,
            decoration: const InputDecoration(
                labelText: 'Tag set', border: OutlineInputBorder()),
            items: sets
                .map((s) => DropdownMenuItem<int>(
                      value: (s['number'] as num?)?.toInt() ?? 1,
                      child: Text(s['name']?.toString() ?? ''),
                    ))
                .toList(),
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) {
                      return;
                    }
                    setState(() => _tagSetNo = v);
                    _load();
                  },
          ),
        if (sets.length > 1) const SizedBox(height: 16),
        if (sets.isNotEmpty) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('enableDefaultTagSet'.tr),
            subtitle: Text(_enableDefaultTagSet
                ? 'enableDefaultTagSetHint'.tr
                : 'disableDefaultTagSetHint'.tr),
            value: _enableDefaultTagSet,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() => _enableDefaultTagSet = value);
                    WebPreferenceSettings.saveEnableDefaultTagSet(value);
                  },
          ),
          DropdownButtonFormField<int?>(
            initialValue: _defaultTagSetNo,
            decoration: InputDecoration(
              labelText: 'usertags.defaultTagSet'.tr,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text('usertags.defaultTagSetNone'.tr),
              ),
              ...sets.map((s) => DropdownMenuItem<int?>(
                    value: (s['number'] as num?)?.toInt() ?? 1,
                    child: Text(s['name']?.toString() ?? ''),
                  )),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _defaultTagSetNo = v);
                    WebPreferenceSettings.saveDefaultTagSetNo(v);
                  },
          ),
          const SizedBox(height: 16),
        ],
        Text('usertags.add'.tr, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _tagCtrl,
          decoration: InputDecoration(
            hintText: 'usertags.tagHint'.tr,
            border: const OutlineInputBorder(),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              label: Text('usertags.watch'.tr),
              selected: _watch,
              onSelected: _busy ? null : (v) => setState(() => _watch = v),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('usertags.hidden'.tr),
              selected: _hidden,
              onSelected: _busy ? null : (v) => setState(() => _hidden = v),
            ),
            const Spacer(),
            FilledButton(
                onPressed: _busy ? null : _add, child: Text('usertags.add'.tr)),
          ],
        ),
        const SizedBox(height: 24),
        Text('usertags.currentList'.tr,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text('common.unknown'.tr,
              style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...tags.map((t) {
            final id = (t['tagId'] as num?)?.toInt() ?? 0;
            final ns = t['namespace']?.toString() ?? '';
            final key = t['key']?.toString() ?? '';
            final label = key.isNotEmpty ? '$ns:$key' : ns;
            final w = t['watched'] == true;
            final h = t['hidden'] == true;
            final weight = (t['weight'] as num?)?.toInt() ?? 10;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: _busy ? null : () => _showEditDialog(t),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                subtitle: Text(
                  [
                    if (w) 'usertags.watch'.tr,
                    if (h) 'usertags.hidden'.tr,
                    '${'usertags.weight'.tr}: $weight',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'tagVote.search'.tr,
                      onPressed: _busy ? null : () => _searchTag(label),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'usertags.editTitle'.tr,
                      onPressed:
                          _busy || id == 0 ? null : () => _showEditDialog(t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'usertags.delete'.tr,
                      onPressed: _busy || id == 0 ? null : () => _delete(id),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
