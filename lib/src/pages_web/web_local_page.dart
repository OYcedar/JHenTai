import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

class WebLocalController extends GetxController {
  static const viewModeStorageKey = 'jh_web_local_view_mode';

  final searchTextController = TextEditingController();
  final galleries = <Map<String, dynamic>>[].obs;
  final roots = <String>[].obs;
  final currentPath = ''.obs;
  final searchQuery = ''.obs;
  final viewMode = 'list'.obs;
  final groupExpanded = <String, bool>{}.obs;
  final isLoading = true.obs;
  final isScanning = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    final savedViewMode = web.window.localStorage.getItem(viewModeStorageKey);
    if (savedViewMode == 'grid' || savedViewMode == 'list') {
      viewMode.value = savedViewMode!;
    }
    _loadGalleries();
  }

  @override
  void onClose() {
    searchTextController.dispose();
    super.onClose();
  }

  Future<void> _loadGalleries() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final results = await Future.wait([
        backendApiClient.listLocalGalleryRoots(),
        backendApiClient.listLocalGalleries(),
      ]);
      final rootData = (results[0] as List<String>)
          .map(_normalizePath)
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
      roots.value = rootData;

      galleries.value = results[1].cast<Map<String, dynamic>>();
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
    try {
      await backendApiClient.refreshLocalGalleries();
      await Future.delayed(const Duration(seconds: 2));
      await _loadGalleries();
      currentPath.value = '';
    } finally {
      isScanning.value = false;
    }
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
    if (path.isEmpty) return;
    try {
      await backendApiClient.deleteLocalGallery(path);
      galleries.removeWhere((item) => item['path'] == path);
      galleries.refresh();
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
    if (q.isEmpty) return galleries.toList();
    return galleries.where((gallery) {
      final title = gallery['title']?.toString().toLowerCase() ?? '';
      final path = gallery['path']?.toString().toLowerCase() ?? '';
      return title.contains(q) || path.contains(q);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> get groupedGalleries {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final gallery in filteredGalleries) {
      final path = gallery['path']?.toString() ?? '';
      final group = _parentPath(path);
      groups.putIfAbsent(group, () => []).add(gallery);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
    return {
      for (final key in sortedKeys)
        key: (groups[key]!
          ..sort((a, b) => _naturalCompare(
                a['title']?.toString() ?? '',
                b['title']?.toString() ?? '',
              )))
    };
  }

  void toggleGroup(String group) {
    groupExpanded[group] = !(groupExpanded[group] ?? true);
    groupExpanded.refresh();
  }

  void toggleViewMode() {
    final next = viewMode.value == 'grid' ? 'list' : 'grid';
    viewMode.value = next;
    web.window.localStorage.setItem(viewModeStorageKey, next);
  }

  void enterDirectory(String path) {
    currentPath.value = _normalizePath(path);
  }

  void goUpDirectory() {
    final current = currentPath.value;
    if (current.isEmpty) return;
    if (roots.contains(current)) {
      currentPath.value = '';
      return;
    }
    final parent = _parentPath(current);
    currentPath.value = _isAtOrUnderRoot(parent) ? parent : '';
  }

  List<String> get childDirectories {
    final dirs = <String>{};
    final current = currentPath.value;
    if (current.isEmpty) {
      if (roots.isNotEmpty) return roots.toList();
      dirs.addAll(
          galleries.map((g) => _topDerivedRoot(g['path']?.toString() ?? '')));
    } else {
      for (final gallery in galleries) {
        final galleryPath = _normalizePath(gallery['path']?.toString() ?? '');
        final child = _nextChildDirectory(current, galleryPath);
        if (child != null) dirs.add(child);
      }
    }
    return dirs.where((path) => path.isNotEmpty).toList()
      ..sort((a, b) => _naturalCompare(_displayPath(a), _displayPath(b)));
  }

  List<Map<String, dynamic>> get currentDirectoryGalleries {
    final current = currentPath.value;
    if (current.isEmpty) return const [];
    final items = galleries
        .where((gallery) =>
            _parentPath(gallery['path']?.toString() ?? '') == current)
        .toList();
    return items
      ..sort((a, b) => _naturalCompare(
            a['title']?.toString() ?? '',
            b['title']?.toString() ?? '',
          ));
  }

  bool _isCurrentPathStillVisible(String path) {
    if (roots.contains(path)) return true;
    return galleries.any((gallery) {
      final galleryPath = _normalizePath(gallery['path']?.toString() ?? '');
      return galleryPath == path || galleryPath.startsWith('$path/');
    });
  }

  bool _isAtOrUnderRoot(String path) {
    if (path.isEmpty) return false;
    if (roots.isEmpty) return true;
    return roots.any((root) => path == root || path.startsWith('$root/'));
  }

  static String? _nextChildDirectory(String parent, String galleryPath) {
    if (parent.isEmpty || galleryPath.isEmpty) return null;
    if (!galleryPath.startsWith('$parent/')) return null;
    final rest = galleryPath.substring(parent.length + 1);
    if (rest.isEmpty || !rest.contains('/')) return null;
    return '$parent/${rest.split('/').first}';
  }

  static String _topDerivedRoot(String path) {
    final parent = _parentPath(path);
    if (parent.isEmpty) return '';
    final parts = parent.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return parent;
    return '/${parts.take(2).join('/')}';
  }

  static String _parentPath(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return normalized;
    return normalized.substring(0, index);
  }

  static String _displayPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return '/';
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return normalized;
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
      if (aPart == bPart) continue;

      final aNum = int.tryParse(aPart);
      final bNum = int.tryParse(bPart);
      if (aNum != null && bNum != null) {
        final cmp = aNum.compareTo(bNum);
        if (cmp != 0) return cmp;
      }

      final cmp = aPart.compareTo(bPart);
      if (cmp != 0) return cmp;
    }

    return aParts.length.compareTo(bParts.length);
  }
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
                  onPressed: () => controller.refreshGalleries(),
                  label: Text('common.retry'.tr),
                ),
              ],
            ),
          );
        }
        if (controller.galleries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open, size: 64, color: Colors.grey),
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
          );
        }
        return Column(
          children: [
            _buildSearchField(),
            Expanded(child: _buildGalleryList(context)),
          ],
        );
      }),
    );
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
                  onPressed: () {
                    controller.searchTextController.clear();
                    controller.searchQuery.value = '';
                  },
                )),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => controller.searchQuery.value = value,
      ),
    );
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
              final columns = width > 1100
                  ? 6
                  : width > 850
                      ? 5
                      : width > 650
                          ? 4
                          : width > 420
                              ? 3
                              : 2;
              return GridView(
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
    return ListTile(
      leading: _buildGalleryCover(gallery),
      title: Text(
        gallery['title'] as String? ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
          'common.images'.trParams({'count': '${gallery['imageCount'] ?? 0}'})),
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
    );
  }

  Widget _buildGalleryGrid(
      BuildContext context, List<Map<String, dynamic>> items) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width > 1200
          ? 6
          : width > 900
              ? 5
              : width > 680
                  ? 4
                  : width > 460
                      ? 3
                      : 2;
      return GridView.builder(
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
                      'common.images'
                          .trParams({'count': '${gallery['imageCount'] ?? 0}'}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
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
