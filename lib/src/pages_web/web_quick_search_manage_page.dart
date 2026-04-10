import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

/// Manage quick searches stored on the server (same format as [WebHomeController.saveCurrentAsQuickSearch]).
class WebQuickSearchManagePage extends StatefulWidget {
  const WebQuickSearchManagePage({super.key});

  @override
  State<WebQuickSearchManagePage> createState() => _WebQuickSearchManagePageState();
}

class _WebQuickSearchManagePageState extends State<WebQuickSearchManagePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await backendApiClient.listQuickSearches();
      setState(() {
        _items = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _delete(String name) async {
    try {
      await backendApiClient.deleteQuickSearch(name);
      await _load();
      if (mounted) {
        Get.snackbar('common.success'.tr, 'quickSearch.deleted'.tr, snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e', snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _add(String name, String keyword) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final config = jsonEncode({
      'keyword': keyword.trim(),
      'categoryFilter': 0,
      'minimumRating': 0,
      'searchInName': true,
      'searchInTags': true,
      'searchInDesc': false,
      'showExpunged': false,
      'filterLanguage': null,
      'disableFilterForLanguage': false,
    });
    try {
      await backendApiClient.saveQuickSearch(trimmed, config);
      await _load();
      if (mounted) Get.back();
      if (mounted) {
        Get.snackbar('common.success'.tr, 'quickSearch.saved'.tr, snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e', snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final kwCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: Text('quickSearch.addNew'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'quickSearch.nameLabel'.tr,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kwCtrl,
                decoration: InputDecoration(
                  labelText: 'quickSearch.keywordLabel'.tr,
                  hintText: 'quickSearch.keywordHint'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () => _add(nameCtrl.text, kwCtrl.text),
            child: Text('common.confirm'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.openQuickSearch'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: Text('common.retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('quickSearch.empty'.tr, style: const TextStyle(color: Colors.grey)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final name = item['name']?.toString() ?? '';
                        final cfg = item['config']?.toString() ?? '';
                        String subtitle = cfg;
                        try {
                          final m = jsonDecode(cfg) as Map<String, dynamic>?;
                          final kw = m?['keyword'] as String? ?? '';
                          subtitle = kw.isEmpty ? cfg : kw;
                        } catch (_) {}
                        if (subtitle.length > 120) {
                          subtitle = '${subtitle.substring(0, 120)}…';
                        }
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await Get.dialog<bool>(
                                AlertDialog(
                                  title: Text('quickSearch.deleteTitle'.tr),
                                  content: Text('quickSearch.deleteConfirm'.trParams({'name': name})),
                                  actions: [
                                    TextButton(onPressed: () => Get.back(result: false), child: Text('common.cancel'.tr)),
                                    FilledButton(onPressed: () => Get.back(result: true), child: Text('common.delete'.tr)),
                                  ],
                                ),
                              );
                              if (ok == true) await _delete(name);
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}
