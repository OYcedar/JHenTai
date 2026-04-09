import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final tags = <String, List<String>>{}.obs;
  final comments = <Map<String, dynamic>>[].obs;

  final favoriteSlot = Rxn<int>();
  final favoriteName = Rxn<String>();
  final isFavLoading = false.obs;

  int? apiuid;
  String? apikey;

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

      final rawTags = result['tags'] as Map<String, dynamic>?;
      if (rawTags != null) {
        tags.value = rawTags.map((k, v) => MapEntry(k, (v as List).cast<String>()));
      }

      apiuid = result['apiuid'] as int?;
      apikey = result['apikey'] as String?;

      favoriteSlot.value = result['favoriteSlot'] as int?;
      favoriteName.value = result['favoriteName'] as String?;

      final rawComments = result['comments'] as List?;
      if (rawComments != null) {
        comments.value = rawComments.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      errorMessage.value = 'detail.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleFavorite(int? favcat) async {
    isFavLoading.value = true;
    try {
      if (favoriteSlot.value != null && favcat == null) {
        await backendApiClient.removeFavorite(gid, token);
        favoriteSlot.value = null;
        favoriteName.value = null;
        Get.snackbar('detail.favRemoved'.tr, 'detail.favRemovedMsg'.tr, snackPosition: SnackPosition.BOTTOM);
      } else {
        final slot = favcat ?? 0;
        await backendApiClient.addFavorite(gid, token, favcat: slot);
        favoriteSlot.value = slot;
        final slotName = 'detail.favSlot'.trParams({'n': '$slot'});
        favoriteName.value = slotName;
        Get.snackbar('detail.favAdded'.tr, 'detail.favAddedMsg'.trParams({'name': slotName}), snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      Get.snackbar('common.error'.tr, 'detail.favError'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      isFavLoading.value = false;
    }
  }

  Future<void> submitRating(double newRating) async {
    if (apiuid == null || apikey == null) {
      Get.snackbar('common.error'.tr, 'detail.rateLoginRequired'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final result = await backendApiClient.rateGallery(
        gid: gid,
        token: token,
        apiuid: apiuid!,
        apikey: apikey!,
        rating: newRating,
      );
      final avg = result['rating_avg'] as num?;
      if (avg != null) rating.value = avg.toDouble();
      Get.snackbar('detail.rated'.tr, 'detail.ratedMsg'.trParams({'rating': newRating.toStringAsFixed(1)}), snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, 'detail.rateFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
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
        coverUrl: coverUrl.value,
        uploader: uploader.value,
      );
      Get.snackbar('detail.downloadStarted'.tr, 'detail.galleryQueued'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, 'detail.downloadFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> startArchiveDownload({bool isOriginal = false}) async {
    if (archiverUrl.isEmpty) {
      Get.snackbar('common.error'.tr, 'detail.noArchive'.tr, snackPosition: SnackPosition.BOTTOM);
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
        coverUrl: coverUrl.value,
        uploader: uploader.value,
        isOriginal: isOriginal,
      );
      Get.snackbar('detail.downloadStarted'.tr, 'detail.archiveQueued'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, 'detail.archiveFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  static String favSlotName(int i) => 'detail.favSlot'.trParams({'n': '$i'});
}

class WebGalleryDetailPage extends GetView<WebGalleryDetailController> {
  const WebGalleryDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.title.value, overflow: TextOverflow.ellipsis)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'detail.copyUrl'.tr,
            onPressed: () {
              final url = 'https://e-hentai.org/g/${controller.gid}/${controller.token}/';
              Clipboard.setData(ClipboardData(text: url));
              Get.snackbar('detail.copied'.tr, url, snackPosition: SnackPosition.BOTTOM);
            },
          ),
          Obx(() {
            if (controller.isFavLoading.value) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final isFav = controller.favoriteSlot.value != null;
            return IconButton(
              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? _favSlotColor(controller.favoriteSlot.value ?? 0) : null),
              tooltip: isFav ? 'detail.removeFromFav'.tr : 'detail.addToFav'.tr,
              onPressed: () {
                if (isFav) {
                  controller.toggleFavorite(null);
                } else {
                  _showFavoritePicker(context);
                }
              },
            );
          }),
        ],
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

  void _showFavoritePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('detail.addToFavTitle'.tr),
        children: List.generate(10, (i) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              controller.toggleFavorite(i);
            },
            child: Row(
              children: [
                Icon(Icons.favorite, size: 18, color: _favSlotColor(i)),
                const SizedBox(width: 12),
                Text('detail.favSlot'.trParams({'n': '$i'})),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide)
                _buildWideHeader(context)
              else
                _buildNarrowHeader(context),
              const SizedBox(height: 20),
              _buildActionButtons(context),
              const SizedBox(height: 24),
              _buildTags(context),
              const SizedBox(height: 24),
              _buildComments(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(context, width: 220, height: 310),
        const SizedBox(width: 20),
        Expanded(child: _buildMetadata(context)),
      ],
    );
  }

  Widget _buildNarrowHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _buildCover(context, width: 200, height: 280)),
        const SizedBox(height: 16),
        _buildMetadata(context),
      ],
    );
  }

  Widget _buildCover(BuildContext context, {required double width, required double height}) {
    return Obx(() {
      final url = controller.coverUrl.value;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          height: height,
          child: url.isNotEmpty
              ? Image.network(
                  backendApiClient.proxyImageUrl(url),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.photo_library, size: 48, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.photo_library, size: 48, color: Colors.grey),
                ),
        ),
      );
    });
  }

  Widget _buildMetadata(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => Text(controller.title.value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
        if (controller.titleJpn.isNotEmpty)
          Obx(() => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(controller.titleJpn.value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
          )),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Obx(() => _CategoryChip(category: controller.category.value)),
            Obx(() => Chip(
              avatar: const Icon(Icons.person, size: 16),
              label: Text(controller.uploader.value),
              visualDensity: VisualDensity.compact,
            )),
            Obx(() => Chip(
              avatar: const Icon(Icons.photo_library, size: 16),
              label: Text('common.pages'.trParams({'count': '${controller.pageCount.value}'})),
              visualDensity: VisualDensity.compact,
            )),
            Obx(() => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showRatingDialog(context),
              child: Chip(
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                label: Text(controller.rating.value.toStringAsFixed(1)),
                visualDensity: VisualDensity.compact,
              ),
            )),
            Obx(() {
              final fav = controller.favoriteName.value;
              if (fav == null) return const SizedBox.shrink();
              return Chip(
                avatar: Icon(Icons.favorite, size: 16, color: _favSlotColor(controller.favoriteSlot.value ?? 0)),
                label: Text(fav),
                visualDensity: VisualDensity.compact,
              );
            }),
          ],
        ),
      ],
    );
  }

  void _showRatingDialog(BuildContext context) {
    double selected = controller.rating.value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('detail.rateTitle'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starVal = (i + 1).toDouble();
                  final halfVal = i + 0.5;
                  return GestureDetector(
                    onTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        final localX = details.localPosition.dx;
                        setState(() => selected = localX < 16 ? halfVal : starVal);
                      }
                    },
                    onTap: () => setState(() => selected = starVal),
                    child: Icon(
                      selected >= starVal
                          ? Icons.star
                          : selected >= halfVal
                              ? Icons.star_half
                              : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text('${selected.toStringAsFixed(1)} / 5.0'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                controller.submitRating(selected);
              },
              child: Text('detail.rateSubmit'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        Obx(() => controller.pageCount.value > 0
            ? FilledButton.icon(
                icon: const Icon(Icons.menu_book),
                label: Text('detail.readOnline'.tr),
                style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                onPressed: () => Get.toNamed('/web/reader/${controller.gid}/${controller.token}'),
              )
            : const SizedBox.shrink()),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.download),
          label: Text('detail.downloadGallery'.tr),
          style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
          onPressed: controller.startGalleryDownload,
        ),
        Obx(() => controller.archiverUrl.isNotEmpty
            ? OutlinedButton.icon(
                icon: const Icon(Icons.archive),
                label: Text('detail.archiveResample'.tr),
                onPressed: () => controller.startArchiveDownload(isOriginal: false),
              )
            : const SizedBox.shrink()),
        Obx(() => controller.archiverUrl.isNotEmpty
            ? OutlinedButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: Text('detail.archiveOriginal'.tr),
                onPressed: () => controller.startArchiveDownload(isOriginal: true),
              )
            : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildTags(BuildContext context) {
    return Obx(() {
      if (controller.tags.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('detail.tags'.tr, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...controller.tags.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _namespaceColor(entry.key),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: entry.value.map((tag) => ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () {
                          final query = '${entry.key}:"$tag\$"';
                          Get.toNamed('/web/home', arguments: {'search': query});
                        },
                      )).toList(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    });
  }

  Widget _buildComments(BuildContext context) {
    return Obx(() {
      if (controller.comments.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('detail.comments'.trParams({'count': '${controller.comments.length}'}),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...controller.comments.map((c) => _CommentCard(comment: c)),
        ],
      );
    });
  }
}

class _CommentCard extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    final author = comment['author'] as String? ?? 'detail.anonymous'.tr;
    final date = comment['date'] as String? ?? '';
    final score = comment['score'] as String? ?? '';
    final body = comment['body'] as String? ?? '';
    final plainBody = body
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(author, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (score.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: score.startsWith('-') ? Colors.red.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(score, style: TextStyle(
                      fontSize: 12,
                      color: score.startsWith('-') ? Colors.red.shade800 : Colors.green.shade800,
                    )),
                  ),
              ],
            ),
            if (date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(date, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
            const SizedBox(height: 8),
            SelectableText(plainBody, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _categoryColor(category),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(category,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

Color _categoryColor(String category) {
  return switch (category.toLowerCase()) {
    'doujinshi' => Colors.red.shade700,
    'manga' => Colors.orange.shade700,
    'artist cg' => Colors.amber.shade700,
    'game cg' => Colors.green.shade700,
    'western' => Colors.teal.shade700,
    'non-h' => Colors.blue.shade700,
    'image set' => Colors.indigo.shade700,
    'cosplay' => Colors.purple.shade700,
    'asian porn' => Colors.pink.shade700,
    'misc' => Colors.grey.shade700,
    _ => Colors.grey.shade700,
  };
}

Color _namespaceColor(String namespace) {
  return switch (namespace.toLowerCase()) {
    'artist' => Colors.deepPurple,
    'group' || 'circle' => Colors.teal,
    'parody' => Colors.orange,
    'character' => Colors.green,
    'female' => Colors.pink,
    'male' => Colors.blue,
    'language' => Colors.brown,
    'reclass' => Colors.red,
    'other' => Colors.grey,
    _ => Colors.grey.shade600,
  };
}

Color _favSlotColor(int slot) {
  const colors = [
    Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.teal,
    Colors.blue, Colors.indigo, Colors.purple, Colors.pink, Colors.brown,
  ];
  return colors[slot % colors.length];
}
