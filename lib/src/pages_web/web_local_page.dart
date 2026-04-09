import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebLocalController extends GetxController {
  final galleries = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final isScanning = false.obs;
  final selectedImages = <String>[].obs;
  final selectedGalleryTitle = ''.obs;
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
      errorMessage.value = 'Failed to load local galleries: $e';
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
    selectedGalleryTitle.value = gallery['title'] as String? ?? '';
    final path = gallery['path'] as String? ?? '';
    try {
      final images = await backendApiClient.getLocalGalleryImages(path);
      selectedImages.value = images;
      Get.toNamed('/web/local/viewer');
    } catch (e) {
      Get.snackbar('Error', 'Failed to load gallery images: $e',
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
        title: const Text('Local Galleries'),
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
                  label: const Text('Retry'),
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
                const Text('No local galleries found'),
                const SizedBox(height: 8),
                const Text(
                  'Mount directories into the Docker container\nor place galleries in the local_gallery folder',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan Now'),
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
            subtitle: Text('${gallery['imageCount'] ?? 0} images'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => controller.openGallery(gallery),
          ),
        );
      },
    ));
  }
}

class WebLocalViewerPage extends GetView<WebLocalController> {
  const WebLocalViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.selectedGalleryTitle.value)),
      ),
      body: Obx(() {
        if (controller.selectedImages.isEmpty) {
          return const Center(child: Text('No images'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            childAspectRatio: 0.75,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: controller.selectedImages.length,
          itemBuilder: (context, index) {
            final imagePath = controller.selectedImages[index];
            final imageUrl = backendApiClient.imageFileUrl(imagePath);
            return InkWell(
              onTap: () => _showFullImage(context, index),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
              ),
            );
          },
        );
      }),
    );
  }

  void _showFullImage(BuildContext context, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => _FullImageDialog(
        images: controller.selectedImages,
        initialIndex: initialIndex,
      ),
    );
  }
}

class _FullImageDialog extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullImageDialog({required this.images, required this.initialIndex});

  @override
  State<_FullImageDialog> createState() => _FullImageDialogState();
}

class _FullImageDialogState extends State<_FullImageDialog> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_currentPage + 1} / ${widget.images.length}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemBuilder: (context, index) {
            final imageUrl = backendApiClient.imageFileUrl(widget.images[index]);
            return InteractiveViewer(
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
