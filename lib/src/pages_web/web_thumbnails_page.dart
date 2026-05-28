import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_eh_thumbnail.dart';
import 'package:web/web.dart' as web;

Map<String, dynamic> _thumbMapForThumbsPage(
    WebThumbnailsController c, int index) {
  if (index < c.galleryThumbnails.length) {
    return Map<String, dynamic>.from(c.galleryThumbnails[index]);
  }
  if (index < c.thumbnailImageUrls.length) {
    final u = c.thumbnailImageUrls[index];
    if (u.isNotEmpty) {
      return {'thumbUrl': u, 'isLarge': true};
    }
  }
  final cover = c.coverUrl.value;
  if (cover.isNotEmpty) {
    return {'thumbUrl': cover, 'isLarge': true};
  }
  return {'thumbUrl': '', 'isLarge': true};
}

int? _webDetailThumbnailColumnsSetting() {
  final raw =
      web.window.localStorage.getItem('jh_web_detail_thumbnail_columns');
  final value = int.tryParse(raw ?? '');
  return value != null && value >= 2 && value <= 8 ? value : null;
}

class WebThumbnailsController extends GetxController {
  late int gid;
  late String token;

  final imagePageUrls = <String>[].obs;
  final thumbnailImageUrls = <String>[].obs;
  final galleryThumbnails = <Map<String, dynamic>>[].obs;
  final coverUrl = ''.obs;
  final galleryTitle = ''.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final scrollController = ScrollController();

  int? _initialPageNo;
  int _crossAxisCount = 3;
  double _rowExtent = 0;

  @override
  void onInit() {
    super.onInit();
    gid = int.tryParse(Get.parameters['gid'] ?? '') ?? 0;
    token = Get.parameters['token'] ?? '';
    _initialPageNo = _readInitialPageNo();
    _load();
  }

  int? _readInitialPageNo() {
    final uri = Uri.parse(Uri.base.toString());
    final raw = uri.queryParameters['page'] ?? Get.parameters['page'];
    final value = int.tryParse(raw ?? '');
    return value != null && value > 0 ? value : null;
  }

  Future<void> _load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final detail = await backendApiClient.fetchGalleryDetail(gid, token);
      coverUrl.value = detail['coverUrl'] as String? ?? '';
      galleryTitle.value = detail['title'] as String? ?? '';

      final result = await backendApiClient.fetchGalleryImagePages(gid, token);
      final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
      imagePageUrls.value = pages;
      final thumbs =
          (result['thumbnailImageUrls'] as List?)?.cast<String>() ?? [];
      thumbnailImageUrls.value = thumbs.length == pages.length
          ? thumbs
          : List<String>.filled(pages.length, '');
      final gt = result['galleryThumbnails'] as List?;
      if (gt != null && gt.length == pages.length) {
        galleryThumbnails.value =
            gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (gt != null) {
        galleryThumbnails.value =
            gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        galleryThumbnails.value = [];
      }
    } catch (e) {
      errorMessage.value = 'thumbnails.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
      final pageNo = _initialPageNo;
      if (pageNo != null) {
        _initialPageNo = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToPageNo(pageNo);
        });
      }
    }
  }

  Future<void> retry() => _load();

  void updateGridMetrics({
    required int crossAxisCount,
    required double rowExtent,
  }) {
    _crossAxisCount = math.max(1, crossAxisCount);
    _rowExtent = math.max(0, rowExtent);
  }

  Future<void> scrollToPageNo(int pageNo) async {
    if (!scrollController.hasClients || imagePageUrls.isEmpty) {
      return;
    }
    final pageIndex = (pageNo - 1).clamp(0, imagePageUrls.length - 1);
    final rowIndex = pageIndex ~/ _crossAxisCount;
    final rawOffset = rowIndex * _rowExtent;
    final offset = rawOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );
    await scrollController.animateTo(
      offset.toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}

class WebThumbnailsPage extends GetView<WebThumbnailsController> {
  const WebThumbnailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text('thumbnails.title'
            .trParams({'count': '${controller.imagePageUrls.length}'}))),
        actions: [
          Obx(
            () => IconButton(
              tooltip: 'thumbnails.jumpToPage'.tr,
              icon: const Icon(Icons.near_me_outlined),
              onPressed: controller.imagePageUrls.isEmpty
                  ? null
                  : () => _showJumpDialog(context),
            ),
          ),
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
                Text(controller.errorMessage.value),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: controller.retry,
                    child: Text('common.retry'.tr)),
              ],
            ),
          );
        }
        return _buildGrid(context);
      }),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const padding = 8.0;
      const spacing = 6.0;
      const childAspectRatio = 0.7;
      final configuredColumns = _webDetailThumbnailColumnsSetting();
      final crossAxisCount = configuredColumns ??
          (constraints.maxWidth > 1200
              ? 8
              : constraints.maxWidth > 800
                  ? 6
                  : constraints.maxWidth > 500
                      ? 4
                      : 3);
      final usableWidth = math.max(0.0,
          constraints.maxWidth - padding * 2 - spacing * (crossAxisCount - 1));
      final tileWidth = usableWidth / crossAxisCount;
      controller.updateGridMetrics(
        crossAxisCount: crossAxisCount,
        rowExtent: tileWidth / childAspectRatio + spacing,
      );

      return GridView.builder(
        controller: controller.scrollController,
        padding: const EdgeInsets.all(padding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        itemCount: controller.imagePageUrls.length,
        itemBuilder: (context, index) {
          return Obx(() => _ThumbnailCell(
                index: index,
                gid: controller.gid,
                token: controller.token,
                galleryTitle: controller.galleryTitle.value,
                thumbData: _thumbMapForThumbsPage(controller, index),
              ));
        },
      );
    });
  }

  Future<void> _showJumpDialog(BuildContext context) async {
    final textController = TextEditingController();
    final total = controller.imagePageUrls.length;

    try {
      final pageNo = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('thumbnails.jumpToPage'.tr),
            content: TextField(
              controller: textController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'thumbnails.pageRange'.trParams({'total': '$total'}),
              ),
              onSubmitted: (value) {
                final pageNo = int.tryParse(value);
                if (pageNo != null) {
                  Navigator.of(context).pop(pageNo);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.cancel'.tr),
              ),
              FilledButton(
                onPressed: () {
                  final pageNo = int.tryParse(textController.text);
                  if (pageNo != null) {
                    Navigator.of(context).pop(pageNo);
                  }
                },
                child: Text('common.ok'.tr),
              ),
            ],
          );
        },
      );
      if (pageNo != null) {
        await controller.scrollToPageNo(pageNo);
      }
    } finally {
      textController.dispose();
    }
  }
}

class _ThumbnailCell extends StatelessWidget {
  final int index;
  final int gid;
  final String token;
  final String galleryTitle;
  final Map<String, dynamic> thumbData;

  const _ThumbnailCell({
    required this.index,
    required this.gid,
    required this.token,
    required this.galleryTitle,
    required this.thumbData,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final parts = <String>['startPage=$index'];
        final t = galleryTitle.trim();
        if (t.isNotEmpty) {
          parts.add('title=${Uri.encodeQueryComponent(t)}');
        }
        Get.toNamed('/web/reader/$gid/$token?${parts.join('&')}');
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebEhThumbnail(
              data: thumbData,
              height: double.infinity,
              width: double.infinity,
              borderRadius: BorderRadius.circular(6),
            ),
            Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(6)),
                ),
                child: Text(
                  'P${index + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
