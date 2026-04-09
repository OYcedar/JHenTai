import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebDownloadsController extends GetxController with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  final galleryTasks = <Map<String, dynamic>>[].obs;
  final archiveTasks = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
    _loadTasks();
    _connectWebSocket();
  }

  @override
  void onClose() {
    _reconnectTimer?.cancel();
    tabController.dispose();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.onClose();
  }

  Future<void> _loadTasks() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final gTasks = await backendApiClient.listGalleryDownloads();
      galleryTasks.value = gTasks.cast<Map<String, dynamic>>();

      final aTasks = await backendApiClient.listArchiveDownloads();
      archiveTasks.value = aTasks.cast<Map<String, dynamic>>();
    } catch (e) {
      errorMessage.value = 'Failed to load tasks: $e';
    } finally {
      isLoading.value = false;
    }
  }

  int _reconnectAttempts = 0;

  void _connectWebSocket() {
    if (isClosed) return;
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();

    try {
      final wsUrl = backendApiClient.baseUrl.replaceFirst('http', 'ws');
      final wsToken = backendApiClient.currentToken ?? '';
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws/events?token=$wsToken'),
      );
      _reconnectAttempts = 0;

      _wsSubscription = _wsChannel!.stream.listen(
        (data) => _handleWsMessage(data.toString()),
        onError: (e) {
          debugPrint('WebSocket error: $e');
          _scheduleReconnect();
        },
        onDone: () => _scheduleReconnect(),
      );
    } catch (e) {
      debugPrint('WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (isClosed) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: (_reconnectAttempts * 2).clamp(1, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connectWebSocket);
  }

  void _handleWsMessage(String message) {
    try {
      final event = jsonDecode(message) as Map<String, dynamic>;
      final eventType = event['event'] as String?;
      final data = event['data'] as Map<String, dynamic>?;
      if (data == null) return;

      if (eventType == 'gallery_download_progress') {
        _updateGalleryTask(data);
      } else if (eventType == 'archive_download_progress') {
        _updateArchiveTask(data);
      } else if (eventType == 'download_removed') {
        _loadTasks();
      }
    } catch (e) {
      debugPrint('WS message parse error: $e');
    }
  }

  void _updateGalleryTask(Map<String, dynamic> data) {
    final gid = data['gid'];
    final index = galleryTasks.indexWhere((t) => t['gid'] == gid);
    if (index >= 0) {
      galleryTasks[index] = data;
    } else {
      galleryTasks.insert(0, data);
    }
  }

  void _updateArchiveTask(Map<String, dynamic> data) {
    final gid = data['gid'];
    final index = archiveTasks.indexWhere((t) => t['gid'] == gid);
    if (index >= 0) {
      archiveTasks[index] = data;
    } else {
      archiveTasks.insert(0, data);
    }
  }

  Future<void> pauseGallery(int gid) => backendApiClient.pauseGalleryDownload(gid);
  Future<void> resumeGallery(int gid) => backendApiClient.resumeGalleryDownload(gid);
  Future<void> deleteGallery(int gid) => backendApiClient.deleteGalleryDownload(gid);
  Future<void> pauseArchive(int gid) => backendApiClient.pauseArchiveDownload(gid);
  Future<void> resumeArchive(int gid) => backendApiClient.resumeArchiveDownload(gid);
  Future<void> deleteArchive(int gid) => backendApiClient.deleteArchiveDownload(gid);

  Future<void> refresh() => _loadTasks();
}

class WebDownloadsPage extends GetView<WebDownloadsController> {
  const WebDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: controller.refresh),
        ],
        bottom: TabBar(
          controller: controller.tabController,
          tabs: const [
            Tab(text: 'Gallery', icon: Icon(Icons.photo_library)),
            Tab(text: 'Archive', icon: Icon(Icons.archive)),
          ],
        ),
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
                  onPressed: controller.refresh,
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return TabBarView(
          controller: controller.tabController,
          children: [
            _GalleryTaskList(controller: controller),
            _ArchiveTaskList(controller: controller),
          ],
        );
      }),
    );
  }
}

// --- Gallery Tasks ---

class _GalleryTaskList extends StatelessWidget {
  final WebDownloadsController controller;
  const _GalleryTaskList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.galleryTasks.isEmpty) {
        return const Center(child: Text('No gallery downloads'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: controller.galleryTasks.length,
        itemBuilder: (context, index) {
          final task = controller.galleryTasks[index];
          return _GalleryTaskCard(task: task, controller: controller);
        },
      );
    });
  }
}

