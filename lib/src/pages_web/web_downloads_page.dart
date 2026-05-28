import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

enum WebDownloadSort { priorityDesc, timeDesc, title, status }

class WebDownloadsController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  static const maxGalleryNum4AnimationStorageKey =
      'jh_web_max_gallery_num_for_animation';
  static const defaultMaxGalleryNum4Animation = 30;

  static const _kGalleryGroupsExpanded =
      'jh_web_downloads_gallery_groups_expanded';
  static const _kArchiveGroupsExpanded =
      'jh_web_downloads_archive_groups_expanded';
  static const _kViewMode = 'jh_web_downloads_view_mode';

  final searchQuery = ''.obs;
  final selectedCategoryFilter = Rxn<String>();
  final gallerySort = WebDownloadSort.priorityDesc.obs;
  final archiveSort = WebDownloadSort.priorityDesc.obs;
  final viewMode = 'list'.obs;

  final galleryGroupExpanded = RxMap<String, bool>();
  final archiveGroupExpanded = RxMap<String, bool>();

  WebDownloadService get _svc => Get.find<WebDownloadService>();

  static int get maxGalleryNum4Animation {
    final value = int.tryParse(
      web.window.localStorage.getItem(maxGalleryNum4AnimationStorageKey) ?? '',
    );
    return value != null && value >= 0 ? value : defaultMaxGalleryNum4Animation;
  }

  static void setMaxGalleryNum4Animation(int value) {
    web.window.localStorage.setItem(
      maxGalleryNum4AnimationStorageKey,
      '${value < 0 ? 0 : value}',
    );
  }

  static String _taskGroupName(Map<String, dynamic> t) =>
      (t['group_name'] ?? t['groupName'] ?? 'default') as String;

  static String _taskCategoryKey(Map<String, dynamic> t) =>
      (t['category'] as String? ?? '').trim();

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

  void _loadViewModeFromStorage() {
    final saved = web.window.localStorage.getItem(_kViewMode);
    if (saved == 'grid' || saved == 'list') {
      viewMode.value = saved!;
    }
  }

  void toggleViewMode() {
    final next = viewMode.value == 'grid' ? 'list' : 'grid';
    viewMode.value = next;
    web.window.localStorage.setItem(_kViewMode, next);
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
      list = list
          .where((t) => _taskCategoryKey(t).toLowerCase() == needle)
          .toList();
    }
    final q = searchQuery.value.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final title = (t['title'] as String? ?? '').toLowerCase();
        final uploader = (t['uploader'] as String? ?? '').toLowerCase();
        final category = (t['category'] as String? ?? '').toLowerCase();
        return title.contains(q) ||
            uploader.contains(q) ||
            category.contains(q);
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
      list = list
          .where((t) => _taskCategoryKey(t).toLowerCase() == needle)
          .toList();
    }
    final q = searchQuery.value.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final title = (t['title'] as String? ?? '').toLowerCase();
        final uploader = (t['uploader'] as String? ?? '').toLowerCase();
        final category = (t['category'] as String? ?? '').toLowerCase();
        return title.contains(q) ||
            uploader.contains(q) ||
            category.contains(q);
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
    final cats =
        galleryTab ? galleryCategoriesForFilter : archiveCategoriesForFilter;
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
    _loadViewModeFromStorage();
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
  Future<void> reDownloadGallery(int gid) => _svc.reDownloadGallery(gid);
  Future<void> deleteGallery(int gid, {bool deleteFiles = true}) =>
      _svc.deleteGallery(gid, deleteFiles: deleteFiles);
  Future<void> pauseArchive(int gid) => _svc.pauseArchive(gid);
  Future<void> resumeArchive(int gid) => _svc.resumeArchive(gid);
  Future<void> deleteArchive(int gid, {bool deleteFiles = true}) =>
      _svc.deleteArchive(gid, deleteFiles: deleteFiles);

  Future<void> refresh() => _svc.refresh();

  Future<void> pauseVisibleTasks() async {
    final galleryTab = tabController.index == 0;
    final tasks =
        galleryTab ? sortedFilteredGalleryTasks : sortedFilteredArchiveTasks;
    final ids = tasks
        .where((t) => galleryTab
            ? (t['status'] == 1)
            : ({1, 2, 3, 4, 5}.contains(t['status'])))
        .map((t) => (t['gid'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await Future.wait(ids.map(galleryTab ? pauseGallery : pauseArchive));
    await refresh();
    Get.snackbar('common.success'.tr,
        'downloads.batchPaused'.trParams({'count': '${ids.length}'}),
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> resumeVisibleTasks() async {
    final galleryTab = tabController.index == 0;
    final tasks =
        galleryTab ? sortedFilteredGalleryTasks : sortedFilteredArchiveTasks;
    final ids = tasks
        .where((t) => galleryTab
            ? ({2, 4}.contains(t['status']))
            : ({7, 8}.contains(t['status'])))
        .map((t) => (t['gid'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await Future.wait(ids.map(galleryTab ? resumeGallery : resumeArchive));
    await refresh();
    Get.snackbar('common.success'.tr,
        'downloads.batchResumed'.trParams({'count': '${ids.length}'}),
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> reDownloadVisibleGalleryTasks() async {
    if (tabController.index != 0) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final ids = sortedFilteredGalleryTasks
        .map((t) => (t['gid'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('reDownload'.tr),
        content: Text(
          'downloads.reDownloadVisibleConfirm'
              .trParams({'count': '${ids.length}'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('reDownload'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Future.wait(ids.map(reDownloadGallery));
    await refresh();
    Get.snackbar('common.success'.tr,
        'downloads.batchRedownloaded'.trParams({'count': '${ids.length}'}),
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> deleteVisibleTasks() async {
    final galleryTab = tabController.index == 0;
    final tasks =
        galleryTab ? sortedFilteredGalleryTasks : sortedFilteredArchiveTasks;
    final ids =
        tasks.map((t) => (t['gid'] as num?)?.toInt()).whereType<int>().toList();
    if (ids.isEmpty) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final deleteFiles = await Get.dialog<bool>(
      AlertDialog(
        title: Text('downloads.deleteVisible'.tr),
        content: Text(
          'downloads.deleteVisibleConfirm'.trParams({'count': '${ids.length}'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('deleteTask'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('deleteTaskAndImages'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (deleteFiles == null) return;

    await Future.wait(ids.map((gid) => galleryTab
        ? deleteGallery(gid, deleteFiles: deleteFiles)
        : deleteArchive(gid, deleteFiles: deleteFiles)));
    await refresh();
    Get.snackbar('common.success'.tr,
        'downloads.batchDeleted'.trParams({'count': '${ids.length}'}),
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> changeVisibleTasksGroup(BuildContext context) async {
    final galleryTab = tabController.index == 0;
    final tasks =
        galleryTab ? sortedFilteredGalleryTasks : sortedFilteredArchiveTasks;
    final ids =
        tasks.map((t) => (t['gid'] as num?)?.toInt()).whereType<int>().toList();
    if (ids.isEmpty) {
      Get.snackbar('common.success'.tr, 'downloads.noBatchTargets'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final group = await _showBatchGroupDialog(context, tasks);
    if (group == null) return;

    await Future.wait(ids.map((gid) => galleryTab
        ? patchGalleryTask(gid, group: group)
        : patchArchiveTask(gid, group: group)));
    await refresh();
    Get.snackbar('common.success'.tr,
        'downloads.batchGroupChanged'.trParams({'count': '${ids.length}'}),
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> patchGalleryTask(int gid, {int? priority, String? group}) async {
    await backendApiClient.patchGalleryDownload(gid,
        priority: priority, group: group);
    await _svc.refresh();
  }

  Future<void> patchArchiveTask(int gid, {int? priority, String? group}) async {
    await backendApiClient.patchArchiveDownload(gid,
        priority: priority, group: group);
    await _svc.refresh();
  }

  Future<void> renameTaskGroup({
    required bool galleryTab,
    required String oldGroup,
    required String newGroup,
  }) async {
    final group = newGroup.trim().isEmpty ? 'default' : newGroup.trim();
    if (group == oldGroup) return;
    final tasks =
        galleryTab ? _svc.galleryTasks.values : _svc.archiveTasks.values;
    final ids = tasks
        .where((t) => _taskGroupName(t) == oldGroup)
        .map((t) => (t['gid'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;
    await Future.wait(
      ids.map((gid) => galleryTab
          ? backendApiClient.patchGalleryDownload(gid, group: group)
          : backendApiClient.patchArchiveDownload(gid, group: group)),
    );
    final expanded = galleryTab ? galleryGroupExpanded : archiveGroupExpanded;
    final oldExpanded = expanded.remove(oldGroup);
    if (oldExpanded != null) {
      expanded[group] = oldExpanded;
      expanded.refresh();
      if (galleryTab) {
        _persistGalleryExpanded();
      } else {
        _persistArchiveExpanded();
      }
    }
    await _svc.refresh();
    Get.snackbar(
      'common.success'.tr,
      'downloads.groupRenamed'.trParams({'count': '${ids.length}'}),
      snackPosition: SnackPosition.BOTTOM,
    );
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
          Obx(
            () => IconButton(
              icon: Icon(controller.viewMode.value == 'grid'
                  ? Icons.view_list
                  : Icons.grid_view),
              tooltip: 'listMode.toggle'.tr,
              onPressed: controller.toggleViewMode,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.pause_circle_outline),
            tooltip: 'downloads.pauseVisible'.tr,
            onPressed: controller.pauseVisibleTasks,
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'downloads.resumeVisible'.tr,
            onPressed: controller.resumeVisibleTasks,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'downloads.reDownloadVisible'.tr,
            onPressed: controller.reDownloadVisibleGalleryTasks,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline),
            tooltip: 'downloads.changeVisibleGroup'.tr,
            onPressed: () => controller.changeVisibleTasksGroup(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'downloads.deleteVisible'.tr,
            onPressed: controller.deleteVisibleTasks,
          ),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: controller.refresh),
        ],
        bottom: TabBar(
          controller: controller.tabController,
          tabs: [
            Tab(
                text: 'downloads.gallery'.tr,
                icon: const Icon(Icons.photo_library)),
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

Future<String?> _showBatchGroupDialog(
    BuildContext context, List<Map<String, dynamic>> tasks) async {
  final groups = WebDownloadsController.sortedGroupNames(
    tasks.map(WebDownloadsController._taskGroupName),
  );
  final controller =
      TextEditingController(text: groups.isEmpty ? 'default' : groups.first);
  try {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('downloads.changeVisibleGroup'.tr),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('downloads.changeVisibleGroupConfirm'
                    .trParams({'count': '${tasks.length}'})),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'downloads.setGroup'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    final group = controller.text.trim();
                    Navigator.pop(ctx, group.isEmpty ? 'default' : group);
                  },
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: groups
                        .map((group) => ActionChip(
                              label: Text(group),
                              onPressed: () => controller.text = group,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed: () {
                final group = controller.text.trim();
                Navigator.pop(ctx, group.isEmpty ? 'default' : group);
              },
              child: Text('common.ok'.tr),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<String?> _showRenameGroupDialog(
  BuildContext context,
  String oldGroup,
) async {
  final controller = TextEditingController(text: oldGroup);
  try {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('downloads.renameGroup'.tr),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('downloads.renameGroupConfirm'
                    .trParams({'group': oldGroup})),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'downloads.setGroup'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    Navigator.pop(ctx, controller.text.trim());
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('common.ok'.tr),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
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
              final sort = galleryTab
                  ? controller.gallerySort.value
                  : controller.archiveSort.value;
              final categories = galleryTab
                  ? controller.galleryCategoriesForFilter
                  : controller.archiveCategoriesForFilter;
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: WebDownloadSort.priorityDesc,
                              child: Text('downloads.sortPriority'.tr,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.timeDesc,
                              child: Text('downloads.sortTime'.tr,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.title,
                              child: Text('downloads.sortTitle'.tr,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: WebDownloadSort.status,
                              child: Text('downloads.sortStatus'.tr,
                                  overflow: TextOverflow.ellipsis),
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                      onChanged: (v) =>
                          controller.selectedCategoryFilter.value = v,
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
  final bool animate;
  final VoidCallback onTap;
  final VoidCallback? onRename;

  const _DownloadGroupHeader({
    required this.groupName,
    required this.count,
    required this.expanded,
    this.animate = true,
    required this.onTap,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.folder_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  groupName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '($count)',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration:
                    animate ? const Duration(milliseconds: 200) : Duration.zero,
                child: const Icon(Icons.chevron_right, size: 22),
              ),
              if (onRename != null)
                PopupMenuButton<_DownloadGroupAction>(
                  tooltip: 'downloads.renameGroup'.tr,
                  onSelected: (action) {
                    switch (action) {
                      case _DownloadGroupAction.rename:
                        onRename?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _DownloadGroupAction.rename,
                      child: _DownloadTaskMenuItem(
                        icon: Icons.drive_file_rename_outline,
                        label: 'downloads.renameGroup'.tr,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DownloadGroupAction { rename }

void _showGalleryPatchDialog(BuildContext context, WebDownloadsController ctrl,
    Map<String, dynamic> task) {
  final gid = task['gid'] as int;
  final priCtrl = TextEditingController(
      text: '${(task['priority'] as num?)?.toInt() ?? 0}');
  final grpCtrl = TextEditingController(
      text: '${task['group_name'] ?? task['groupName'] ?? 'default'}');
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
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr)),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final g =
                grpCtrl.text.trim().isEmpty ? 'default' : grpCtrl.text.trim();
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

void _showArchivePatchDialog(BuildContext context, WebDownloadsController ctrl,
    Map<String, dynamic> task) {
  final gid = task['gid'] as int;
  final priCtrl = TextEditingController(
      text: '${(task['priority'] as num?)?.toInt() ?? 0}');
  final grpCtrl = TextEditingController(
      text: '${task['group_name'] ?? task['groupName'] ?? 'default'}');
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
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr)),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final g =
                grpCtrl.text.trim().isEmpty ? 'default' : grpCtrl.text.trim();
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

Future<bool?> _showDeleteTaskDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('downloads.deleteTitle'.tr),
      content: Text('downloads.deleteConfirm'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('common.cancel'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'deleteTask'.tr,
            style: const TextStyle(color: Colors.red),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'deleteTaskAndImages'.tr,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
}

Future<bool> _showReDownloadGalleryDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('reDownload'.tr),
      content: Text('downloads.reDownloadConfirm'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('common.cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('reDownload'.tr),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> _renameDownloadGroup(
  BuildContext context,
  WebDownloadsController controller, {
  required bool galleryTab,
  required String oldGroup,
}) async {
  final next = await _showRenameGroupDialog(context, oldGroup);
  if (next == null) return;
  await controller.renameTaskGroup(
    galleryTab: galleryTab,
    oldGroup: oldGroup,
    newGroup: next,
  );
}

class _GroupedDownloadGrid extends StatelessWidget {
  final List<String> groups;
  final Map<String, List<Map<String, dynamic>>> byGroup;
  final Map<String, bool> expanded;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String>? onRenameGroup;
  final Widget Function(Map<String, dynamic> task) itemBuilder;

  const _GroupedDownloadGrid({
    required this.groups,
    required this.byGroup,
    required this.expanded,
    required this.onToggleGroup,
    this.onRenameGroup,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1280
            ? 6
            : width >= 1000
                ? 5
                : width >= 760
                    ? 4
                    : width >= 520
                        ? 3
                        : 2;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            for (final group in groups) ...[
              _DownloadGroupHeader(
                groupName: group,
                count: byGroup[group]!.length,
                expanded: expanded[group] ?? true,
                animate: byGroup[group]!.length <=
                    WebDownloadsController.maxGalleryNum4Animation,
                onTap: () => onToggleGroup(group),
                onRename: onRenameGroup == null
                    ? null
                    : () => onRenameGroup?.call(group),
              ),
              const SizedBox(height: 8),
              if (expanded[group] ?? true)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: byGroup[group]!.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (context, index) =>
                      itemBuilder(byGroup[group]![index]),
                ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _GalleryTaskGridCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final WebDownloadsController controller;

  const _GalleryTaskGridCard({required this.task, required this.controller});

  @override
  Widget build(BuildContext context) {
    final gid = _taskInt(task, 'gid');
    final token = task['token'] as String? ?? '';
    final status = _taskInt(task, 'status');
    final isCompleted = status == 3;
    return _DownloadTaskGridCard(
      task: task,
      statusName: 'downloads.gStatus$status'.tr,
      isCompleted: isCompleted,
      progressLabel:
          '${_taskInt(task, 'completedCount')} / ${_taskInt(task, 'pageCount')}',
      progressValue:
          _ratio(_taskInt(task, 'completedCount'), _taskInt(task, 'pageCount')),
      readRoute: '/web/reader/$gid/$token?mode=downloaded',
      onEdit: () => _showGalleryPatchDialog(context, controller, task),
      onReDownload: () async {
        if (!await _showReDownloadGalleryDialog(context)) return;
        await controller.reDownloadGallery(gid);
      },
      onPause: status == 1 ? () => controller.pauseGallery(gid) : null,
      onResume: status == 2 || status == 4
          ? () => controller.resumeGallery(gid)
          : null,
      onDelete: () async {
        final deleteFiles = await _showDeleteTaskDialog(context);
        if (deleteFiles == null) return;
        await controller.deleteGallery(gid, deleteFiles: deleteFiles);
      },
    );
  }
}

class _ArchiveTaskGridCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final WebDownloadsController controller;

  const _ArchiveTaskGridCard({required this.task, required this.controller});

  @override
  Widget build(BuildContext context) {
    final gid = _taskInt(task, 'gid');
    final token = task['token'] as String? ?? '';
    final status = _taskInt(task, 'status');
    final downloaded = _taskInt(task, 'downloadedBytes');
    final total = _taskInt(task, 'totalBytes');
    final isCompleted = status == 6;
    return _DownloadTaskGridCard(
      task: task,
      fallbackIcon: Icons.archive,
      statusName: 'downloads.aStatus$status'.tr,
      isCompleted: isCompleted,
      isArchive: true,
      isOriginalArchive: task['isOriginal'] == true,
      progressLabel: total > 0
          ? '${_formatBytes(downloaded)} / ${_formatBytes(total)}'
          : '',
      progressValue: status == 3
          ? _ratio(downloaded, total)
          : isCompleted
              ? 1
              : null,
      readRoute: '/web/reader/$gid/$token?mode=archive',
      onEdit: () => _showArchivePatchDialog(context, controller, task),
      onPause: status == 3 ? () => controller.pauseArchive(gid) : null,
      onResume: status == 7 || status == 8
          ? () => controller.resumeArchive(gid)
          : null,
      onDelete: () async {
        final deleteFiles = await _showDeleteTaskDialog(context);
        if (deleteFiles == null) return;
        await controller.deleteArchive(gid, deleteFiles: deleteFiles);
      },
    );
  }
}

class _DownloadTaskGridCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final IconData fallbackIcon;
  final String statusName;
  final bool isCompleted;
  final bool isArchive;
  final bool isOriginalArchive;
  final String progressLabel;
  final double? progressValue;
  final String readRoute;
  final VoidCallback onEdit;
  final VoidCallback? onReDownload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback onDelete;

  const _DownloadTaskGridCard({
    required this.task,
    this.fallbackIcon = Icons.photo_library,
    required this.statusName,
    required this.isCompleted,
    this.isArchive = false,
    this.isOriginalArchive = false,
    required this.progressLabel,
    required this.progressValue,
    required this.readRoute,
    required this.onEdit,
    this.onReDownload,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = task['title'] as String? ?? '';
    final category = task['category'] as String? ?? '';
    final coverUrl = task['coverUrl'] as String? ?? '';
    final priority = _taskInt(task, 'priority');
    final groupName =
        (task['group_name'] ?? task['groupName'] ?? 'default') as String;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCompleted ? () => Get.toNamed(readRoute) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl.isNotEmpty
                      ? WebProxiedImage(
                          sourceUrl: coverUrl,
                          fit: BoxFit.cover,
                          readerErrorChild: _GridCoverFallback(
                            icon: fallbackIcon,
                          ),
                        )
                      : _GridCoverFallback(icon: fallbackIcon),
                  if (!isCompleted)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: PopupMenuButton<_DownloadTaskAction>(
                      tooltip: 'downloads.editTask'.tr,
                      icon: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.more_vert,
                            color: Colors.white, size: 18),
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _DownloadTaskAction.read:
                            Get.toNamed(readRoute);
                            break;
                          case _DownloadTaskAction.edit:
                            onEdit();
                            break;
                          case _DownloadTaskAction.reDownload:
                            onReDownload?.call();
                            break;
                          case _DownloadTaskAction.pause:
                            onPause?.call();
                            break;
                          case _DownloadTaskAction.resume:
                            onResume?.call();
                            break;
                          case _DownloadTaskAction.delete:
                            onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (isCompleted)
                          PopupMenuItem(
                            value: _DownloadTaskAction.read,
                            child: _DownloadTaskMenuItem(
                              icon: Icons.menu_book,
                              label: 'downloads.read'.tr,
                            ),
                          ),
                        PopupMenuItem(
                          value: _DownloadTaskAction.edit,
                          child: _DownloadTaskMenuItem(
                            icon: Icons.tune,
                            label: 'downloads.editTask'.tr,
                          ),
                        ),
                        if (onReDownload != null)
                          PopupMenuItem(
                            value: _DownloadTaskAction.reDownload,
                            child: _DownloadTaskMenuItem(
                              icon: Icons.restart_alt,
                              label: 'reDownload'.tr,
                            ),
                          ),
                        if (onPause != null)
                          PopupMenuItem(
                            value: _DownloadTaskAction.pause,
                            child: _DownloadTaskMenuItem(
                              icon: Icons.pause,
                              label: 'downloads.pause'.tr,
                            ),
                          ),
                        if (onResume != null)
                          PopupMenuItem(
                            value: _DownloadTaskAction.resume,
                            child: _DownloadTaskMenuItem(
                              icon: Icons.play_arrow,
                              label: 'downloads.resume'.tr,
                            ),
                          ),
                        PopupMenuItem(
                          value: _DownloadTaskAction.delete,
                          child: _DownloadTaskMenuItem(
                            icon: Icons.delete_outline,
                            label: 'common.delete'.tr,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (category.isNotEmpty)
                        _TinyLabel(
                          label: category,
                          color: _categoryColor(category),
                          filled: true,
                        ),
                      _TinyLabel(
                        label: 'downloads.priorityLabel'
                            .trParams({'n': '$priority'}),
                        color: Colors.purple,
                      ),
                      if (groupName != 'default')
                        _TinyLabel(label: groupName, color: Colors.blueGrey),
                      if (isArchive && isOriginalArchive)
                        _TinyLabel(
                          label: 'originalImage'.tr,
                          color: Colors.teal,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: _StatusBadge(
                          statusIndex: _taskInt(task, 'status'),
                          statusName: statusName,
                          isCompleted: isCompleted,
                          isArchive: isArchive,
                        ),
                      ),
                      if (progressLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            progressLabel,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: progressValue),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCoverFallback extends StatelessWidget {
  final IconData icon;
  const _GridCoverFallback({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, color: Colors.grey),
    );
  }
}

class _TinyLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _TinyLabel({
    required this.label,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontSize: 10,
          fontWeight: filled ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _DownloadTaskMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DownloadTaskMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

enum _DownloadTaskAction { read, edit, reDownload, pause, resume, delete }

// --- Gallery Tasks ---

class _GalleryTaskList extends StatelessWidget {
  final WebDownloadsController controller;
  const _GalleryTaskList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      final _ =
          svc.galleryTasks.length + controller.galleryGroupExpanded.length;
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
      if (controller.viewMode.value == 'grid') {
        return _GroupedDownloadGrid(
          groups: groups,
          byGroup: byGroup,
          expanded: controller.galleryGroupExpanded,
          onToggleGroup: controller.toggleGalleryGroup,
          onRenameGroup: (group) => _renameDownloadGroup(
            context,
            controller,
            galleryTab: true,
            oldGroup: group,
          ),
          itemBuilder: (task) =>
              _GalleryTaskGridCard(task: task, controller: controller),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final g in groups) ...[
            _DownloadGroupHeader(
              groupName: g,
              count: byGroup[g]!.length,
              expanded: controller.galleryGroupExpanded[g] ?? true,
              animate: byGroup[g]!.length <=
                  WebDownloadsController.maxGalleryNum4Animation,
              onTap: () => controller.toggleGalleryGroup(g),
              onRename: () => _renameDownloadGroup(
                context,
                controller,
                galleryTab: true,
                oldGroup: g,
              ),
            ),
            const SizedBox(height: 6),
            if (controller.galleryGroupExpanded[g] ?? true)
              ...byGroup[g]!.map((task) =>
                  _GalleryTaskCard(task: task, controller: controller)),
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
    final groupName =
        (task['group_name'] ?? task['groupName'] ?? 'default') as String;
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child:
                            const Icon(Icons.photo_library, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child:
                          const Icon(Icons.photo_library, color: Colors.grey),
                    ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _categoryColor(category),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(category,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (uploader.isNotEmpty)
                          Flexible(
                            child: Text(uploader,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(
                            statusIndex: status,
                            statusName: statusName,
                            isCompleted: isCompleted),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'downloads.priorityLabel'
                                .trParams({'n': '$priority'}),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.purple),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (groupName != 'default') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(groupName,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.blueGrey)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text('$completed / $total',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    if (supersededBy != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'downloads.superseded'
                              .trParams({'gid': '$supersededBy'}),
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange.shade800),
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
                  onPressed: () =>
                      _showGalleryPatchDialog(context, controller, task),
                ),
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 20),
                  tooltip: 'reDownload'.tr,
                  onPressed: () async {
                    if (!await _showReDownloadGalleryDialog(context)) return;
                    await controller.reDownloadGallery(gid);
                  },
                ),
                if (isCompleted)
                  IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.green),
                    tooltip: 'downloads.read'.tr,
                    onPressed: () =>
                        Get.toNamed('/web/reader/$gid/$token?mode=downloaded'),
                  ),
                if (status == 1)
                  IconButton(
                      icon: const Icon(Icons.pause),
                      tooltip: 'downloads.pause'.tr,
                      onPressed: () => controller.pauseGallery(gid)),
                if (status == 2 || status == 4)
                  IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'downloads.resume'.tr,
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

  Future<void> _confirmDelete(BuildContext context, int gid) async {
    final deleteFiles = await _showDeleteTaskDialog(context);
    if (deleteFiles == null) return;
    await controller.deleteGallery(gid, deleteFiles: deleteFiles);
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
      final _ =
          svc.archiveTasks.length + controller.archiveGroupExpanded.length;
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
      if (controller.viewMode.value == 'grid') {
        return _GroupedDownloadGrid(
          groups: groups,
          byGroup: byGroup,
          expanded: controller.archiveGroupExpanded,
          onToggleGroup: controller.toggleArchiveGroup,
          onRenameGroup: (group) => _renameDownloadGroup(
            context,
            controller,
            galleryTab: false,
            oldGroup: group,
          ),
          itemBuilder: (task) =>
              _ArchiveTaskGridCard(task: task, controller: controller),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final g in groups) ...[
            _DownloadGroupHeader(
              groupName: g,
              count: byGroup[g]!.length,
              expanded: controller.archiveGroupExpanded[g] ?? true,
              animate: byGroup[g]!.length <=
                  WebDownloadsController.maxGalleryNum4Animation,
              onTap: () => controller.toggleArchiveGroup(g),
              onRename: () => _renameDownloadGroup(
                context,
                controller,
                galleryTab: false,
                oldGroup: g,
              ),
            ),
            const SizedBox(height: 6),
            if (controller.archiveGroupExpanded[g] ?? true)
              ...byGroup[g]!.map((task) =>
                  _ArchiveTaskCard(task: task, controller: controller)),
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
    final groupName =
        (task['group_name'] ?? task['groupName'] ?? 'default') as String;
    final status = task['status'] as int? ?? 0;
    final downloaded = task['downloadedBytes'] as int? ?? 0;
    final total = task['totalBytes'] as int? ?? 0;
    final progress = total > 0 ? downloaded / total : 0.0;
    final statusName = 'downloads.aStatus$status'.tr;
    final isCompleted = status == 6;
    final isOriginal = task['isOriginal'] == true;

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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.archive, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _categoryColor(category),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(category,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (uploader.isNotEmpty)
                          Flexible(
                            child: Text(uploader,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(
                            statusIndex: status,
                            statusName: statusName,
                            isCompleted: isCompleted,
                            isArchive: true),
                        const SizedBox(width: 8),
                        if (isOriginal) ...[
                          _TinyLabel(
                            label: 'originalImage'.tr,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'downloads.priorityLabel'
                                .trParams({'n': '$priority'}),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.purple),
                          ),
                        ),
                        if (groupName != 'default') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(groupName,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.blueGrey)),
                          ),
                        ],
                        const SizedBox(width: 8),
                        if (total > 0)
                          Flexible(
                            child: Text(
                                '${_formatBytes(downloaded)} / ${_formatBytes(total)}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                        value: status == 3
                            ? progress
                            : (isCompleted ? 1.0 : null)),
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
                  onPressed: () =>
                      _showArchivePatchDialog(context, controller, task),
                ),
                if (isCompleted)
                  IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.green),
                    tooltip: 'downloads.read'.tr,
                    onPressed: () =>
                        Get.toNamed('/web/reader/$gid/$token?mode=archive'),
                  ),
                if (status == 3)
                  IconButton(
                      icon: const Icon(Icons.pause),
                      tooltip: 'downloads.pause'.tr,
                      onPressed: () => controller.pauseArchive(gid)),
                if (status == 7 || status == 8)
                  IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'downloads.resume'.tr,
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

  Future<void> _confirmDelete(BuildContext context, int gid) async {
    final deleteFiles = await _showDeleteTaskDialog(context);
    if (deleteFiles == null) return;
    await controller.deleteArchive(gid, deleteFiles: deleteFiles);
  }
}

// --- Shared widgets ---

class _StatusBadge extends StatelessWidget {
  final int statusIndex;
  final String statusName;
  final bool isCompleted;
  final bool isArchive;
  const _StatusBadge(
      {required this.statusIndex,
      required this.statusName,
      required this.isCompleted,
      this.isArchive = false});

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
      child: Text(statusName,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Color _resolveColor() {
    if (isCompleted) return Colors.green;
    if (isArchive) {
      // archive: 3=Downloading, 7=Paused, 8=Failed
      return switch (statusIndex) {
        3 => Colors.blue,
        7 => Colors.orange,
        8 => Colors.red,
        _ => Colors.grey
      };
    }
    // gallery: 1=Downloading, 2=Paused, 4=Failed
    return switch (statusIndex) {
      1 => Colors.blue,
      2 => Colors.orange,
      4 => Colors.red,
      _ => Colors.grey
    };
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

int _taskInt(Map<String, dynamic> task, String key) =>
    (task[key] as num?)?.toInt() ?? 0;

double? _ratio(int completed, int total) =>
    total > 0 ? completed / total : null;
