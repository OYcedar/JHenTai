import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebDownloadsController extends GetxController with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  final searchQuery = ''.obs;
  final selectedGroup = Rxn<String>();

  WebDownloadService get _svc => Get.find<WebDownloadService>();

  List<Map<String, dynamic>> get filteredGalleryTasks {
    var list = _svc.galleryTasks.values.toList();
    final group = selectedGroup.value;
    if (group != null) {
      list = list.where((t) => (t['group_name'] ?? t['groupName'] ?? 'default') == group).toList();
    }
    final q = searchQuery.value.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final title = (t['title'] as String? ?? '').toLowerCase();
        final uploader = (t['uploader'] as String? ?? '').toLowerCase();
        final category = (t['category'] as String? ?? '').toLowerCase();
        return title.contains(q) || uploader.contains(q) || category.contains(q);
      }).toList();
    }
    return list;
  }

  List<Map<String, dynamic>> get filteredArchiveTasks {
    var list = _svc.archiveTasks.values.toList();
    final group = selectedGroup.value;
    if (group != null) {
      list = list.where((t) => (t['group_name'] ?? t['groupName'] ?? 'default') == group).toList();
    }
    final q = searchQuery.value.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final title = (t['title'] as String? ?? '').toLowerCase();
        final uploader = (t['uploader'] as String? ?? '').toLowerCase();
        final category = (t['category'] as String? ?? '').toLowerCase();
        return title.contains(q) || uploader.contains(q) || category.contains(q);
      }).toList();
    }
    return list;
  }

  Set<String> get allGroups {
    final groups = <String>{};
    for (final t in _svc.galleryTasks.values) {
      groups.add((t['group_name'] ?? t['groupName'] ?? 'default') as String);
    }
    for (final t in _svc.archiveTasks.values) {
      groups.add((t['group_name'] ?? t['groupName'] ?? 'default') as String);
    }
    return groups;
  }

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }

  Future<void> pauseGallery(int gid) => _svc.pauseGallery(gid);
  Future<void> resumeGallery(int gid) => _svc.resumeGallery(gid);
  Future<void> deleteGallery(int gid) => _svc.deleteGallery(gid);
  Future<void> pauseArchive(int gid) => _svc.pauseArchive(gid);
  Future<void> resumeArchive(int gid) => _svc.resumeArchive(gid);
  Future<void> deleteArchive(int gid) => _svc.deleteArchive(gid);

  Future<void> refresh() => _svc.refresh();
}

class WebDownloadsPage extends GetView<WebDownloadsController> {
  const WebDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('downloads.title'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: controller.refresh),
        ],
        bottom: TabBar(
          controller: controller.tabController,
          tabs: [
            Tab(text: 'downloads.gallery'.tr, icon: const Icon(Icons.photo_library)),
            Tab(text: 'downloads.archive'.tr, icon: const Icon(Icons.archive)),
          ],
        ),
      ),
      body: Obx(() {
        final svc = Get.find<WebDownloadService>();
        if (!svc.isLoaded.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            _DownloadFilterBar(controller: controller),
            Expanded(
              child: TabBarView(
                controller: controller.tabController,
                children: [
                  _GalleryTaskList(controller: controller),
                  _ArchiveTaskList(controller: controller),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DownloadFilterBar extends StatelessWidget {
  final WebDownloadsController controller;
  const _DownloadFilterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      final _ = svc.galleryTasks.length + svc.archiveTasks.length;
      final groups = controller.allGroups;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'downloads.search'.tr,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => controller.searchQuery.value = v,
              ),
            ),
            if (groups.length > 1) ...[
              const SizedBox(width: 8),
              Obx(() => DropdownButton<String?>(
                value: controller.selectedGroup.value,
                hint: Text('downloads.allGroups'.tr),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('downloads.allGroups'.tr)),
                  ...groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                ],
                onChanged: (v) => controller.selectedGroup.value = v,
                underline: const SizedBox.shrink(),
                isDense: true,
              )),
            ],
          ],
        ),
      );
    });
  }
}

// --- Gallery Tasks ---