class _GalleryTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final WebDownloadsController controller;
  const _GalleryTaskCard({required this.task, required this.controller});

  static const _statusNames = ['None', 'Downloading', 'Paused', 'Completed', 'Failed'];

  @override
  Widget build(BuildContext context) {
    final gid = task['gid'] as int;
    final token = task['token'] as String? ?? '';
    final title = task['title'] as String? ?? '';
    final category = task['category'] as String? ?? '';
    final uploader = task['uploader'] as String? ?? '';
    final coverUrl = task['coverUrl'] as String? ?? '';
    final status = task['status'] as int? ?? 0;
    final completed = task['completedCount'] as int? ?? 0;
    final total = task['pageCount'] as int? ?? 0;
    final progress = total > 0 ? completed / total : 0.0;
    final statusName = status < _statusNames.length ? _statusNames[status] : 'Unknown';
    final isCompleted = status == 3;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCompleted
            ? () => Get.toNamed('/web/reader/$gid/$token?mode=downloaded')
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            SizedBox(
              width: 80,
              height: 110,
              child: coverUrl.isNotEmpty
                  ? Image.network(
                      backendApiClient.proxyImageUrl(coverUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.photo_library, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.photo_library, color: Colors.grey),
                    ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _categoryColor(category),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(category,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (uploader.isNotEmpty)
                          Flexible(
                            child: Text(uploader,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(status: statusName, isCompleted: isCompleted),
                        const SizedBox(width: 8),
                        Text('$completed / $total', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompleted)
                  IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.green),
                    tooltip: 'Read',
                    onPressed: () => Get.toNamed('/web/reader/$gid/$token?mode=downloaded'),
                  ),
                if (status == 1)
                  IconButton(icon: const Icon(Icons.pause), tooltip: 'Pause',
                      onPressed: () => controller.pauseGallery(gid)),
                if (status == 2 || status == 4)
                  IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Resume',
                      onPressed: () => controller.resumeGallery(gid)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, gid),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, int gid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: const Text('Delete this download and its files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); controller.deleteGallery(gid); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// --- Archive Tasks ---

class _ArchiveTaskList extends StatelessWidget {
  final WebDownloadsController controller;
  const _ArchiveTaskList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.archiveTasks.isEmpty) {
        return const Center(child: Text('No archive downloads'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: controller.archiveTasks.length,
        itemBuilder: (context, index) {
          final task = controller.archiveTasks[index];
          return _ArchiveTaskCard(task: task, controller: controller);
        },
      );
    });
  }
}

class _ArchiveTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final WebDownloadsController controller;
  const _ArchiveTaskCard({required this.task, required this.controller});

  static const _statusNames = [
    'None', 'Unlocking', 'Parsing URL', 'Downloading',
    'Downloaded', 'Unpacking', 'Completed', 'Paused', 'Failed',
  ];

  @override
  Widget build(BuildContext context) {
    final gid = task['gid'] as int;
    final token = task['token'] as String? ?? '';
    final title = task['title'] as String? ?? '';
    final category = task['category'] as String? ?? '';
    final uploader = task['uploader'] as String? ?? '';
    final coverUrl = task['coverUrl'] as String? ?? '';
    final status = task['status'] as int? ?? 0;
    final downloaded = task['downloadedBytes'] as int? ?? 0;
    final total = task['totalBytes'] as int? ?? 0;
    final progress = total > 0 ? downloaded / total : 0.0;
    final statusName = status < _statusNames.length ? _statusNames[status] : 'Unknown';
    final isCompleted = status == 6;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCompleted
            ? () => Get.toNamed('/web/reader/$gid/$token?mode=archive')
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            SizedBox(
              width: 80,
              height: 110,
              child: coverUrl.isNotEmpty
                  ? Image.network(
                      backendApiClient.proxyImageUrl(coverUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.archive, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.archive, color: Colors.grey),
                    ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _categoryColor(category),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(category,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (uploader.isNotEmpty)
                          Flexible(
                            child: Text(uploader,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(status: statusName, isCompleted: isCompleted),
                        const SizedBox(width: 8),
                        if (total > 0)
                          Text('${_formatBytes(downloaded)} / ${_formatBytes(total)}',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: status == 3 ? progress : (isCompleted ? 1.0 : null)),
                  ],
                ),
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompleted)
                  IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.green),
                    tooltip: 'Read',
                    onPressed: () => Get.toNamed('/web/reader/$gid/$token?mode=archive'),
                  ),
                if (status == 3)
                  IconButton(icon: const Icon(Icons.pause), tooltip: 'Pause',
                      onPressed: () => controller.pauseArchive(gid)),
                if (status == 7 || status == 8)
                  IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Resume',
                      onPressed: () => controller.resumeArchive(gid)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, gid),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, int gid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: const Text('Delete this download and its files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); controller.deleteArchive(gid); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// --- Shared widgets ---

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isCompleted;
  const _StatusBadge({required this.status, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    final color = isCompleted
        ? Colors.green
        : status == 'Downloading' ? Colors.blue
        : status == 'Paused' ? Colors.orange
        : status == 'Failed' ? Colors.red
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
}
