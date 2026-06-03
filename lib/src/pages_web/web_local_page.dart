import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:jhentai/src/pages_web/web_scan_roots_dialog.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

class WebLocalController extends GetxController
    with WebScrollToTopControllerMixin {
  static const viewModeStorageKey = 'jh_web_local_view_mode';
  static const gridColumnsStorageKey = 'jh_web_local_grid_columns';
  static const _searchDebounceDuration = Duration(milliseconds: 180);
  static const _scanPollInitialDelay = Duration(milliseconds: 250);
  static const _scanPollMaxDelay = Duration(milliseconds: 1000);
  static const _scanPollTimeout = Duration(seconds: 90);

  final searchTextController = TextEditingController();
  final galleries = <Map<String, dynamic>>[].obs;
  final roots = <String>[].obs;
  final extraRoots = <String>[].obs;
  final currentPath = ''.obs;
  final searchQuery = ''.obs;
  final viewMode = 'list'.obs;
  final groupExpanded = <String, bool>{}.obs;
  final isLoading = true.obs;
  final isScanning = false.obs;
  final scanProgress = Rxn<LocalGalleryScanProgress>();
  final errorMessage = ''.obs;

  int _dataVersion = 0;
  _LocalFilteredCache? _filteredCache;
  _LocalGroupedCache? _groupedCache;
  _LocalPathListCache? _childDirectoriesCache;
  _LocalPathGalleryCache? _currentDirectoryGalleriesCache;
  Timer? _searchDebounceTimer;
  String? _pendingSearchQuery;

  @override
  void onInit() {
    super.onInit();
    bindScrollToTop();
    final savedViewMode = web.window.localStorage.getItem(viewModeStorageKey);
    if (savedViewMode == 'grid' || savedViewMode == 'list') {
      viewMode.value = savedViewMode!;
    }
    _loadGalleries();
  }

  @override
  void onClose() {
    _searchDebounceTimer?.cancel();
    unbindScrollToTop();
    searchTextController.dispose();
    super.onClose();
  }

  Future<void> _loadGalleries() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final rootInfo = await backendApiClient.getLocalGalleryRootInfo();
      final listInfo = await backendApiClient.getLocalGalleryListInfo();
      final galleryData = listInfo.galleries;
      isScanning.value = listInfo.scanning;
      scanProgress.value = listInfo.scanProgress;
      final rootData = rootInfo.roots
          .map(_normalizePath)
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
      roots.value = rootData;
      extraRoots.value = rootInfo.extraRoots
          .map(_normalizePath)
          .where((p) => p.isNotEmpty)
          .toList()
        ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));

      galleries.value = galleryData.cast<Map<String, dynamic>>();
      _markDataChanged();
      if (currentPath.value.isNotEmpty &&
          !_isCurrentPathStillVisible(currentPath.value)) {
        currentPath.value = '';
      }
      for (final group in groupedGalleries.keys) {
        groupExpanded.putIfAbsent(group, () => true);
      }
    } catch (e) {
      errorMessage.value = 'local.loadListFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshGalleries() async {
    isScanning.value = true;
    scanProgress.value = const LocalGalleryScanProgress(
      scanning: true,
      foundCount: 0,
      elapsedMs: 0,
    );
    final previousCount = galleries.length;
    try {
      await backendApiClient.refreshLocalGalleries();
      await _waitForScanComplete();
      await _loadGalleries();
      currentPath.value = '';
      Get.snackbar(
        'common.success'.tr,
        '${'newGalleryCount'.tr}: ${galleries.length - previousCount}',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'local.scanFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isScanning.value = false;
    }
  }

  Future<void> _waitForScanComplete() async {
    final deadline = DateTime.now().add(_scanPollTimeout);
    var delay = _scanPollInitialDelay;
    while (DateTime.now().isBefore(deadline)) {
      final info = await backendApiClient.getLocalGalleryListInfo();
      isScanning.value = info.scanning;
      scanProgress.value = info.scanProgress;
      if (!info.scanning) {
        return;
      }
      await Future.delayed(delay);
      final nextDelay = delay + const Duration(milliseconds: 150);
      delay = nextDelay > _scanPollMaxDelay ? _scanPollMaxDelay : nextDelay;
    }
  }

  void showHelp() {
    Get.snackbar(
      'local.title'.tr,
      'local.helpText'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 8),
    );
  }

  Future<void> reloadGalleries() => _loadGalleries();

  Future<void> addScanRoot(String path) async {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return;
    }
    await backendApiClient.addLocalGalleryRoot(normalized);
    await _loadGalleries();
  }

  Future<void> deleteScanRoot(String path) async {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return;
    }
    await backendApiClient.deleteLocalGalleryRoot(normalized);
    await _loadGalleries();
  }

  Future<void> openGallery(Map<String, dynamic> gallery) async {
    final title = gallery['title'] as String? ?? '';
    final path = gallery['path'] as String? ?? '';
    try {
      final images = await backendApiClient.getLocalGalleryImages(path);
      if (images.isEmpty) {
        Get.snackbar('local.empty'.tr, 'local.noImages'.tr,
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      Get.toNamed('/web/reader/0/local?mode=local', arguments: {
        'images': images,
        'title': title,
        'progressKey': gallery['coverPath'] ?? path,
      });
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'local.loadFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> deleteGallery(Map<String, dynamic> gallery) async {
    final path = gallery['path'] as String? ?? '';
    if (path.isEmpty) {
      return;
    }
    try {
      await backendApiClient.deleteLocalGallery(path);
      galleries.removeWhere((item) => item['path'] == path);
      galleries.refresh();
      _markDataChanged();
      Get.snackbar('common.success'.tr, 'local.deleteSuccess'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'local.deleteFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  bool get isSearching => searchQuery.value.trim().isNotEmpty;

  List<Map<String, dynamic>> get filteredGalleries {
    final q = searchQuery.value.trim().toLowerCase();
    final cached = _filteredCache;
    if (cached != null && cached.version == _dataVersion && cached.query == q) {
      return cached.items;
    }
    if (q.isEmpty) {
      final items = List<Map<String, dynamic>>.unmodifiable(galleries);
      _filteredCache = _LocalFilteredCache(_dataVersion, q, items);
      return items;
    }
    final items = galleries.where((gallery) {
      final title = gallery['title']?.toString().toLowerCase() ?? '';
      final path = gallery['path']?.toString().toLowerCase() ?? '';
      return title.contains(q) || path.contains(q);
    }).toList();
    final result = List<Map<String, dynamic>>.unmodifiable(items);
    _filteredCache = _LocalFilteredCache(_dataVersion, q, result);
    return result;
  }

  Map<String, List<Map<String, dynamic>>> get groupedGalleries {
    final q = searchQuery.value.trim().toLowerCase();
    final cached = _groupedCache;
    if (cached != null && cached.version == _dataVersion && cached.query == q) {
      return cached.groups;
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final gallery in filteredGalleries) {
      final path = gallery['path']?.toString() ?? '';
      final group = _parentPath(path);
      groups.putIfAbsent(group, () => []).add(gallery);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
    final result = {
      for (final key in sortedKeys)
        key: List<Map<String, dynamic>>.unmodifiable(groups[key]!
          ..sort(
            (a, b) => _naturalCompare(
              a['title']?.toString() ?? '',
              b['title']?.toString() ?? '',
            ),
          ))
    };
    _groupedCache = _LocalGroupedCache(_dataVersion, q, result);
    return result;
  }

  void toggleGroup(String group) {
    groupExpanded[group] = !(groupExpanded[group] ?? true);
    groupExpanded.refresh();
  }

  void toggleViewMode() {
    final next = viewMode.value == 'grid' ? 'list' : 'grid';
    viewMode.value = next;
    _resetScrollState();
    web.window.localStorage.setItem(viewModeStorageKey, next);
  }

  static int? get gridColumns {
    final raw = web.window.localStorage.getItem(gridColumnsStorageKey);
    final value = int.tryParse(raw ?? '');
    return value != null && value >= 2 && value <= 8 ? value : null;
  }

  static void setGridColumns(int? count) {
    if (count == null) {
      web.window.localStorage.removeItem(gridColumnsStorageKey);
    } else {
      web.window.localStorage.setItem(gridColumnsStorageKey, '$count');
    }
  }

  void enterDirectory(String path) {
    currentPath.value = _normalizePath(path);
    _resetScrollState();
  }

  void goUpDirectory() {
    final current = currentPath.value;
    if (current.isEmpty) {
      return;
    }
    if (roots.contains(current)) {
      currentPath.value = '';
      _resetScrollState();
      return;
    }
    final parent = _parentPath(current);
    currentPath.value = _isAtOrUnderRoot(parent) ? parent : '';
    _resetScrollState();
  }

  void updateSearchQuery(String value) {
    _pendingSearchQuery = value;
    _searchDebounceTimer?.cancel();
    if (value.isEmpty) {
      _flushPendingSearchQuery();
      return;
    }
    _searchDebounceTimer = Timer(
      _searchDebounceDuration,
      _flushPendingSearchQuery,
    );
  }

  void clearSearchQuery() {
    searchTextController.clear();
    _pendingSearchQuery = '';
    _flushPendingSearchQuery();
  }

  void _flushPendingSearchQuery() {
    _searchDebounceTimer?.cancel();
    final value = _pendingSearchQuery;
    _pendingSearchQuery = null;
    if (value == null || searchQuery.value == value) {
      return;
    }
    searchQuery.value = value;
    _resetScrollState();
  }

  void _resetScrollState() {
    resetScrollToTopState();
  }

  List<String> get childDirectories {
    final current = currentPath.value;
    final cached = _childDirectoriesCache;
    if (cached != null &&
        cached.version == _dataVersion &&
        cached.currentPath == current) {
      return cached.paths;
    }
    final dirs = <String>{};
    if (current.isEmpty) {
      if (roots.isNotEmpty) {
        final paths = List<String>.unmodifiable(roots);
        _childDirectoriesCache =
            _LocalPathListCache(_dataVersion, current, paths);
        return paths;
      }
      dirs.addAll(
          galleries.map((g) => _topDerivedRoot(g['path']?.toString() ?? '')));
    } else {
      for (final gallery in galleries) {
        final galleryPath = _normalizePath(gallery['path']?.toString() ?? '');
        final child = _nextChildDirectory(current, galleryPath);
        if (child != null) {
          dirs.add(child);
        }
      }
    }
    final paths = dirs.where((path) => path.isNotEmpty).toList()
      ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
    final result = List<String>.unmodifiable(paths);
    _childDirectoriesCache = _LocalPathListCache(_dataVersion, current, result);
    return result;
  }

  List<Map<String, dynamic>> get currentDirectoryGalleries {
    final current = currentPath.value;
    if (current.isEmpty) {
      return const [];
    }
    final cached = _currentDirectoryGalleriesCache;
    if (cached != null &&
        cached.version == _dataVersion &&
        cached.currentPath == current) {
      return cached.items;
    }
    final items = galleries
        .where((gallery) =>
            _parentPath(gallery['path']?.toString() ?? '') == current)
        .toList();
    items.sort((a, b) => _naturalCompare(
          a['title']?.toString() ?? '',
          b['title']?.toString() ?? '',
        ));
    final result = List<Map<String, dynamic>>.unmodifiable(items);
    _currentDirectoryGalleriesCache =
        _LocalPathGalleryCache(_dataVersion, current, result);
    return result;
  }

  void _markDataChanged() {
    _dataVersion++;
    _filteredCache = null;
    _groupedCache = null;
    _childDirectoriesCache = null;
    _currentDirectoryGalleriesCache = null;
  }

  bool _isCurrentPathStillVisible(String path) {
    if (roots.contains(path)) {
      return true;
    }
    return galleries.any((gallery) {
      final galleryPath = _normalizePath(gallery['path']?.toString() ?? '');
      return galleryPath == path || galleryPath.startsWith('$path/');
    });
  }

  bool _isAtOrUnderRoot(String path) {
    if (path.isEmpty) {
      return false;
    }
    if (roots.isEmpty) {
      return true;
    }
    return roots.any((root) => path == root || path.startsWith('$root/'));
  }

  static String? _nextChildDirectory(String parent, String galleryPath) {
    if (parent.isEmpty || galleryPath.isEmpty) {
      return null;
    }
    if (!galleryPath.startsWith('$parent/')) {
      return null;
    }
    final rest = galleryPath.substring(parent.length + 1);
    if (rest.isEmpty || !rest.contains('/')) {
      return null;
    }
    return '$parent/${rest.split('/').first}';
  }

  static String _topDerivedRoot(String path) {
    final parent = _parentPath(path);
    if (parent.isEmpty) {
      return '';
    }
    final parts = parent.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) {
      return parent;
    }
    return '/${parts.take(2).join('/')}';
  }

  static String _parentPath(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    if (index <= 0) {
      return normalized;
    }
    return normalized.substring(0, index);
  }

  static String _displayPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return '/';
    }
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return normalized;
    }
    final tail = parts.length >= 2
        ? '${parts[parts.length - 2]}/${parts.last}'
        : parts.last;
    return tail;
  }

  static String _normalizePath(String path) {
    return path.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'/+$'), '');
  }

  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+|\D+)');
    final aParts = pattern.allMatches(a.toLowerCase()).toList();
    final bParts = pattern.allMatches(b.toLowerCase()).toList();
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < len; i++) {
      final aPart = aParts[i].group(0)!;
      final bPart = bParts[i].group(0)!;
      if (aPart == bPart) {
        continue;
      }

      final aNum = int.tryParse(aPart);
      final bNum = int.tryParse(bPart);
      if (aNum != null && bNum != null) {
        final cmp = aNum.compareTo(bNum);
        if (cmp != 0) {
          return cmp;
        }
      }

      final cmp = aPart.compareTo(bPart);
      if (cmp != 0) {
        return cmp;
      }
    }

    return aParts.length.compareTo(bParts.length);
  }
}

