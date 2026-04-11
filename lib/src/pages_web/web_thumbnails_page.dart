import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_eh_thumbnail.dart';

Map<String, dynamic> _thumbMapForThumbsPage(WebThumbnailsController c, int index) {
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

  @override
  void onInit() {
    super.onInit();
    gid = int.tryParse(Get.parameters['gid'] ?? '') ?? 0;
    token = Get.parameters['token'] ?? '';
    _load();
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
      final thumbs = (result['thumbnailImageUrls'] as List?)?.cast<String>() ?? [];
      thumbnailImageUrls.value = thumbs.length == pages.length
          ? thumbs
          : List<String>.filled(pages.length, '');
      final gt = result['galleryThumbnails'] as List?;
      if (gt != null && gt.length == pages.length) {
        galleryThumbnails.value = gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (gt != null) {
        galleryThumbnails.value = gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        galleryThumbnails.value = [];
      }
    } catch (e) {
      errorMessage.value = 'thumbnails.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> retry() => _load();
}

class WebThumbnailsPage extends GetView<WebThumbnailsController> {
  const WebThumbnailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text('thumbnails.title'.trParams(
            {'count': '${controller.imagePageUrls.length}'}))),
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
                FilledButton(onPressed: controller.retry, child: Text('common.retry'.tr)),
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
      final crossAxisCount = constraints.maxWidth > 1200
          ? 8
          : constraints.maxWidth > 800
              ? 6
              : constraints.maxWidth > 500
                  ? 4
                  : 3;

      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.7,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
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
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
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
