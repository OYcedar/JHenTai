import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

enum ReaderMode { online, downloaded, archive, local }
enum ReadDirection { ltr, rtl, vertical }

class WebReaderController extends GetxController {
  late int gid;
  late String token;
  late ReaderMode mode;

  final imageUrls = <String>[].obs;
  final currentPage = 0.obs;
  final totalPages = 0.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final showOverlay = true.obs;
  final readDirection = ReadDirection.ltr.obs;

  final _imagePageUrls = <String>[];
  final _loadedImageUrls = <int, String>{};

  late PageController pageController;
  final scrollController = ScrollController();
  final focusNode = FocusNode();

  List<String>? localImages;

  Timer? _saveProgressTimer;

  @override
  void onInit() {
    super.onInit();
    gid = int.tryParse(Get.parameters['gid'] ?? '') ?? 0;
    token = Get.parameters['token'] ?? '';

    final modeParam = Get.parameters['mode'] ?? 'online';
    mode = switch (modeParam) {
      'downloaded' => ReaderMode.downloaded,
      'archive' => ReaderMode.archive,
      'local' => ReaderMode.local,
      _ => ReaderMode.online,
    };

    pageController = PageController();
    _loadSavedDirection();
    _loadGallery();
  }

  @override
  void onClose() {
    _saveProgressTimer?.cancel();
    _saveProgressNow();
    pageController.dispose();
    scrollController.dispose();
    focusNode.dispose();
    super.onClose();
  }

  Future<void> _loadSavedDirection() async {
    try {
      final saved = await backendApiClient.getSetting('web_read_direction');
      if (saved != null) {
        final idx = int.tryParse(saved);
        if (idx != null && idx >= 0 && idx < ReadDirection.values.length) {
          readDirection.value = ReadDirection.values[idx];
        }
      }
    } catch (_) {}
  }

  Future<void> _restoreProgress() async {
    if (gid == 0) return;
    try {
      final saved = await backendApiClient.getSetting('read_progress_$gid');
      if (saved != null) {
        final page = int.tryParse(saved) ?? 0;
        if (page > 0 && page < totalPages.value) {
          currentPage.value = page;
          if (readDirection.value == ReadDirection.vertical) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Rough scroll for vertical mode
            });
          } else {
            pageController = PageController(initialPage: page);
          }
        }
      }
    } catch (_) {}
  }

  void _scheduleSaveProgress() {
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer(const Duration(seconds: 2), _saveProgressNow);
  }

  void _saveProgressNow() {
    if (gid == 0) return;
    backendApiClient.putSetting('read_progress_$gid', currentPage.value).catchError((_) {});
  }

  Future<void> _loadGallery() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _restoreProgress();
      switch (mode) {
        case ReaderMode.online:
          await _loadOnline();
        case ReaderMode.downloaded:
          await _loadDownloaded();
        case ReaderMode.archive:
          await _loadArchive();
        case ReaderMode.local:
          _loadLocal();
      }
    } catch (e) {
      errorMessage.value = 'Failed to load gallery: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadOnline() async {
    final result = await backendApiClient.fetchGalleryImagePages(gid, token);
    final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
    final total = result['totalPages'] as int? ?? pages.length;
    _imagePageUrls.clear();
    _imagePageUrls.addAll(pages);
    totalPages.value = total;
    imageUrls.value = List.filled(_imagePageUrls.length, '');
    _preloadImages(0);
  }

  Future<void> _loadDownloaded() async {
    final filenames = await backendApiClient.getGalleryDownloadImages(gid);
    totalPages.value = filenames.length;
    imageUrls.value = filenames
        .map((f) => backendApiClient.galleryImageUrl(gid, f))
        .toList();
  }

  Future<void> _loadArchive() async {
    final filenames = await backendApiClient.getArchiveDownloadImages(gid);
    totalPages.value = filenames.length;
    imageUrls.value = filenames
        .map((f) => backendApiClient.archiveImageUrl(gid, f))
        .toList();
  }

  void _loadLocal() {
    if (localImages == null || localImages!.isEmpty) {
      errorMessage.value = 'No images provided';
      return;
    }
    totalPages.value = localImages!.length;
    imageUrls.value = localImages!
        .map((path) => backendApiClient.imageFileUrl(path))
        .toList();
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
    if (mode == ReaderMode.online) {
      _preloadImages(page);
    }
    _scheduleSaveProgress();
  }

  void goToPage(int page) {
    if (page >= 0 && page < totalPages.value) {
      if (readDirection.value == ReadDirection.vertical) {
        return;
      }
      pageController.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void nextPage() => goToPage(currentPage.value + 1);
  void prevPage() => goToPage(currentPage.value - 1);
  void toggleOverlay() => showOverlay.value = !showOverlay.value;

  void cycleReadDirection() {
    final values = ReadDirection.values;
    final next = (readDirection.value.index + 1) % values.length;
    readDirection.value = values[next];
    backendApiClient.putSetting('web_read_direction', next).catchError((_) {});
    if (values[next] != ReadDirection.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentPage.value < totalPages.value) {
          pageController = PageController(initialPage: currentPage.value);
        }
      });
    }
  }

  Future<void> retry() => _loadGallery();
}

class WebReaderPage extends StatelessWidget {
  const WebReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WebReaderController>();
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
                Text('Loading gallery...', style: TextStyle(color: Colors.white70)),
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
                    style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: controller.retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        return _ReaderBody(controller: controller);
      }),
    );
  }
}

