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

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
    _loadTasks();
    _connectWebSocket();
  }

  @override
  void onClose() {
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
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();

    try {
      final wsUrl = backendApiClient.baseUrl.replaceFirst('http', 'ws');
      _wsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/events'));
      _reconnectAttempts = 0;

      _wsSubscription = _wsChannel!.stream.listen(
        (data) => _handleWsMessage(data.toString()),
        onError: (e) {
          debugPrint('WebSocket error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = Duration(seconds: (_reconnectAttempts * 2).clamp(1, 30));
    debugPrint('WebSocket reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    Future.delayed(delay, _connectWebSocket);
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
                Text(controller.errorMessage.value,
                    textAlign: TextAlign.center),
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
    final title = task['title'] as String? ?? '';
    final status = task['status'] as int? ?? 0;
    final completed = task['completedCount'] as int? ?? 0;
    final total = task['pageCount'] as int? ?? 0;
    final progress = total > 0 ? completed / total : 0.0;
    final statusName = status < _statusNames.length ? _statusNames[status] : 'Unknown';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$statusName - $completed / $total'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 1)
              IconButton(icon: const Icon(Icons.pause), onPressed: () => controller.pauseGallery(gid)),
            if (status == 2 || status == 4)
              IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => controller.resumeGallery(gid)),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, gid),
            ),
          ],
        ),
        isThreeLine: true,
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
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteGallery(gid);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

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
    final title = task['title'] as String? ?? '';
    final status = task['status'] as int? ?? 0;
    final downloaded = task['downloadedBytes'] as int? ?? 0;
    final total = task['totalBytes'] as int? ?? 0;
    final progress = total > 0 ? downloaded / total : 0.0;
    final statusName = status < _statusNames.length ? _statusNames[status] : 'Unknown';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$statusName${total > 0 ? ' - ${_formatBytes(downloaded)} / ${_formatBytes(total)}' : ''}'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: status == 3 ? progress : null),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 3)
              IconButton(icon: const Icon(Icons.pause), onPressed: () => controller.pauseArchive(gid)),
            if (status == 7 || status == 8)
              IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => controller.resumeArchive(gid)),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, gid),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
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
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteArchive(gid);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