class _LocalFilteredCache {
  const _LocalFilteredCache(this.version, this.query, this.items);

  final int version;
  final String query;
  final List<Map<String, dynamic>> items;
}

class _LocalGroupedCache {
  _LocalGroupedCache(
    this.version,
    this.query,
    Map<String, List<Map<String, dynamic>>> groups,
  ) : groups = Map.unmodifiable(groups);

  final int version;
  final String query;
  final Map<String, List<Map<String, dynamic>>> groups;
}

class _LocalPathListCache {
  const _LocalPathListCache(this.version, this.currentPath, this.paths);

  final int version;
  final String currentPath;
  final List<String> paths;
}

class _LocalPathGalleryCache {
  const _LocalPathGalleryCache(this.version, this.currentPath, this.items);

  final int version;
  final String currentPath;
  final List<Map<String, dynamic>> items;
}

class WebLocalPage extends GetView<WebLocalController> {
  const WebLocalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Obx(
            () => controller.currentPath.value.isEmpty || controller.isSearching
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'local.parentDirectory'.tr,
                    onPressed: controller.goUpDirectory,
                  )),
        title: Text('local.title'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'local.helpText'.tr,
            onPressed: controller.showHelp,
          ),
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'local.scanRoots'.tr,
            onPressed: () => showWebScanRootsDialog(
              context,
              onChanged: controller.reloadGalleries,
            ),
          ),
          Obx(() => IconButton(
                icon: Icon(controller.viewMode.value == 'grid'
                    ? Icons.view_list
                    : Icons.grid_view),
                tooltip: 'listMode.toggle'.tr,
                onPressed: controller.toggleViewMode,
              )),
          Obx(() => controller.isScanning.value
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: controller.refreshGalleries)),
        ],
      ),
      floatingActionButton: Obx(
        () => buildWebScrollToTopFab(
          visible: controller.showScrollToTop.value,
          onPressed: controller.scrollToTop,
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(controller.errorMessage.value,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => controller.reloadGalleries(),
                  label: Text('common.retry'.tr),
                ),
              ],
            ),
          );
        }
        if (controller.galleries.isEmpty) {
          return Column(
            children: [
              _buildScanProgress(),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('local.noGalleries'.tr),
                      const SizedBox(height: 8),
                      Text(
                        'local.helpText'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text('local.scanNow'.tr),
                        onPressed: controller.refreshGalleries,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildSearchField(),
            _buildScanProgress(),
            Expanded(child: _buildGalleryList(context)),
          ],
        );
      }),
    );
  }

  Widget _buildScanProgress() {
    return Obx(() {
      final progress = controller.scanProgress.value;
      if (!controller.isScanning.value || progress == null) {
        return const SizedBox.shrink();
      }
      final theme = Get.theme;
      final elapsed = _formatDuration(progress.elapsedMs);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'local.scanProgress'.trParams({
                  'count': '${progress.foundCount}',
                  'elapsed': elapsed,
                }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes}m ${remainder}s';
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: controller.searchTextController,
        decoration: InputDecoration(
          hintText: 'home.search'.tr,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Obx(() => controller.searchQuery.value.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: controller.clearSearchQuery,
                )),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: controller.updateSearchQuery,
      ),
    );
  }

  void _copyLocalPath(String path) {
    if (path.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: path));
    Get.snackbar('hasCopiedToClipboard'.tr, path,
        snackPosition: SnackPosition.BOTTOM);
  }

  Widget _buildGalleryList(BuildContext context) {
    return Obx(() {
      if (!controller.isSearching) {
        return _buildDirectoryBrowser(context);
      }

      if (controller.viewMode.value == 'grid') {
        final items = controller.filteredGalleries;
        if (items.isEmpty) {
          return Center(child: Text('home.noGalleries'.tr));
        }
        return _buildGalleryGrid(context, items);
      }

      final groups = controller.groupedGalleries;
      if (groups.isEmpty) {
        return Center(child: Text('home.noGalleries'.tr));
      }
      return ListView(
        controller: controller.scrollController,
        padding: const EdgeInsets.all(8),
        children: [
          for (final entry in groups.entries)
            _buildGalleryGroup(context, entry.key, entry.value),
        ],
      );
    });
  }

  Widget _buildDirectoryBrowser(BuildContext context) {
    final dirs = controller.childDirectories;
    final galleries = controller.currentDirectoryGalleries;
    final currentPath = controller.currentPath.value;

    if (dirs.isEmpty && galleries.isEmpty) {
      return Center(child: Text('home.noGalleries'.tr));
    }

    if (controller.viewMode.value == 'grid') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (currentPath.isNotEmpty)
            _buildCurrentDirectoryHeader(context, currentPath),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = WebLocalController.gridColumns ??
                  (width > 1100
                      ? 6
                      : width > 850
                          ? 5
                          : width > 650
                              ? 4
                              : width > 420
                                  ? 3
                                  : 2);
              return GridView(
                controller: controller.scrollController,
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                children: [
                  if (currentPath.isNotEmpty)
                    _buildDirectoryGridTile(
                      context,
                      title: 'local.parentDirectory'.tr,
                      subtitle: WebLocalController._parentPath(currentPath),
                      icon: Icons.keyboard_return,
                      onTap: controller.goUpDirectory,
                    ),
                  for (final dir in dirs)
                    _buildDirectoryGridTile(
                      context,
                      title: WebLocalController._displayPath(dir),
                      subtitle: dir,
                      icon: controller.roots.contains(dir)
                          ? Icons.folder_special
                          : Icons.folder_open,
                      onTap: () => controller.enterDirectory(dir),
                    ),
                  for (final gallery in galleries)
                    _buildGalleryGridTile(context, gallery),
                ],
              );
            }),
          ),
        ],
      );
    }

    return ListView(
      controller: controller.scrollController,
      padding: const EdgeInsets.all(8),
      children: [
        if (currentPath.isNotEmpty)
          _buildCurrentDirectoryHeader(context, currentPath),
        if (currentPath.isNotEmpty)
          _buildDirectoryTile(
            context,
            title: 'local.parentDirectory'.tr,
            subtitle: WebLocalController._parentPath(currentPath),
            icon: Icons.keyboard_return,
            onTap: controller.goUpDirectory,
          ),
        for (final dir in dirs)
          _buildDirectoryTile(
            context,
            title: WebLocalController._displayPath(dir),
            subtitle: dir,
            icon: controller.roots.contains(dir)
                ? Icons.folder_special
                : Icons.folder_open,
            onTap: () => controller.enterDirectory(dir),
          ),
        for (final gallery in galleries) _buildGalleryTile(context, gallery),
      ],
    );
  }

  Widget _buildCurrentDirectoryHeader(BuildContext context, String path) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildDirectoryTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDirectoryGridTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 46, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryGroup(
    BuildContext context,
    String group,
    List<Map<String, dynamic>> galleries,
  ) {
    final expanded = controller.groupExpanded[group] ?? true;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(expanded ? Icons.folder_open : Icons.folder),
            title: Text(
              WebLocalController._displayPath(group),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(group, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text('${galleries.length}'),
            onTap: () => controller.toggleGroup(group),
          ),
          if (expanded)
            for (final gallery in galleries)
              _buildGalleryTile(context, gallery),
        ],
      ),
    );
  }

  Widget _buildGalleryTile(BuildContext context, Map<String, dynamic> gallery) {
    return GestureDetector(
      onLongPressStart: (details) =>
          _showLocalGalleryMenu(context, details.globalPosition, gallery),
      onSecondaryTapUp: (details) =>
          _showLocalGalleryMenu(context, details.globalPosition, gallery),
      child: ListTile(
        leading: _buildGalleryCover(gallery),
        title: Text(
          gallery['title'] as String? ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('common.images'
            .trParams({'count': '${gallery['imageCount'] ?? 0}'})),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'common.delete'.tr,
              onPressed: () => _confirmDeleteLocalGallery(context, gallery),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.menu_book),
          ],
        ),
        onTap: () => controller.openGallery(gallery),
      ),
    );
  }

  Widget _buildGalleryGrid(
      BuildContext context, List<Map<String, dynamic>> items) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = WebLocalController.gridColumns ??
          (width > 1200
              ? 6
              : width > 900
                  ? 5
                  : width > 680
                      ? 4
                      : width > 460
                          ? 3
                          : 2);
      return GridView.builder(
        controller: controller.scrollController,
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 0.62,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            _buildGalleryGridTile(context, items[index]),
      );
    });
  }

  Widget _buildGalleryGridTile(
      BuildContext context, Map<String, dynamic> gallery) {
    final title = gallery['title'] as String? ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onLongPressStart: (details) =>
            _showLocalGalleryMenu(context, details.globalPosition, gallery),
        onSecondaryTapUp: (details) =>
            _showLocalGalleryMenu(context, details.globalPosition, gallery),
        child: InkWell(
          onTap: () => controller.openGallery(gallery),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildGalleryCoverLarge(context, gallery)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'common.images'.trParams(
                            {'count': '${gallery['imageCount'] ?? 0}'}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'common.delete'.tr,
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _confirmDeleteLocalGallery(context, gallery),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocalGalleryMenu(
    BuildContext context,
    Offset position,
    Map<String, dynamic> gallery,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'read',
          child: ListTile(
            leading: const Icon(Icons.menu_book, size: 20),
            title: Text('downloads.read'.tr),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'copyPath',
          child: ListTile(
            leading: const Icon(Icons.copy, size: 20),
            title: Text('local.copyPath'.tr),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading:
                const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text('common.delete'.tr),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'read':
          controller.openGallery(gallery);
          break;
        case 'copyPath':
          final path = gallery['path']?.toString() ?? '';
          _copyLocalPath(path);
          break;
        case 'delete':
          _confirmDeleteLocalGallery(context, gallery);
          break;
      }
    });
  }

  Widget _buildGalleryCover(Map<String, dynamic> gallery) {
    final coverPath = gallery['coverPath'] as String? ?? '';
    if (coverPath.isEmpty) {
      return const SizedBox(
        width: 52,
        height: 72,
        child: Icon(Icons.photo_library, size: 40),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: WebProxiedImage(
        sourceUrl: backendApiClient.imageFileUrl(coverPath),
        width: 52,
        height: 72,
        fit: BoxFit.cover,
        errorIconSize: 32,
      ),
    );
  }

  Widget _buildGalleryCoverLarge(
      BuildContext context, Map<String, dynamic> gallery) {
    final coverPath = gallery['coverPath'] as String? ?? '';
    if (coverPath.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.photo_library, size: 48)),
      );
    }

    return WebProxiedImage(
      sourceUrl: backendApiClient.imageFileUrl(coverPath),
      fit: BoxFit.cover,
      errorIconSize: 40,
    );
  }

  Future<void> _confirmDeleteLocalGallery(
      BuildContext context, Map<String, dynamic> gallery) async {
    final title = gallery['title'] as String? ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('local.deleteTitle'.tr),
        content: Text('local.deleteConfirm'.trParams({'title': title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteGallery(gallery);
    }
  }
}
