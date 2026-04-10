import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_eh_thumbnail.dart';
import 'package:web/web.dart' as web;

/// Same drag devices as UIConfig.scrollBehaviourWithoutScrollBarWithMouse but
/// defined here so web does not import ui_config → style_setting → drift/sqlite3.
final ScrollBehavior _webReaderStripScrollBehavior =
    const MaterialScrollBehavior().copyWith(
  dragDevices: {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  },
  scrollbars: false,
);

enum ReaderMode { online, downloaded, archive, local }
enum ReadDirection { ltr, rtl, vertical, fitWidth, doubleColumn }

class WebReaderController extends GetxController {
  late int gid;
  late String token;
  late ReaderMode mode;

  final imageUrls = <String>[].obs;
  final galleryThumbnails = <Map<String, dynamic>>[].obs;
  final currentPage = 0.obs;
  final totalPages = 0.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final showOverlay = true.obs;
  final readDirection = ReadDirection.ltr.obs;

  final isAutoMode = false.obs;
  final autoInterval = 5.0.obs;
  Timer? _autoTimer;

  final _imagePageUrls = <String>[];
  final _loadedImageUrls = <int, String>{};

  late PageController pageController;
  final scrollController = ScrollController();
  /// Horizontal thumbnail strip at bottom (mouse drag + wheel).
  final stripScrollController = ScrollController();
  final focusNode = FocusNode();

  List<String>? localImages;

  Timer? _saveProgressTimer;
  int? _startPage;

  @override
  void onInit() {
    super.onInit();
    _readWebRouteAndQueryParams();

    pageController = PageController();
    _loadSavedDirection();
    _loadGallery();
  }

  @override
  void onClose() {
    _autoTimer?.cancel();
    _saveProgressTimer?.cancel();
    _saveProgressNow();
    pageController.dispose();
    scrollController.dispose();
    stripScrollController.dispose();
    focusNode.dispose();
    super.onClose();
  }

  /// Reads `?startPage=` / `?mode=` from the browser URL; Get.parameters often omits query on Flutter Web.
  void _readWebRouteAndQueryParams() {
    final uri = Uri.parse(web.window.location.href);
    final q = uri.queryParameters;

    _startPage = int.tryParse(q['startPage'] ?? Get.parameters['startPage'] ?? '');

    final modeParam = q['mode'] ?? Get.parameters['mode'] ?? 'online';
    mode = switch (modeParam) {
      'downloaded' => ReaderMode.downloaded,
      'archive' => ReaderMode.archive,
      'local' => ReaderMode.local,
      _ => ReaderMode.online,
    };

    var gidStr = Get.parameters['gid'] ?? '';
    var tokenStr = Get.parameters['token'] ?? '';
    if (gidStr.isEmpty || tokenStr.isEmpty) {
      final segs = uri.pathSegments;
      final i = segs.indexOf('reader');
      if (i >= 0 && i + 2 < segs.length) {
        gidStr = segs[i + 1];
        tokenStr = segs[i + 2];
      }
    }
    gid = int.tryParse(gidStr) ?? 0;
    token = tokenStr;
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
    if (_startPage != null && _startPage! >= 0) {
      currentPage.value = _startPage!;
      _initPageController(_startPage!);
      return;
    }
    if (gid == 0) return;
    try {
      final saved = await backendApiClient.getSetting('read_progress_$gid');
      if (saved != null) {
        final page = int.tryParse(saved) ?? 0;
        if (page > 0 && page < totalPages.value) {
          currentPage.value = page;
          _initPageController(page);
        }
      }
    } catch (_) {}
  }

