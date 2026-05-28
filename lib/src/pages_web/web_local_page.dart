import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';

class WebLocalController extends GetxController {
  final searchTextController = TextEditingController();
  final galleries = <Map<String, dynamic>>[].obs;
  final searchQuery = ''.obs;
  final groupExpanded = <String, bool>{}.obs;
  final isLoading = true.obs;
  final isScanning = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
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
      final data = await backendApiClient.listLocalGalleries();
      galleries.value = data.cast<Map<String, dynamic>>();
      for (final group in groupedGalleries.keys) {
        groupExpanded.putIfAbsent(group, () => true);
      }
    } catch (e) {
      errorMessage.value = 'local.loadListFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() async {
    isScanning.value = true;
    try {
      await backendApiClient.refreshLocalGalleries();
      await Future.delayed(const Duration(seconds: 2));
      await _loadGalleries();
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
      ..sort((a, b) => _displayPath(a).compareTo(_displayPath(b)));
    return {
      for (final key in sortedKeys)
        key: (groups[key]!
          ..sort((a, b) => (a['title']?.toString() ?? '')
              .toLowerCase()
              .compareTo((b['title']?.toString() ?? '').toLowerCase())))
    };
  }

  void toggleGroup(String group) {
    groupExpanded[group] = !(groupExpanded[group] ?? true);
    groupExpanded.refresh();
  }

  static String _parentPath(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return normalized;
    return normalized.substring(0, index);
  }

  static String _displayPath(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return '/';
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return normalized;
    final tail = parts.length >= 2
        ? '${parts[parts.length - 2]}/${parts.last}'
        : parts.last;
    return tail;
  }
}

class WebLocalPage extends GetView<WebLocalController> {
  const WebLocalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('local.title'.tr),
        actions: [
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
                  onPressed: controller.refresh)),
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
                  onPressed: () => controller.refresh(),
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
                  onPressed: controller.refresh,
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