class _ReaderBody extends StatelessWidget {
  final WebReaderController controller;
  const _ReaderBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: controller.focusNode..requestFocus(),
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
            child: Obx(() => controller.readDirection.value == ReadDirection.vertical
                ? _buildVerticalReader(context)
                : _buildPageReader(context)),
          ),
          _TopOverlay(controller: controller),
          _BottomOverlay(controller: controller),
        ],
      ),
    );
  }

  Widget _buildPageReader(BuildContext context) {
    return Obx(() => PageView.builder(
      controller: controller.pageController,
      reverse: controller.readDirection.value == ReadDirection.rtl,
      itemCount: controller.totalPages.value,
      onPageChanged: controller.onPageChanged,
      itemBuilder: (context, index) => _ImagePage(controller: controller, index: index),
    ));
  }

  Widget _buildVerticalReader(BuildContext context) {
    return Obx(() => NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0) {
            final page = (metrics.pixels / metrics.maxScrollExtent * (controller.totalPages.value - 1)).round();
            if (page != controller.currentPage.value) {
              controller.currentPage.value = page;
              if (controller.mode == ReaderMode.online) {
                controller._preloadImages(page);
              }
            }
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: controller.scrollController,
        itemCount: controller.totalPages.value,
        itemBuilder: (context, index) => _ImagePage(controller: controller, index: index, isVertical: true),
      ),
    ));
  }
}

class _ImagePage extends StatelessWidget {
  final WebReaderController controller;
  final int index;
  final bool isVertical;

  const _ImagePage({required this.controller, required this.index, this.isVertical = false});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final url = index < controller.imageUrls.length ? controller.imageUrls[index] : '';
      if (url.isEmpty) {
        return SizedBox(
          height: isVertical ? MediaQuery.of(context).size.height * 0.8 : null,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white54),
                SizedBox(height: 12),
                Text('Loading image...', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        );
      }

      final image = Image.network(
        url,
        fit: isVertical ? BoxFit.fitWidth : BoxFit.contain,
        width: isVertical ? double.infinity : null,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final total = loadingProgress.expectedTotalBytes;
          final progress = total != null ? loadingProgress.cumulativeBytesLoaded / total : null;
          return SizedBox(
            height: isVertical ? MediaQuery.of(context).size.height * 0.8 : null,
            child: Center(child: CircularProgressIndicator(value: progress, color: Colors.white54)),
          );
        },
        errorBuilder: (_, error, __) => SizedBox(
          height: isVertical ? 400 : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                const SizedBox(height: 8),
                const Text('Failed to load image', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    if (controller.mode == ReaderMode.online) {
                      controller._loadedImageUrls.remove(index);
                      controller.imageUrls[index] = '';
                      controller._loadImageAtIndex(index);
                    }
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );

      if (isVertical) return image;
      return InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Center(child: image));
    });
  }
}

class _TopOverlay extends StatelessWidget {
  final WebReaderController controller;
  const _TopOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedOpacity(
      opacity: controller.showOverlay.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !controller.showOverlay.value,
        child: Container(
          height: kToolbarHeight + MediaQuery.of(context).padding.top,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
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
                Obx(() {
                  final icon = switch (controller.readDirection.value) {
                    ReadDirection.ltr => Icons.arrow_forward,
                    ReadDirection.rtl => Icons.arrow_back,
                    ReadDirection.vertical => Icons.swap_vert,
                  };
                  final label = switch (controller.readDirection.value) {
                    ReadDirection.ltr => 'LTR',
                    ReadDirection.rtl => 'RTL',
                    ReadDirection.vertical => 'Vertical',
                  };
                  return Tooltip(
                    message: 'Reading direction: $label',
                    child: IconButton(
                      icon: Icon(icon, color: Colors.white),
                      onPressed: controller.cycleReadDirection,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _BottomOverlay extends StatelessWidget {
  final WebReaderController controller;
  const _BottomOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: controller.showOverlay.value ? 0 : -120,
      left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 16, right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 8, top: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => controller.totalPages.value > 1
                ? Slider(
                    value: controller.currentPage.value.toDouble().clamp(0, (controller.totalPages.value - 1).toDouble()),
                    min: 0,
                    max: (controller.totalPages.value - 1).toDouble(),
                    divisions: controller.totalPages.value > 1 ? controller.totalPages.value - 1 : 1,
                    label: '${controller.currentPage.value + 1}',
                    onChanged: (v) => controller.goToPage(v.round()),
                  )
                : const SizedBox.shrink()),
            _buildThumbnailStrip(),
          ],
        ),
      ),
    ));
  }

  Widget _buildThumbnailStrip() {
    return Obx(() {
      if (controller.totalPages.value <= 1) return const SizedBox.shrink();
      final maxThumbs = controller.totalPages.value.clamp(0, 20);
      final step = controller.totalPages.value > 20
          ? controller.totalPages.value / 20
          : 1.0;

      return SizedBox(
        height: 52,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: maxThumbs,
          itemBuilder: (context, i) {
            final pageIndex = (i * step).floor().clamp(0, controller.totalPages.value - 1);
            final url = pageIndex < controller.imageUrls.length ? controller.imageUrls[pageIndex] : '';
            final isActive = controller.currentPage.value == pageIndex;

            return GestureDetector(
              onTap: () => controller.goToPage(pageIndex),
              child: Container(
                width: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isActive ? Colors.white : Colors.white24,
                    width: isActive ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: url.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.network(url, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white24, size: 16)),
                      )
                    : const Center(child: Icon(Icons.image, color: Colors.white24, size: 16)),
              ),
            );
          },
        ),
      );
    });
  }
}