  void _initPageController(int page) {
    final dir = readDirection.value;
    if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
      return;
    }
    if (dir == ReadDirection.doubleColumn) {
      pageController = PageController(initialPage: page ~/ 2);
    } else {
      pageController = PageController(initialPage: page);
    }
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
      await _restoreProgress();
    } catch (e) {
      errorMessage.value = 'reader.loadFailed'.trParams({'error': '$e'});
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
    final gt = result['galleryThumbnails'] as List?;
    if (gt != null) {
      galleryThumbnails.value = gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      galleryThumbnails.value = [];
    }
    _preloadAround(0);
    imageUrls.refresh();
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
      errorMessage.value = 'reader.noImages'.tr;
      return;
    }
    totalPages.value = localImages!.length;
    imageUrls.value = localImages!
        .map((path) => backendApiClient.imageFileUrl(path))
        .toList();
  }

  void _preloadAround(int center) {
    if (mode != ReaderMode.online) return;
    for (int i = math.max(0, center - 1); i < _imagePageUrls.length && i <= center + 5; i++) {
      if (!_loadedImageUrls.containsKey(i)) {
        _loadImageAtIndex(i);
      }
    }
  }

  Future<void> _loadImageAtIndex(int index) async {
    if (index < 0 || index >= _imagePageUrls.length) return;
    if (_loadedImageUrls.containsKey(index)) return;

    try {
      final result = await backendApiClient.proxyGet(url: _imagePageUrls[index]);
      final html = (result as Map<String, dynamic>)['data']?.toString() ?? '';

      String? imageUrl;
      // Try multiple patterns to robustly extract the image URL
      final patterns = [
        RegExp(r'id="img"\s[^>]*src="([^"]+)"'),
        RegExp(r'src="([^"]+)"\s[^>]*id="img"'),
        RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"'),
        RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"'),
        RegExp(r'id="img"[^>]+src="([^"]+)"'),
      ];
      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          imageUrl = match.group(1);
          break;
        }
      }
      // Fallback: find any large image URL (hentai CDN pattern)
      if (imageUrl == null) {
        final cdnMatch = RegExp(r'"(https?://[^"]+\.(jpg|png|gif|webp))"', caseSensitive: false).firstMatch(html);
        if (cdnMatch != null) imageUrl = cdnMatch.group(1);
      }

      if (imageUrl != null) {
        final proxiedUrl = backendApiClient.proxyImageUrl(imageUrl);
        _loadedImageUrls[index] = proxiedUrl;
        if (index < imageUrls.length) {
          imageUrls[index] = proxiedUrl;
          imageUrls.refresh();
        }
      }
    } catch (e) {
      debugPrint('Failed to load image $index: $e');
    }
  }

  void retryImage(int index) {
    if (mode == ReaderMode.online) {
      _loadedImageUrls.remove(index);
      imageUrls[index] = '';
      imageUrls.refresh();
      _loadImageAtIndex(index);
    }
  }

  void onPageChanged(int page) {
    if (readDirection.value == ReadDirection.doubleColumn) {
      currentPage.value = (page * 2).clamp(0, totalPages.value - 1);
    } else {
      currentPage.value = page;
    }
    if (mode == ReaderMode.online) {
      _preloadAround(currentPage.value);
    }
    _scheduleSaveProgress();
  }

  void goToPage(int page) {
    if (page < 0 || page >= totalPages.value) return;
    final dir = readDirection.value;
    if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
      return;
    }
    if (dir == ReadDirection.doubleColumn) {
      pageController.animateToPage(page ~/ 2,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      pageController.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void nextPage() {
    final dir = readDirection.value;
    if (dir == ReadDirection.doubleColumn) {
      goToPage(currentPage.value + 2);
    } else {
      goToPage(currentPage.value + 1);
    }
  }

  void prevPage() {
    final dir = readDirection.value;
    if (dir == ReadDirection.doubleColumn) {
      goToPage(math.max(0, currentPage.value - 2));
    } else {
      goToPage(currentPage.value - 1);
    }
  }

  void toggleOverlay() => showOverlay.value = !showOverlay.value;

  void cycleReadDirection() {
    final values = ReadDirection.values;
    final next = (readDirection.value.index + 1) % values.length;
    readDirection.value = values[next];
    backendApiClient.putSetting('web_read_direction', next).catchError((_) {});
    final newDir = values[next];
    if (newDir != ReadDirection.vertical && newDir != ReadDirection.fitWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentPage.value < totalPages.value) {
          if (newDir == ReadDirection.doubleColumn) {
            pageController = PageController(initialPage: currentPage.value ~/ 2);
          } else {
            pageController = PageController(initialPage: currentPage.value);
          }
        }
      });
    }
  }

  void toggleAutoMode() {
    if (isAutoMode.value) {
      isAutoMode.value = false;
      _autoTimer?.cancel();
      return;
    }
    _showAutoIntervalDialog();
  }

  void _showAutoIntervalDialog() {
    double selectedInterval = autoInterval.value;
    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Auto Mode Interval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${selectedInterval.toStringAsFixed(1)}s'),
              Slider(
                value: selectedInterval,
                min: 2,
                max: 15,
                divisions: 26,
                label: '${selectedInterval.toStringAsFixed(1)}s',
                onChanged: (v) => setState(() => selectedInterval = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Get.back();
                autoInterval.value = selectedInterval;
                isAutoMode.value = true;
                _startAutoTimer();
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  void setAutoInterval(double seconds) {
    autoInterval.value = seconds;
    if (isAutoMode.value) {
      _autoTimer?.cancel();
      _startAutoTimer();
    }
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(Duration(milliseconds: (autoInterval.value * 1000).round()), (_) {
      final dir = readDirection.value;
      if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
        if (scrollController.hasClients) {
          final target = scrollController.offset + 600;
          if (target >= scrollController.position.maxScrollExtent) {
            isAutoMode.value = false;
            _autoTimer?.cancel();
            return;
          }
          scrollController.animateTo(target,
              duration: Duration(milliseconds: (autoInterval.value * 800).round()),
              curve: Curves.linear);
        }
      } else {
        if (currentPage.value >= totalPages.value - 1) {
          isAutoMode.value = false;
          _autoTimer?.cancel();
          return;
        }
        nextPage();
      }
    });
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text('reader.loading'.tr, style: const TextStyle(color: Colors.white70)),
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
                FilledButton(onPressed: controller.retry, child: Text('common.retry'.tr)),
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
            behavior: HitTestBehavior.translucent,
            onTap: controller.toggleOverlay,
            child: Obx(() {
              final dir = controller.readDirection.value;
              return switch (dir) {
                ReadDirection.vertical => _buildVerticalReader(context),
                ReadDirection.fitWidth => _buildFitWidthReader(context),
                ReadDirection.doubleColumn => _buildDoubleColumnReader(context),
                _ => _buildPageReader(context),
              };
            }),
          ),
          _TopOverlay(controller: controller),
          _BottomOverlay(controller: controller),
          Positioned(
            right: 16,
            bottom: 16,
            child: Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${controller.currentPage.value + 1} / ${controller.totalPages.value}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )),
          ),
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
      itemBuilder: (context, index) => _DoubleTapZoomImage(controller: controller, index: index),
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
                controller._preloadAround(page);
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

  Widget _buildFitWidthReader(BuildContext context) {
    return Obx(() => NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0) {
            final page = (metrics.pixels / metrics.maxScrollExtent * (controller.totalPages.value - 1)).round();
            if (page != controller.currentPage.value) {
              controller.currentPage.value = page;
              if (controller.mode == ReaderMode.online) {
                controller._preloadAround(page);
              }
            }
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: controller.scrollController,
        itemCount: controller.totalPages.value,
        itemBuilder: (context, index) => _ImagePage(controller: controller, index: index, isVertical: true, fitWidth: true),
      ),
    ));
  }

  Widget _buildDoubleColumnReader(BuildContext context) {
    final total = controller.totalPages.value;
    final pageCount = (total / 2).ceil();
    return Obx(() => PageView.builder(
      controller: controller.pageController,
      itemCount: pageCount,
      onPageChanged: controller.onPageChanged,
      itemBuilder: (context, pairIndex) {
        final leftIdx = pairIndex * 2;
        final rightIdx = leftIdx + 1;
        return Row(
          children: [
            Expanded(child: _DoubleTapZoomImage(controller: controller, index: leftIdx)),
            if (rightIdx < total)
              Expanded(child: _DoubleTapZoomImage(controller: controller, index: rightIdx))
            else
              const Expanded(child: SizedBox.shrink()),
          ],
        );
      },
    ));
  }
}

