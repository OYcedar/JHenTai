import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

enum WebDownloadSort { priorityDesc, timeDesc, title, status }

class WebDownloadsController extends GetxController with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  static const _kGalleryGroupsExpanded = 'jh_web_downloads_gallery_groups_expanded';
  static const _kArchiveGroupsExpanded = 'jh_web_downloads_archive_groups_expanded';

  final searchQuery = ''.obs;
  final selectedCategoryFilter = Rxn<String>();
  final gallerySort = WebDownloadSort.priorityDesc.obs;
  final archiveSort = WebDownloadSort.priorityDesc.obs;

  final galleryGroupExpanded = RxMap<String, bool>();
  final archiveGroupExpanded = RxMap<String, bool>();

  WebDownloadService get _svc => Get.find<WebDownloadService>();

  static String _taskGroupName(Map<String, dynamic> t) =>
      (t['group_name'] ?? t['groupName'] ?? 'default') as String;

  static String _taskCategoryKey(Map<String, dynamic> t) => (t['category'] as String? ?? '').trim();

  static List<String> sortedGroupNames(Iterable<String> names) {
    final list = names.toSet().toList();
    list.sort((a, b) {
      if (a == 'default') return -1;
      if (b == 'default') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  List<String> get galleryCategoriesForFilter {
    final s = <String>{};
    for (final t in _svc.galleryTasks.values) {
      final c = _taskCategoryKey(t);
      if (c.isNotEmpty) s.add(c);
    }
    final list = s.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> get archiveCategoriesForFilter {
    final s = <String>{};
    for (final t in _svc.archiveTasks.values) {
      final c = _taskCategoryKey(t);
      if (c.isNotEmpty) s.add(c);
    }
    final list = s.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _loadExpandedFromStorage() {
    _mergeExpandedMap(_kGalleryGroupsExpanded, galleryGroupExpanded);
    _mergeExpandedMap(_kArchiveGroupsExpanded, archiveGroupExpanded);
  }

  void _mergeExpandedMap(String key, RxMap<String, bool> target) {
    try {
      final raw = web.window.localStorage.getItem(key);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((k, v) {
        if (v is bool) target[k] = v;
      });
    } catch (_) {}
  }

  void _persistGalleryExpanded() {
    try {
      web.window.localStorage.setItem(
        _kGalleryGroupsExpanded,
        jsonEncode(Map<String, bool>.from(galleryGroupExpanded)),
      );
    } catch (_) {}
  }

  void _persistArchiveExpanded() {
    try {
      web.window.localStorage.setItem(
        _kArchiveGroupsExpanded,
        jsonEncode(Map<String, bool>.from(archiveGroupExpanded)),
      );
    } catch (_) {}
  }

  void toggleGalleryGroup(String groupName) {
    final cur = galleryGroupExpanded[groupName] ?? true;
    galleryGroupExpanded[groupName] = !cur;
    galleryGroupExpanded.refresh();
    _persistGalleryExpanded();
  }

  void toggleArchiveGroup(String groupName) {
    final cur = archiveGroupExpanded[groupName] ?? true;
    archiveGroupExpanded[groupName] = !cur;
    archiveGroupExpanded.refresh();
    _persistArchiveExpanded();
  }

  List<Map<String, dynamic>> get filteredGalleryTasks {
    var list = _svc.galleryTasks.values.toList();
    final cat = selectedCategoryFilter.value;
    if (cat != null && cat.isNotEmpty) {
      final needle = cat.toLowerCase();
      list = list.where((t) => _taskCategoryKey(t).toLowerCase() == needle).toList();
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

  static int _cmpInsertTime(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['insertTime'] as String? ?? '';
    final tb = b['insertTime'] as String? ?? '';
    return ta.compareTo(tb);
  }

  static int _galleryStatusRank(int s) => switch (s) {
        3 => 0,
        1 => 1,
        2 => 2,
        4 => 3,
        _ => 9,
      };

  static int _archiveStatusRank(int s) => switch (s) {
        6 => 0,
        3 => 1,
        7 => 2,
        8 => 3,
        _ => 9,
      };

  List<Map<String, dynamic>> get sortedFilteredGalleryTasks {
    final list = List<Map<String, dynamic>>.from(filteredGalleryTasks);
    switch (gallerySort.value) {
      case WebDownloadSort.priorityDesc:
        list.sort((a, b) {
          final pa = (a['priority'] as num?)?.toInt() ?? 0;
          final pb = (b['priority'] as num?)?.toInt() ?? 0;
          if (pa != pb) return pb.compareTo(pa);
          return _cmpInsertTime(a, b);
        });
        break;
      case WebDownloadSort.timeDesc:
        list.sort((a, b) => _cmpInsertTime(b, a));
        break;
      case WebDownloadSort.title:
        list.sort((a, b) => (a['title'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['title'] as String? ?? '').toLowerCase()));
        break;
      case WebDownloadSort.status:
        list.sort((a, b) {
          final sa = a['status'] as int? ?? 0;
          final sb = b['status'] as int? ?? 0;
          final ra = _galleryStatusRank(sa);
          final rb = _galleryStatusRank(sb);
          if (ra != rb) return ra.compareTo(rb);
          return _cmpInsertTime(b, a);
        });
        break;
    }
    return list;
  }

  List<Map<String, dynamic>> get filteredArchiveTasks {
    var list = _svc.archiveTasks.values.toList();
    final cat = selectedCategoryFilter.value;
    if (cat != null && cat.isNotEmpty) {
      final needle = cat.toLowerCase();
      list = list.where((t) => _taskCategoryKey(t).toLowerCase() == needle).toList();
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

  List<Map<String, dynamic>> get sortedFilteredArchiveTasks {
    final list = List<Map<String, dynamic>>.from(filteredArchiveTasks);
    switch (archiveSort.value) {
      case WebDownloadSort.priorityDesc:
        list.sort((a, b) {
          final pa = (a['priority'] as num?)?.toInt() ?? 0;
          final pb = (b['priority'] as num?)?.toInt() ?? 0;
          if (pa != pb) return pb.compareTo(pa);
          return _cmpInsertTime(a, b);
        });
        break;
      case WebDownloadSort.timeDesc:
        list.sort((a, b) => _cmpInsertTime(b, a));
        break;
      case WebDownloadSort.title:
        list.sort((a, b) => (a['title'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['title'] as String? ?? '').toLowerCase()));
        break;
      case WebDownloadSort.status:
        list.sort((a, b) {
          final sa = a['status'] as int? ?? 0;
          final sb = b['status'] as int? ?? 0;
          final ra = _archiveStatusRank(sa);
          final rb = _archiveStatusRank(sb);
          if (ra != rb) return ra.compareTo(rb);
          return _cmpInsertTime(b, a);
        });
        break;
    }
    return list;
  }

  void _syncCategoryFilterWithTab() {
    final galleryTab = tabController.index == 0;
    final cats = galleryTab ? galleryCategoriesForFilter : archiveCategoriesForFilter;
    final sel = selectedCategoryFilter.value;
    if (sel != null && !cats.contains(sel)) {
      selectedCategoryFilter.value = null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
    _loadExpandedFromStorage();
    tabController.addListener(_syncCategoryFilterWithTab);
  }

  @override
  void onClose() {
    tabController.removeListener(_syncCategoryFilterWithTab);
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

  Future<void> patchGalleryTask(int gid, {int? priority, String? group}) async {
    await backendApiClient.patchGalleryDownload(gid, priority: priority, group: group);
    await _svc.refresh();
  }

  Future<void> patchArchiveTask(int gid, {int? priority, String? group}) async {
    await backendApiClient.patchArchiveDownload(gid, priority: priority, group: group);
    await _svc.refresh();
  }
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: AnimatedBuilder(
          animation: controller.tabController,
          builder: (context, _) {
            final galleryTab = controller.tabController.index == 0;
            return Obx(() {
              final sort = galleryTab ? controller.gallerySort.value : controller.archiveSort.value;
              final categories =
                  galleryTab ? controller.galleryCategoriesForFilter : controller.archiveCategoriesForFilter;
              final rawCat = controller.selectedCategoryFilter.value;
              if (rawCat != null && !categories.contains(rawCat)) {
                Future.microtask(() {
                  if (controller.selectedCategoryFilter.value == rawCat) {
                    controller.selectedCategoryFilter.value = null;
                  }
                });
              }
              final categoryFieldValue =
                  rawCat == null || categories.contains(rawCat) ? rawCat : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<WebDownloadSort>(
                          value: sort,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: 'downloads.sortBy'.tr,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: WebDownloadSort.priorityDesc,
                              child: Text('downloads.sortPriority'.tr, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.timeDesc,
                              child: Text('downloads.sortTime'.tr, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.title,
                              child: Text('downloads.sortTitle'.tr, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.status,
                              child: Text('downloads.sortStatus'.tr, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            if (galleryTab) {
                              controller.gallerySort.value = v;
                            } else {
                              controller.archiveSort.value = v;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: categoryFieldValue,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: 'downloads.categoryFilter'.tr,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('downloads.allCategories'.tr),
                        ),
                        ...categories.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => controller.selectedCategoryFilter.value = v,
                    ),
                  ],
                ],
              );
            });
          },
        ),
      );
    });
  }
}

class _DownloadGroupHeader extends StatelessWidget {
  final String groupName;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _DownloadGroupHeader({
    required this.groupName,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  groupName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '($count)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.chevron_right, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showGalleryPatchDialog(BuildContext context, WebDownloadsController ctrl, Map<String, dynamic> task) {
  final gid = task['gid'] as int;
  final priCtrl = TextEditingController(text: '${(task['priority'] as num?)?.toInt() ?? 0}');
  final grpCtrl = TextEditingController(text: '${task['group_name'] ?? task['groupName'] ?? 'default'}');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('downloads.editTask'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: priCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'downloads.setPriority'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: grpCtrl,
            decoration: InputDecoration(
              labelText: 'downloads.setGroup'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final g = grpCtrl.text.trim().isEmpty ? 'default' : grpCtrl.text.trim();
            await ctrl.patchGalleryTask(
              gid,
              priority: int.tryParse(priCtrl.text.trim()),
              group: g,
            );
          },
          child: Text('common.ok'.tr),
        ),
      ],
    ),
  );
}

void _showArchivePatchDialog(BuildContext context, WebDownloadsController ctrl, Map<String, dynamic> task) {
  final gid = task['gid'] as int;
  final priCtrl = TextEditingController(text: '${(task['priority'] as num?)?.toInt() ?? 0}');
  final grpCtrl = TextEditingController(text: '${task['group_name'] ?? task['groupName'] ?? 'default'}');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('downloads.editTask'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: priCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'downloads.setPriority'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: grpCtrl,
            decoration: InputDecoration(
              labelText: 'downloads.setGroup'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final g = grpCtrl.text.trim().isEmpty ? 'default' : grpCtrl.text.trim();
            await ctrl.patchArchiveTask(
              gid,
              priority: int.tryParse(priCtrl.text.trim()),
              group: g,
            );
          },
          child: Text('common.ok'.tr),
        ),
      ],
    ),
  );
}

// --- Gallery Tasks ---

class _GalleryTaskList extends StatelessWidget {
  final WebDownloadsController controller;
  const _GalleryTaskList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      final _ = svc.galleryTasks.length + controller.galleryGroupExpanded.length;
      final tasks = controller.sortedFilteredGalleryTasks;
      if (tasks.isEmpty) {
        return Center(child: Text('downloads.noGallery'.tr));
      }
      final byGroup = <String, List<Map<String, dynamic>>>{};
      for (final t in tasks) {
        final g = WebDownloadsController._taskGroupName(t);
        byGroup.putIfAbsent(g, () => []).add(t);
      }
      final groups = WebDownloadsController.sortedGroupNames(byGroup.keys);
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final g in groups) ...[
            _DownloadGroupHeader(
              groupName: g,
              count: byGroup[g]!.length,
              expanded: controller.galleryGroupExpanded[g] ?? true,
              onTap: () => controller.toggleGalleryGroup(g),
            ),
            const SizedBox(height: 6),
            if (controller.galleryGroupExpanded[g] ?? true)
              ...byGroup[g]!.map((task) => _GalleryTaskCard(task: task, controller: controller)),
            const SizedBox(height: 10),
          ],
        ],
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
    final priority = (task['priority'] as num?)?.toInt() ?? 0;
    final supersededBy = task['supersededByGid'] as int?;
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
                  ? WebProxiedImage(
                      sourceUrl: coverUrl,
                      fit: BoxFit.cover,
                      readerErrorChild: Container(
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'downloads.priorityLabel'.trParams({'n': '$priority'}),
                            style: const TextStyle(fontSize: 10, color: Colors.purple),
                          ),
                        ),
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
                    if (supersededBy != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'downloads.superseded'.trParams({'gid': '$supersededBy'}),
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                        ),
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
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'downloads.editTask'.tr,
                  onPressed: () => _showGalleryPatchDialog(context, controller, task),
                ),
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
      final _ = svc.archiveTasks.length + controller.archiveGroupExpanded.length;
      final tasks = controller.sortedFilteredArchiveTasks;
      if (tasks.isEmpty) {
        return Center(child: Text('downloads.noArchive'.tr));
      }
      final byGroup = <String, List<Map<String, dynamic>>>{};
      for (final t in tasks) {
        final g = WebDownloadsController._taskGroupName(t);
        byGroup.putIfAbsent(g, () => []).add(t);
      }
      final groups = WebDownloadsController.sortedGroupNames(byGroup.keys);
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final g in groups) ...[
            _DownloadGroupHeader(
              groupName: g,
              count: byGroup[g]!.length,
              expanded: controller.archiveGroupExpanded[g] ?? true,
              onTap: () => controller.toggleArchiveGroup(g),
            ),
            const SizedBox(height: 6),
            if (controller.archiveGroupExpanded[g] ?? true)
              ...byGroup[g]!.map((task) => _ArchiveTaskCard(task: task, controller: controller)),
            const SizedBox(height: 10),
          ],
        ],
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
    final priority = (task['priority'] as num?)?.toInt() ?? 0;
    final groupName = (task['group_name'] ?? task['groupName'] ?? 'default') as String;
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
                  ? WebProxiedImage(
                      sourceUrl: coverUrl,
                      fit: BoxFit.cover,
                      readerErrorChild: Container(
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'downloads.priorityLabel'.trParams({'n': '$priority'}),
                            style: const TextStyle(fontSize: 10, color: Colors.purple),
                          ),
                        ),
                        if (groupName != 'default') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(groupName, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                          ),
                        ],
                        const SizedBox(width: 8),
                        if (total > 0)
                          Flexible(
                            child: Text('${_formatBytes(downloaded)} / ${_formatBytes(total)}',
                                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                          ),
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
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'downloads.editTask'.tr,
                  onPressed: () => _showArchivePatchDialog(context, controller, task),
                ),
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
