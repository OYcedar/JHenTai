import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

class WebHistoryController extends GetxController {
  static const pageSize = 100;
  static const viewModeStorageKey = 'jh_web_history_view_mode';

  final items = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final errorMessage = ''.obs;
  final viewMode = 'list'.obs;

  @override
  void onInit() {
    super.onInit();
    final savedViewMode = web.window.localStorage.getItem(viewModeStorageKey);
    if (savedViewMode == 'grid' || savedViewMode == 'list') {
      viewMode.value = savedViewMode!;
    }
    loadHistory();
  }

  Future<void> loadHistory() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchHistory(limit: pageSize);
      final nextItems =
          ((result['items'] as List?) ?? []).cast<Map<String, dynamic>>();
      items.value = nextItems;
      hasMore.value = nextItems.length >= pageSize;
    } catch (e) {
      errorMessage.value = 'history.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final result = await backendApiClient.fetchHistory(
        limit: pageSize,
        offset: items.length,
      );
      final nextItems =
          ((result['items'] as List?) ?? []).cast<Map<String, dynamic>>();
      items.addAll(nextItems);
      hasMore.value = nextItems.length >= pageSize;
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'history.loadFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> deleteItem(int gid) async {
    await backendApiClient.deleteHistoryItem(gid);
    items.removeWhere((e) => e['gid'] == gid);
  }

  Future<void> clearAll() async {
    await backendApiClient.clearHistory();
    items.clear();
    hasMore.value = false;
  }

  void toggleViewMode() {
    final next = viewMode.value == 'grid' ? 'list' : 'grid';
    viewMode.value = next;
    web.window.localStorage.setItem(viewModeStorageKey, next);
  }
}

class WebHistoryPage extends GetView<WebHistoryController> {
  const WebHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('history.title'.tr),
        actions: [
          Obx(() => IconButton(
                icon: Icon(controller.viewMode.value == 'grid'
                    ? Icons.view_list
                    : Icons.grid_view),
                tooltip: 'listMode.toggle'.tr,
                onPressed: controller.toggleViewMode,
              )),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'history.clearAll'.tr,
            onPressed: () => _confirmClear(context),
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
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: controller.loadHistory,
                  label: Text('common.retry'.tr),
                ),
              ],
            ),
          );
        }
        if (controller.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('history.empty'.tr,
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          );
        }
        return controller.viewMode.value == 'grid'
            ? _buildGrid(context)
            : _buildList(context);
      }),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('history.clearTitle'.tr),
        content: Text('history.clearConfirm'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.clearAll();
            },
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: controller.items.length + (controller.hasMore.value ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= controller.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Obx(
                () => OutlinedButton.icon(
                  icon: controller.isLoadingMore.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  onPressed: controller.isLoadingMore.value
                      ? null
                      : controller.loadMore,
                  label: Text('history.loadMore'.tr),
                ),
              ),
            ),
          );
        }
        final item = controller.items[index];
        final gid = (item['gid'] as num?)?.toInt() ?? 0;
        final token = item['token'] as String? ?? '';
        final title = item['title'] as String? ?? '';
        final coverUrl = item['cover_url'] as String? ?? '';
        final category = item['category'] as String? ?? '';
        final visitTime = item['visit_time'] as String? ?? '';

        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: SizedBox(
              width: 50,
              height: 70,
              child: coverUrl.isNotEmpty
                  ? WebProxiedImage(
                      sourceUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorIconSize: 24,
                      readerErrorChild:
                          const Icon(Icons.broken_image, color: Colors.grey),
                    )
                  : const Icon(Icons.photo_library, color: Colors.grey),
            ),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${category.isNotEmpty ? '$category · ' : ''}${_formatTime(visitTime)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => controller.deleteItem(gid),
            ),
            onTap: () => Get.toNamed('/web/gallery/$gid/$token'),
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width > 1200
          ? 6
          : width > 900
              ? 5
              : width > 680
                  ? 4
                  : width > 460
                      ? 3
                      : 2;
      final itemCount =
          controller.items.length + (controller.hasMore.value ? 1 : 0);
      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 0.62,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= controller.items.length) {
            return _buildLoadMoreTile(context);
          }
          return _buildGridItem(context, controller.items[index]);
        },
      );
    });
  }

  Widget _buildLoadMoreTile(BuildContext context) {
    return Card(
      child: Center(
        child: Obx(
          () => OutlinedButton.icon(
            icon: controller.isLoadingMore.value
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            onPressed:
                controller.isLoadingMore.value ? null : controller.loadMore,
            label: Text('history.loadMore'.tr),
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, Map<String, dynamic> item) {
    final gid = (item['gid'] as num?)?.toInt() ?? 0;
    final token = item['token'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final coverUrl = item['cover_url'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final visitTime = item['visit_time'] as String? ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed('/web/gallery/$gid/$token'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildGridCover(context, coverUrl)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${category.isNotEmpty ? '$category · ' : ''}${_formatTime(visitTime)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.deleteItem(gid),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCover(BuildContext context, String coverUrl) {
    if (coverUrl.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.photo_library, size: 48)),
      );
    }
    return WebProxiedImage(
      sourceUrl: coverUrl,
      fit: BoxFit.cover,
      errorIconSize: 40,
      readerErrorChild: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