class _DoubleTapZoomImage extends StatefulWidget {
  final WebReaderController controller;
  final int index;
  const _DoubleTapZoomImage({required this.controller, required this.index});

  @override
  State<_DoubleTapZoomImage> createState() => _DoubleTapZoomImageState();
}

class _DoubleTapZoomImageState extends State<_DoubleTapZoomImage> with SingleTickerProviderStateMixin {
  final _transformationController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        if (_animation != null) _transformationController.value = _animation!.value;
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final pos = _doubleTapDetails?.localPosition ?? Offset.zero;
    if (_transformationController.value.isIdentity()) {
      final end = Matrix4.identity()
        ..translate(-pos.dx, -pos.dy)
        ..scale(2.0)
        ..translate(pos.dx, pos.dy);
      _animation = Matrix4Tween(begin: _transformationController.value, end: end).animate(_animController);
      _animController.forward(from: 0);
    } else {
      _animation = Matrix4Tween(begin: _transformationController.value, end: Matrix4.identity()).animate(_animController);
      _animController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(child: _ImageContent(controller: widget.controller, index: widget.index)),
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  final WebReaderController controller;
  final int index;
  final bool isVertical;
  final bool fitWidth;

  const _ImagePage({required this.controller, required this.index, this.isVertical = false, this.fitWidth = false});

  @override
  Widget build(BuildContext context) {
    return _ImageContent(controller: controller, index: index, isVertical: isVertical, fitWidth: fitWidth);
  }
}

class _ImageContent extends StatelessWidget {
  final WebReaderController controller;
  final int index;
  final bool isVertical;
  final bool fitWidth;

  const _ImageContent({required this.controller, required this.index, this.isVertical = false, this.fitWidth = false});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final url = index < controller.imageUrls.length ? controller.imageUrls[index] : '';
      if (url.isEmpty) {
        return SizedBox(
          height: isVertical ? MediaQuery.of(context).size.height * 0.8 : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white54),
                const SizedBox(height: 12),
                Text('reader.loadingImage'.tr, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        );
      }

