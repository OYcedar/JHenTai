import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebThumbnailsController extends GetxController {
  late int gid;
  late String token;

  final imagePageUrls = <String>[].obs;
  final thumbnailUrls = <String>[].obs;
  final coverUrl = ''.obs;
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

      final result = await backendApiClient.fetchGalleryImagePages(gid, token);
      final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
      imagePageUrls.value = pages;

      thumbnailUrls.value = List.generate(pages.length, (i) {
        if (i < pages.length) return pages[i];
        return '';
      });
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
            coverUrl: controller.coverUrl.value,
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
  final String coverUrl;

  const _ThumbnailCell({required this.index, required this.gid, required this.token, this.coverUrl = ''});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Get.toNamed('/web/reader/$gid/$token?startPage=$index');
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
            if (coverUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.4), BlendMode.darken),
                  child: Image.network(
                    backendApiClient.proxyImageUrl(coverUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.image, color: Colors.grey, size: 32),
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: Icon(Icons.image, color: Colors.grey, size: 32),
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
