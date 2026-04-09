import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebReaderController extends GetxController {
  late int gid;
  late String token;

  final imageUrls = <String>[].obs;
  final currentPage = 0.obs;
  final totalPages = 0.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final isFullscreen = false.obs;
  final showOverlay = true.obs;

  final _imagePageUrls = <String>[];
  final _loadedImageUrls = <int, String>{};

  late PageController pageController;

  @override
  void onInit() {
    super.onInit();
    gid = int.tryParse(Get.parameters['gid'] ?? '') ?? 0;
    token = Get.parameters['token'] ?? '';
    pageController = PageController();
    _loadGallery();
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }

  Future<void> _loadGallery() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchGalleryImagePages(gid, token);
      final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
      final total = result['totalPages'] as int? ?? pages.length;

      _imagePageUrls.clear();
      _imagePageUrls.addAll(pages);
      totalPages.value = total;
      imageUrls.value = List.filled(_imagePageUrls.length, '');

      _preloadImages(0);
    } catch (e) {
      errorMessage.value = 'Failed to load gallery: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _preloadImages(int startIndex) async {
    for (int i = startIndex; i < _imagePageUrls.length && i < startIndex + 5; i++) {
      if (_loadedImageUrls.containsKey(i)) continue;
      _loadImageAtIndex(i);
    }
  }

  Future<void> _loadImageAtIndex(int index) async {
    if (index < 0 || index >= _imagePageUrls.length) return;
    if (_loadedImageUrls.containsKey(index)) return;

    try {
      final result = await backendApiClient.proxyGet(url: _imagePageUrls[index]);
      final html = (result as Map<String, dynamic>)['data']?.toString() ?? '';

      final imgMatch = RegExp(r'id="img"[^>]+src="([^"]+)"').firstMatch(html);
      if (imgMatch != null) {
        final imageUrl = imgMatch.group(1)!;
        final proxiedUrl = backendApiClient.proxyImageUrl(imageUrl);
        _loadedImageUrls[index] = proxiedUrl;
        if (index < imageUrls.length) {
          imageUrls[index] = proxiedUrl;
        }
      }
    } catch (e) {
      debugPrint('Failed to load image $index: $e');
    }
  }

  void onPageChanged(int page) {
    currentPage.value = page;
    _preloadImages(page);
  }

  void goToPage(int page) {
    if (page >= 0 && page < totalPages.value) {
      pageController.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void nextPage() => goToPage(currentPage.value + 1);
  void prevPage() => goToPage(currentPage.value - 1);

  void toggleOverlay() {
    showOverlay.value = !showOverlay.value;
  }

  Future<void> retry() => _loadGallery();
}

class WebReaderPage extends GetView<WebReaderController> {
  const WebReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Loading gallery pages...',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          );
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(controller.errorMessage.value,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.retry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return _buildReader(context);
      }),
    );
  }

  Widget _buildReader(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space) {
            controller.nextPage();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            controller.prevPage();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Get.back();
          }
        }
      },
      child: Stack(
        children: [
          GestureDetector(
            onTap: controller.toggleOverlay,
            child: Obx(() => PageView.builder(
              controller: controller.pageController,
              itemCount: controller.totalPages.value,
              onPageChanged: controller.onPageChanged,
              itemBuilder: (context, index) => _buildPage(context, index),
            )),
          ),
          // Top overlay
          Obx(() => AnimatedOpacity(
            opacity: controller.showOverlay.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !controller.showOverlay.value,
              child: Container(
                height: kToolbarHeight + MediaQuery.of(context).padding.top,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Get.back(),
                      ),
                      Expanded(
                        child: Obx(() => Text(
                          '${controller.currentPage.value + 1} / ${controller.totalPages.value}',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          textAlign: TextAlign.center,
                        )),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
          )),
          // Bottom slider
          Obx(() => AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: controller.showOverlay.value ? 0 : -80,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 8,
                top: 8,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Obx(() => controller.totalPages.value > 1
                  ? Slider(
                      value: controller.currentPage.value.toDouble(),
                      min: 0,
                      max: (controller.totalPages.value - 1).toDouble(),
                      divisions: controller.totalPages.value - 1,
                      label: '${controller.currentPage.value + 1}',
                      onChanged: (v) => controller.goToPage(v.round()),
                    )
                  : const SizedBox.shrink()),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    return Obx(() {
      final url = index < controller.imageUrls.length ? controller.imageUrls[index] : '';
      if (url.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 12),
              Text('Loading image...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        );
      }
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              final total = loadingProgress.expectedTotalBytes;
              final progress = total != null
                  ? loadingProgress.cumulativeBytesLoaded / total
                  : null;
              return Center(
                child: CircularProgressIndicator(
                  value: progress,
                  color: Colors.white54,
                ),
              );
            },
            errorBuilder: (_, error, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  const SizedBox(height: 8),
                  Text('Failed to load image',
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      controller._loadedImageUrls.remove(index);
                      controller.imageUrls[index] = '';
                      controller._loadImageAtIndex(index);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