      return GestureDetector(
        onLongPress: () => _showImageContextMenu(context, url),
        onSecondaryTapUp: (details) => _showImageContextMenu(context, url, position: details.globalPosition),
        child: Image.network(
          url,
          fit: (isVertical || fitWidth) ? BoxFit.fitWidth : BoxFit.contain,
          width: (isVertical || fitWidth) ? double.infinity : null,
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
                  Text('reader.imageFailed'.tr, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => controller.retryImage(index),
                    child: Text('common.retry'.tr),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  void _showImageContextMenu(BuildContext context, String url, {Offset? position}) {
    final pos = position ?? (context.findRenderObject() as RenderBox?)?.localToGlobal(const Offset(100, 100)) ?? Offset.zero;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'save', child: Text('Save Image')),
        const PopupMenuItem(value: 'reload', child: Text('Reload')),
      ],
    ).then((value) {
      if (value == 'save') {
        web.window.open(url, '_blank');
      } else if (value == 'reload') {
        controller.retryImage(index);
      }
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
                Obx(() => IconButton(
                  icon: Icon(
                    controller.isAutoMode.value ? Icons.pause_circle : Icons.play_circle,
                    color: controller.isAutoMode.value ? Colors.amber : Colors.white,
                  ),
                  tooltip: controller.isAutoMode.value ? 'reader.autoStop'.tr : 'reader.autoStart'.tr,
                  onPressed: controller.toggleAutoMode,
                )),
                IconButton(
                  icon: const Icon(Icons.grid_view, color: Colors.white),
                  tooltip: 'thumbnails.grid'.tr,
                  onPressed: () => Get.toNamed(
                      '/web/thumbnails/${controller.gid}/${controller.token}'),
                ),
                Obx(() {
                  final icon = switch (controller.readDirection.value) {
                    ReadDirection.ltr => Icons.arrow_forward,
                    ReadDirection.rtl => Icons.arrow_back,
                    ReadDirection.vertical => Icons.swap_vert,
                    ReadDirection.fitWidth => Icons.fit_screen,
                    ReadDirection.doubleColumn => Icons.view_column,
                  };
                  final label = switch (controller.readDirection.value) {
                    ReadDirection.ltr => 'reader.ltr'.tr,
                    ReadDirection.rtl => 'reader.rtl'.tr,
                    ReadDirection.vertical => 'reader.vertical'.tr,
                    ReadDirection.fitWidth => 'reader.fitWidth'.tr,
                    ReadDirection.doubleColumn => 'reader.doubleColumn'.tr,
                  };
                  return Tooltip(
                    message: 'reader.directionLabel'.trParams({'dir': label}),
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

Widget _readerStripThumb(WebReaderController controller, int pageIndex, String proxiedFullImageUrl) {
  if (pageIndex < controller.galleryThumbnails.length) {
    final m = controller.galleryThumbnails[pageIndex];
    final u = m['thumbUrl'] as String? ?? '';
    if (u.isNotEmpty) {
      return WebEhThumbnail(
        data: Map<String, dynamic>.from(m),
        height: 40,
        width: 40,
        borderRadius: BorderRadius.circular(3),
      );
    }
  }
  if (proxiedFullImageUrl.isNotEmpty) {
    return Image.network(
      proxiedFullImageUrl,
      fit: BoxFit.cover,
      width: 40,
      height: 40,
      errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white24, size: 16),
    );
  }
  return const Center(child: Icon(Icons.image, color: Colors.white24, size: 16));
}

class _BottomOverlay extends StatelessWidget {
  final WebReaderController controller;
  const _BottomOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    // AnimatedPositioned must be a direct Stack child; wrapping it outside IgnorePointer broke layout.
    return Obx(() => AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: controller.showOverlay.value ? 0 : -140,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controller.showOverlay.value,
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
            Obx(() {
              if (!controller.isAutoMode.value) return const SizedBox.shrink();
              return Row(
                children: [
                  const Icon(Icons.timer, color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text('${controller.autoInterval.value.toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: controller.autoInterval.value,
                      min: 2, max: 15, divisions: 26,
                      onChanged: controller.setAutoInterval,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                ],
              );
            }),
            _buildThumbnailStrip(),
          ],
        ),
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
        child: Listener(
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            final c = controller.stripScrollController;
            if (!c.hasClients) return;
            final delta = signal.scrollDelta.dy;
            final max = c.position.maxScrollExtent;
            c.jumpTo((c.offset + delta).clamp(0.0, max));
          },
          child: ScrollConfiguration(
            behavior: _webReaderStripScrollBehavior,
            child: ListView.builder(
              controller: controller.stripScrollController,
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
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isActive ? Colors.white : Colors.white24,
                        width: isActive ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: _readerStripThumb(controller, pageIndex, url),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}
