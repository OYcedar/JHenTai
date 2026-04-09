import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebGalleryDetailController extends GetxController {
  late int gid;
  late String token;

  final title = ''.obs;
  final titleJpn = ''.obs;
  final category = ''.obs;
  final uploader = ''.obs;
  final pageCount = 0.obs;
  final rating = 0.0.obs;
  final coverUrl = ''.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final galleryUrl = ''.obs;
  final archiverUrl = ''.obs;
  final imagePageUrls = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    gid = int.tryParse(Get.parameters['gid'] ?? '') ?? 0;
    token = Get.parameters['token'] ?? '';
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchGalleryDetail(gid, token);
      title.value = result['title'] as String? ?? 'Unknown';
      titleJpn.value = result['titleJpn'] as String? ?? '';
      category.value = result['category'] as String? ?? '';
      uploader.value = result['uploader'] as String? ?? '';
      coverUrl.value = result['coverUrl'] as String? ?? '';
      rating.value = (result['rating'] as num?)?.toDouble() ?? 0;
      pageCount.value = result['pageCount'] as int? ?? 0;
      archiverUrl.value = result['archiverUrl'] as String? ?? '';
      galleryUrl.value = result['galleryUrl'] as String? ?? '';
      final pages = result['imagePageUrls'] as List?;
      imagePageUrls.value = pages?.cast<String>() ?? [];
    } catch (e) {
      errorMessage.value = 'Failed to load gallery detail: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> startGalleryDownload() async {
    try {
      await backendApiClient.startGalleryDownload(
        gid: gid,
        token: token,
        title: title.value,
        galleryUrl: galleryUrl.value,
        category: category.value,
        pageCount: pageCount.value,
        uploader: uploader.value,
      );
      Get.snackbar('Download Started', 'Gallery download has been queued',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to start download: $e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> startArchiveDownload({bool isOriginal = false}) async {
    if (archiverUrl.isEmpty) {
      Get.snackbar('Error', 'No archive available',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await backendApiClient.startArchiveDownload(
        gid: gid,
        token: token,
        title: title.value,
        galleryUrl: galleryUrl.value,
        archivePageUrl: archiverUrl.value,
        category: category.value,
        pageCount: pageCount.value,
        uploader: uploader.value,
        isOriginal: isOriginal,
      );
      Get.snackbar('Download Started', 'Archive download has been queued',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to start archive download: $e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }
}

class WebGalleryDetailPage extends GetView<WebGalleryDetailController> {
  const WebGalleryDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(
          controller.title.value,
          overflow: TextOverflow.ellipsis,
        )),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(child: Text(controller.errorMessage.value));
        }
        return _buildDetail(context);
      }),
    );
  }

  Widget _buildDetail(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Obx(() => Text(
                controller.title.value,
                style: Theme.of(context).textTheme.headlineSmall,
              )),
              if (controller.titleJpn.isNotEmpty)
                Obx(() => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    controller.titleJpn.value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                )),
              const SizedBox(height: 16),

              // Info chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Obx(() => Chip(
                    label: Text(controller.category.value),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  )),
                  Obx(() => Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(controller.uploader.value),
                  )),
                  Obx(() => Chip(
                    avatar: const Icon(Icons.photo_library, size: 16),
                    label: Text('${controller.pageCount.value} pages'),
                  )),
                  Obx(() => Chip(
                    avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                    label: Text(controller.rating.value.toStringAsFixed(1)),
                  )),
                ],
              ),
              const SizedBox(height: 24),

              // Read button
              Obx(() => controller.pageCount.value > 0
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.menu_book),
                        label: const Text('Read Online'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(200, 48),
                        ),
                        onPressed: () => Get.toNamed('/web/reader/${controller.gid}/${controller.token}'),
                      ),
                    )
                  : const SizedBox.shrink()),

              // Download buttons
              Text('Download', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download Gallery'),
                    onPressed: controller.startGalleryDownload,
                  ),
                  Obx(() => controller.archiverUrl.isNotEmpty
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.archive),
                          label: const Text('Archive (Resample)'),
                          onPressed: () => controller.startArchiveDownload(isOriginal: false),
                        )
                      : const SizedBox.shrink()),
                  Obx(() => controller.archiverUrl.isNotEmpty
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.archive_outlined),
                          label: const Text('Archive (Original)'),
                          onPressed: () => controller.startArchiveDownload(isOriginal: true),
                        )
                      : const SizedBox.shrink()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
