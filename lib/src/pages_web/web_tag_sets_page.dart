import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

/// Watched / hidden tags (EH My Tags), proxied by the server.
class WebTagSetsPage extends StatefulWidget {
  const WebTagSetsPage({super.key});

  @override
  State<WebTagSetsPage> createState() => _WebTagSetsPageState();
}

class _WebTagSetsPageState extends State<WebTagSetsPage> {
  int _tagSetNo = 1;
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
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await backendApiClient.addUsertag(
        tag: t,
        tagSetNo: _tagSetNo,
        watch: _watch,
        hidden: _hidden,
      );
      _tagCtrl.clear();
      Get.snackbar('common.success'.tr, 'usertags.added'.tr, snackPosition: SnackPosition.BOTTOM);
      await _load();
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e', snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(int watchedTagId) async {
    setState(() => _busy = true);
    try {
      await backendApiClient.deleteUsertag(watchedTagId: watchedTagId, tagSetNo: _tagSetNo);
      Get.snackbar('common.success'.tr, 'usertags.deleted'.tr, snackPosition: SnackPosition.BOTTOM);
      await _load();
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e', snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('usertags.title'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _busy ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tags = (_data!['tags'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final sets = (_data!['tagSets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sets.length > 1)
          DropdownButtonFormField<int>(
            value: _tagSetNo,
            decoration: InputDecoration(labelText: 'Tag set', border: const OutlineInputBorder()),
            items: sets
                .map((s) => DropdownMenuItem<int>(
                      value: (s['number'] as num?)?.toInt() ?? 1,
                      child: Text(s['name']?.toString() ?? ''),
                    ))
                .toList(),
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _tagSetNo = v);
                    _load();
                  },
          ),
        if (sets.length > 1) const SizedBox(height: 16),
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
            FilledButton(onPressed: _busy ? null : _add, child: Text('usertags.add'.tr)),
          ],
        ),
        const SizedBox(height: 24),
        Text('usertags.currentList'.tr, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text('common.unknown'.tr, style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...tags.map((t) {
            final id = (t['tagId'] as num?)?.toInt() ?? 0;
            final ns = t['namespace']?.toString() ?? '';
            final key = t['key']?.toString() ?? '';
            final label = key.isNotEmpty ? '$ns:$key' : ns;
            final w = t['watched'] == true;
            final h = t['hidden'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Text(
                  [if (w) 'usertags.watch'.tr, if (h) 'usertags.hidden'.tr].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'usertags.delete'.tr,
                  onPressed: _busy || id == 0 ? null : () => _delete(id),
                ),
              ),
            );
          }),
      ],
    );
  }
}
