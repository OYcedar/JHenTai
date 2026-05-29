import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/consts/locale_consts.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

/// Manage quick searches stored on the server (same format as [WebHomeController.saveCurrentAsQuickSearch]).
class WebQuickSearchManagePage extends StatefulWidget {
  const WebQuickSearchManagePage({super.key});

  @override
  State<WebQuickSearchManagePage> createState() =>
      _WebQuickSearchManagePageState();
}

class _WebQuickSearchManagePageState extends State<WebQuickSearchManagePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _savingOrder = false;
  String? _error;

  static const _categoryKeys = [
    'category.doujinshi',
    'category.manga',
    'category.artistCg',
    'category.gameCg',
    'category.western',
    'category.nonH',
    'category.imageSet',
    'category.cosplay',
    'category.asianPorn',
    'category.misc',
  ];

  static const _categoryBits = [2, 4, 8, 16, 512, 256, 32, 64, 128, 1];

  static final List<String> _searchLanguageKeys = LocaleConsts
      .language2Abbreviation.keys
      .where((key) => key != 'japanese')
      .toList();

  static const _searchSections = ['home', 'favorites', 'watched'];

  static String _sectionLabel(String section) {
    return switch (section) {
      'favorites' => 'home.favorites'.tr,
      'watched' => 'home.watched'.tr,
      _ => 'home.home'.tr,
    };
  }

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
        Get.snackbar('common.success'.tr, 'quickSearch.deleted'.tr,
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _add(String name, String config) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      final nextOrder = _items.length;
      await backendApiClient.saveQuickSearch(trimmed, config,
          sortOrder: nextOrder);
      await _load();
      if (mounted) Get.back();
      if (mounted) {
        Get.snackbar('common.success'.tr, 'quickSearch.saved'.tr,
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Map<String, dynamic> _decodeConfig(String config, {String keyword = ''}) {
    try {
      final decoded = jsonDecode(config);
      if (decoded is Map) {
        final result = Map<String, dynamic>.from(decoded);
        final section = result['section']?.toString() ?? 'home';
        result['section'] =
            _searchSections.contains(section) ? section : 'home';
        result['favoriteSortFavoritedFirst'] =
            result['favoriteSortFavoritedFirst'] as bool? ?? true;
        if (result['favoriteCategoryFilter'] != null) {
          result['favoriteCategoryFilter'] =
              (result['favoriteCategoryFilter'] as num?)?.toInt();
        }
        return result;
      }
    } catch (_) {}
    return {
      'section': 'home',
      'keyword': keyword.trim(),
      'categoryFilter': 0,
      'minimumRating': 0,
      'searchInName': true,
      'searchInTags': true,
      'searchInDesc': false,
      'showExpunged': false,
      'onlyShowGalleriesWithTorrents': false,
      'pageAtLeast': null,
      'pageAtMost': null,
      'filterLanguage': null,
      'disableFilterForLanguage': false,
      'disableFilterForUploader': false,
      'disableFilterForTags': false,
      'favoriteSortFavoritedFirst': true,
      'favoriteCategoryFilter': null,
    };
  }

  Future<void> _updateQuickSearch({
    required String oldName,
    required String newName,
    required Map<String, dynamic> config,
    required int sortOrder,
  }) async {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) return;
    try {
      await backendApiClient.saveQuickSearch(
        trimmedName,
        jsonEncode(config),
        sortOrder: sortOrder,
      );
      if (trimmedName != oldName) {
        await backendApiClient.deleteQuickSearch(oldName);
      }
      await _load();
      if (mounted) Get.back();
      if (mounted) {
        Get.snackbar('common.success'.tr, 'quickSearch.saved'.tr,
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _persistOrder() async {
    setState(() => _savingOrder = true);
    try {
      await Future.wait(_items.asMap().entries.map((entry) {
        final item = entry.value;
        final name = item['name']?.toString() ?? '';
        final config = item['config']?.toString() ?? '';
        if (name.isEmpty || config.isEmpty) return Future<void>.value();
        item['sort_order'] = entry.key;
        return backendApiClient.saveQuickSearch(name, config,
            sortOrder: entry.key);
      }));
      await _load();
    } catch (e) {
      if (mounted) {
        Get.snackbar('common.error'.tr, '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    _persistOrder();
  }

  void _runQuickSearch(Map<String, dynamic> item) {
    final config = _decodeConfig(item['config']?.toString() ?? '');
    Get.offAllNamed('/web/home', arguments: {
      'quickSearchConfig': jsonEncode(config),
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final kwCtrl = TextEditingController();
    var config = _decodeConfig('', keyword: '');
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
              const SizedBox(height: 12),
              _QuickSearchConfigEditor(
                config: config,
                onChanged: (value) => config = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () {
              config['keyword'] = kwCtrl.text.trim();
              _add(nameCtrl.text, jsonEncode(config));
            },
            child: Text('common.confirm'.tr),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, int index) {
    final oldName = item['name']?.toString() ?? '';
    final oldConfig = item['config']?.toString() ?? '';
    var config = _decodeConfig(oldConfig);
    final nameCtrl = TextEditingController(text: oldName);
    final kwCtrl =
        TextEditingController(text: config['keyword']?.toString() ?? '');
    final sortOrder = (item['sort_order'] as num?)?.toInt() ?? index;

    Get.dialog(
      AlertDialog(
        title: Text('quickSearch.editTitle'.tr),
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
              const SizedBox(height: 12),
              _QuickSearchConfigEditor(
                config: config,
                onChanged: (value) => config = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () => _updateQuickSearch(
              oldName: oldName,
              newName: nameCtrl.text,
              config: {
                ...config,
                'keyword': kwCtrl.text.trim(),
              },
              sortOrder: sortOrder,
            ),
            child: Text('common.save'.tr),
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
          if (_savingOrder)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading || _savingOrder ? null : _load),
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
                        FilledButton(
                            onPressed: _load, child: Text('common.retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('quickSearch.empty'.tr,
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      onReorder: _savingOrder ? (_, __) {} : _reorder,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final name = item['name']?.toString() ?? '';
                        final cfg = item['config']?.toString() ?? '';
                        String subtitle = cfg;
                        try {
                          final m = jsonDecode(cfg) as Map<String, dynamic>?;
                          final kw = m?['keyword'] as String? ?? '';
                          final section = m?['section']?.toString() ?? 'home';
                          final sectionText = _sectionLabel(section);
                          subtitle =
                              kw.isEmpty ? sectionText : '$sectionText - $kw';
                        } catch (_) {}
                        if (subtitle.length > 120) {
                          subtitle = '${subtitle.substring(0, 120)}…';
                        }
                        return Card(
                          key: ValueKey(name),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: _savingOrder
                                ? null
                                : () => _runQuickSearch(item),
                            leading: ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text(name),
                            subtitle: Text(subtitle,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.search),
                                  tooltip: 'tagVote.search'.tr,
                                  onPressed: _savingOrder
                                      ? null
                                      : () => _runQuickSearch(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'quickSearch.editTitle'.tr,
                                  onPressed: _savingOrder
                                      ? null
                                      : () => _showEditDialog(item, i),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _savingOrder
                                      ? null
                                      : () async {
                                          final ok = await Get.dialog<bool>(
                                            AlertDialog(
                                              title: Text(
                                                  'quickSearch.deleteTitle'.tr),
                                              content: Text(
                                                  'quickSearch.deleteConfirm'
                                                      .trParams(
                                                          {'name': name})),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Get.back(result: false),
                                                    child: Text(
                                                        'common.cancel'.tr)),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Get.back(result: true),
                                                    child: Text(
                                                        'common.delete'.tr)),
                                              ],
                                            ),
                                          );
                                          if (ok == true) await _delete(name);
                                        },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _QuickSearchConfigEditor extends StatefulWidget {
  const _QuickSearchConfigEditor({
    required this.config,
    required this.onChanged,
  });

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_QuickSearchConfigEditor> createState() =>
      _QuickSearchConfigEditorState();
}

class _QuickSearchConfigEditorState extends State<_QuickSearchConfigEditor> {
  late Map<String, dynamic> _config;
  late final TextEditingController _pageAtLeastCtrl;
  late final TextEditingController _pageAtMostCtrl;

  @override
  void initState() {
    super.initState();
    _config = Map<String, dynamic>.from(widget.config);
    _pageAtLeastCtrl = TextEditingController(
      text: _config['pageAtLeast']?.toString() ?? '',
    );
    _pageAtMostCtrl = TextEditingController(
      text: _config['pageAtMost']?.toString() ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _pageAtLeastCtrl.dispose();
    _pageAtMostCtrl.dispose();
    super.dispose();
  }

  int get _categoryFilter => (_config['categoryFilter'] as num?)?.toInt() ?? 0;

  String get _section {
    final section = _config['section']?.toString() ?? 'home';
    return _WebQuickSearchManagePageState._searchSections.contains(section)
        ? section
        : 'home';
  }

  bool _boolValue(String key, bool fallback) =>
      _config[key] as bool? ?? fallback;

  int _intValue(String key, int fallback) =>
      (_config[key] as num?)?.toInt() ?? fallback;

  void _set(String key, dynamic value) {
    setState(() => _config[key] = value);
    _emit();
  }

  void _emit() => widget.onChanged(Map<String, dynamic>.from(_config));

  void _toggleCategory(int index) {
    final bit = _WebQuickSearchManagePageState._categoryBits[index];
    final next = (_categoryFilter & bit) == 0
        ? _categoryFilter | bit
        : _categoryFilter & ~bit;
    _set('categoryFilter', next);
  }

  void _setPageValue(String key, String raw) {
    final value = int.tryParse(raw.trim());
    _set(key, value != null && value > 0 ? value : null);
  }

  void _resetFilters() {
    setState(() {
      _config = {
        ..._config,
        'categoryFilter': 0,
        'minimumRating': 0,
        'searchInName': true,
        'searchInTags': true,
        'searchInDesc': false,
        'showExpunged': false,
        'onlyShowGalleriesWithTorrents': false,
        'pageAtLeast': null,
        'pageAtMost': null,
        'filterLanguage': null,
        'disableFilterForLanguage': false,
        'disableFilterForUploader': false,
        'disableFilterForTags': false,
        'favoriteSortFavoritedFirst': true,
        'favoriteCategoryFilter': null,
      };
      _pageAtLeastCtrl.clear();
      _pageAtMostCtrl.clear();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: Text('home.searchFilterSheetTitle'.tr),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _section,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'defaultTab'.tr,
            border: const OutlineInputBorder(),
          ),
          items: _WebQuickSearchManagePageState._searchSections
              .map((section) => DropdownMenuItem<String>(
                    value: section,
                    child: Text(
                      _WebQuickSearchManagePageState._sectionLabel(section),
                    ),
                  ))
              .toList(),
          onChanged: (value) => _set('section', value ?? 'home'),
        ),
        if (_section == 'favorites') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            initialValue: _boolValue('favoriteSortFavoritedFirst', true),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'home.favSortTitle'.tr,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<bool>(
                value: true,
                child: Text('home.favSortFavorited'.tr),
              ),
              DropdownMenuItem<bool>(
                value: false,
                child: Text('home.favSortPublished'.tr),
              ),
            ],
            onChanged: (value) =>
                _set('favoriteSortFavoritedFirst', value ?? true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: (_config['favoriteCategoryFilter'] as num?)?.toInt(),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'home.favorites'.tr,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text('home.favAllFolders'.tr),
              ),
              ...List.generate(
                10,
                (index) => DropdownMenuItem<int?>(
                  value: index,
                  child: Text('home.favSlotShort'.trParams({'n': '$index'})),
                ),
              ),
            ],
            onChanged: (value) => _set('favoriteCategoryFilter', value),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child:
              Text('home.categoryFilter'.tr, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(
              _WebQuickSearchManagePageState._categoryKeys.length,
              (index) {
                final enabled = (_categoryFilter &
                        _WebQuickSearchManagePageState._categoryBits[index]) ==
                    0;
                return FilterChip(
                  label: Text(
                    _WebQuickSearchManagePageState._categoryKeys[index].tr,
                  ),
                  selected: enabled,
                  onSelected: (_) => _toggleCategory(index),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _config['filterLanguage'] as String?,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'home.language'.tr,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('home.languageNone'.tr),
            ),
            ..._WebQuickSearchManagePageState._searchLanguageKeys.map(
              (key) => DropdownMenuItem<String?>(
                value: key,
                child: Text('${key[0].toUpperCase()}${key.substring(1)}'),
              ),
            ),
          ],
          onChanged: (value) => _set('filterLanguage', value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child:
              Text('home.minimumRating'.tr, style: theme.textTheme.titleSmall),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _intValue('minimumRating', 0).toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                label: _intValue('minimumRating', 0) == 0
                    ? 'home.ratingAny'.tr
                    : '${_intValue('minimumRating', 0)}+',
                onChanged: (value) => _set('minimumRating', value.round()),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                _intValue('minimumRating', 0) == 0
                    ? 'home.ratingAny'.tr
                    : '${_intValue('minimumRating', 0)}+',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pageAtLeastCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'home.pageAtLeast'.tr,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _setPageValue('pageAtLeast', value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pageAtMostCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'home.pageAtMost'.tr,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _setPageValue('pageAtMost', value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.galleryName'.tr),
          value: _boolValue('searchInName', true),
          onChanged: (value) => _set('searchInName', value ?? true),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.tags'.tr),
          value: _boolValue('searchInTags', true),
          onChanged: (value) => _set('searchInTags', value ?? true),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.description'.tr),
          value: _boolValue('searchInDesc', false),
          onChanged: (value) => _set('searchInDesc', value ?? false),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.showExpunged'.tr),
          value: _boolValue('showExpunged', false),
          onChanged: (value) => _set('showExpunged', value),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.onlyShowGalleriesWithTorrents'.tr),
          value: _boolValue('onlyShowGalleriesWithTorrents', false),
          onChanged: (value) => _set('onlyShowGalleriesWithTorrents', value),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.disableFilterForLanguage'.tr),
          value: _boolValue('disableFilterForLanguage', false),
          onChanged: (value) => _set('disableFilterForLanguage', value),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.disableFilterForUploader'.tr),
          value: _boolValue('disableFilterForUploader', false),
          onChanged: (value) => _set('disableFilterForUploader', value),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('home.disableFilterForTags'.tr),
          value: _boolValue('disableFilterForTags', false),
          onChanged: (value) => _set('disableFilterForTags', value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt),
            label: Text('common.reset'.tr),
          ),
        ),
      ],
    );
  }
}
