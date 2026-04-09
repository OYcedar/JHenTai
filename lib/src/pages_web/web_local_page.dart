import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebLocalController extends GetxController {
  final galleries = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final isScanning = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadGalleries();
  }

  Future<void> _loadGalleries() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final data = await backendApiClient.listLocalGalleries();
      galleries.value = data.cast<Map<String, dynamic>>();
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
      });
    } catch (e) {
      Get.snackbar('common.error'.tr, 'local.loadFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
    }
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
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(icon: const Icon(Icons.refresh), onPressed: controller.refresh)),
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
                Text(controller.errorMessage.value, textAlign: TextAlign.center),
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
        return _buildGalleryList(context);
      }),
    );
  }

  Widget _buildGalleryList(BuildContext context) {
    return Obx(() => ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: controller.galleries.length,
      itemBuilder: (context, index) {
        final gallery = controller.galleries[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.photo_library, size: 40),
            title: Text(
              gallery['title'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('common.images'.trParams({'count': '${gallery['imageCount'] ?? 0}'})),
            trailing: const Icon(Icons.menu_book),
            onTap: () => controller.openGallery(gallery),
          ),
        );
      },
    ));
  }
}
