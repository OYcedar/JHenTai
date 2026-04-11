import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';

class WebHistoryController extends GetxController {
  final items = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadHistory();
  }

  Future<void> loadHistory() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchHistory(limit: 100);
      items.value = ((result['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (e) {
      errorMessage.value = 'history.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteItem(int gid) async {
    await backendApiClient.deleteHistoryItem(gid);
    items.removeWhere((e) => e['gid'] == gid);
  }

  Future<void> clearAll() async {
    await backendApiClient.clearHistory();
    items.clear();
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
                Text('history.empty'.tr, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          );
        }
        return _buildList(context);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
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
      itemCount: controller.items.length,
      itemBuilder: (context, index) {
        final item = controller.items[index];
        final gid = item['gid'] as int;
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
                      readerErrorChild: const Icon(Icons.broken_image, color: Colors.grey),
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