class _GalleryTaskList extends StatelessWidget {
  final WebDownloadsController controller;
  const _GalleryTaskList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      // Touch the reactive map to ensure rebuild on changes
      final _ = svc.galleryTasks.length;
      final tasks = controller.filteredGalleryTasks;
      if (tasks.isEmpty) {
        return Center(child: Text('downloads.noGallery'.tr));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
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

  @override
  Widget build(BuildContext context) {
    final gid = task['gid'] as int;
    final token = task['token'] as String? ?? '';
    final title = task['title'] as String? ?? '';
    final category = task['category'] as String? ?? '';
    final uploader = task['uploader'] as String? ?? '';
    final coverUrl = task['coverUrl'] as String? ?? '';
    final groupName = (task['group_name'] ?? task['groupName'] ?? 'default') as String;
    final status = task['status'] as int? ?? 0;
    final completed = task['completedCount'] as int? ?? 0;
    final total = task['pageCount'] as int? ?? 0;
    final progress = total > 0 ? completed / total : 0.0;
    final statusName = 'downloads.gStatus$status'.tr;
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
                        _StatusBadge(statusIndex: status, statusName: statusName, isCompleted: isCompleted),
                        const SizedBox(width: 8),
                        if (groupName != 'default') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(groupName, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text('$completed / $total', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompleted)
                  IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.green),
                    tooltip: 'downloads.read'.tr,
                    onPressed: () => Get.toNamed('/web/reader/$gid/$token?mode=downloaded'),
                  ),
                if (status == 1)
                  IconButton(icon: const Icon(Icons.pause), tooltip: 'downloads.pause'.tr,
                      onPressed: () => controller.pauseGallery(gid)),
                if (status == 2 || status == 4)
                  IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'downloads.resume'.tr,
                      onPressed: () => controller.resumeGallery(gid)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'common.delete'.tr,
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
        title: Text('downloads.deleteTitle'.tr),
        content: Text('downloads.deleteConfirm'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () { Navigator.pop(ctx); controller.deleteGallery(gid); },
            child: Text('common.delete'.tr, style: const TextStyle(color: Colors.red)),
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
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      final _ = svc.archiveTasks.length;
      final tasks = controller.filteredArchiveTasks;
      if (tasks.isEmpty) {
        return Center(child: Text('downloads.noArchive'.tr));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
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
    final statusName = 'downloads.aStatus$status'.tr;
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
                        _StatusBadge(statusIndex: status, statusName: statusName, isCompleted: isCompleted, isArchive: true),
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
                    tooltip: 'downloads.read'.tr,
                    onPressed: () => Get.toNamed('/web/reader/$gid/$token?mode=archive'),
                  ),
                if (status == 3)
                  IconButton(icon: const Icon(Icons.pause), tooltip: 'downloads.pause'.tr,
                      onPressed: () => controller.pauseArchive(gid)),
                if (status == 7 || status == 8)
                  IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'downloads.resume'.tr,
                      onPressed: () => controller.resumeArchive(gid)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'common.delete'.tr,
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
        title: Text('downloads.deleteTitle'.tr),
        content: Text('downloads.deleteConfirm'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () { Navigator.pop(ctx); controller.deleteArchive(gid); },
            child: Text('common.delete'.tr, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// --- Shared widgets ---

class _StatusBadge extends StatelessWidget {
  final int statusIndex;
  final String statusName;
  final bool isCompleted;
  final bool isArchive;
  const _StatusBadge({required this.statusIndex, required this.statusName, required this.isCompleted, this.isArchive = false});

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(statusName, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Color _resolveColor() {
    if (isCompleted) return Colors.green;
    if (isArchive) {
      // archive: 3=Downloading, 7=Paused, 8=Failed
      return switch (statusIndex) { 3 => Colors.blue, 7 => Colors.orange, 8 => Colors.red, _ => Colors.grey };
    }
    // gallery: 1=Downloading, 2=Paused, 4=Failed
    return switch (statusIndex) { 1 => Colors.blue, 2 => Colors.orange, 4 => Colors.red, _ => Colors.grey };
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
