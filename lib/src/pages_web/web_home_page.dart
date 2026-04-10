import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_gallery_detail_page.dart';
import 'package:web/web.dart' as web;

class WebHomeController extends GetxController {
  final searchController = TextEditingController();
  final galleries = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final currentPage = 0.obs;
  final hasNextPage = false.obs;
  final hasPrevPage = false.obs;

  // Advanced search state
  final categoryFilter = 0.obs;
  final minimumRating = 0.obs;
  final searchInName = true.obs;
  final searchInTags = true.obs;
  final searchInDesc = false.obs;
  final showExpunged = false.obs;

  // List mode: grid, list, listCompact
  final listMode = 'grid'.obs;

  // Quick search
  final quickSearches = <Map<String, dynamic>>[].obs;

  static const _categoryKeys = [
    'category.doujinshi', 'category.manga', 'category.artistCg', 'category.gameCg', 'category.western',
    'category.nonH', 'category.imageSet', 'category.cosplay', 'category.asianPorn', 'category.misc',
  ];
  static const _categoryBits = [2, 4, 8, 16, 512, 256, 32, 64, 1024, 1];

  @override
  void onInit() {
    super.onInit();
    final savedMode = web.window.localStorage.getItem('jh_web_list_mode');
    if (savedMode != null && ['grid', 'list', 'listCompact'].contains(savedMode)) {
      listMode.value = savedMode;
    }
    final args = Get.arguments;
    if (args is Map<String, dynamic> && args['search'] is String) {
      final searchQuery = args['search'] as String;
      searchController.text = searchQuery;
      _currentSearch = searchQuery;
    }
    _loadHomePage();
    loadSearchHistory();
    loadQuickSearches();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  String _currentSection = 'home';
  String _currentSearch = '';
  String _ranklistTl = '15';

  final searchHistory = <String>[].obs;

  void loadSearchHistory() async {
    try {
      final items = await backendApiClient.fetchSearchHistory();
      searchHistory.value = items.map((e) => (e['keyword'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
    } catch (_) {}
  }

  Future<void> _loadHomePage() async {
    _currentSection = 'home';
    if (_currentSearch.isEmpty) _currentSearch = '';
    await _fetchGalleryList();
  }

  Future<void> search(String keyword) async {
    _currentSearch = keyword;
    _currentSection = 'home';
    currentPage.value = 0;
    if (keyword.trim().isNotEmpty) {
      backendApiClient.recordSearchHistory(keyword.trim()).catchError((_) {});
      loadSearchHistory();
    }
    await _fetchGalleryList();
  }

  Future<void> nextPage() async {
    currentPage.value++;
    await _fetchGalleryList();
  }

  Future<void> prevPage() async {
    if (currentPage.value > 0) currentPage.value--;
    await _fetchGalleryList();
  }

  Future<void> refresh() => _fetchGalleryList();

  Future<void> loadUrl(String section, {String? tl}) async {
    _currentSection = section;
    _currentSearch = '';
    currentPage.value = 0;
    if (tl != null) _ranklistTl = tl;
    await _fetchGalleryList();
  }

  Map<String, dynamic>? _buildAdvancedParams() {
    final params = <String, dynamic>{};
    bool hasAdvanced = false;

    if (categoryFilter.value != 0) {
      params['f_cats'] = categoryFilter.value.toString();
      hasAdvanced = true;
    }
    if (minimumRating.value > 0) {
      params['advsearch'] = '1';
      params['f_sr'] = 'on';
      params['f_srdd'] = minimumRating.value.toString();
      hasAdvanced = true;
    }
    if (hasAdvanced || !searchInName.value || !searchInTags.value || searchInDesc.value || showExpunged.value) {
      params['advsearch'] = '1';
      if (searchInName.value) params['f_sname'] = 'on';
      if (searchInTags.value) params['f_stags'] = 'on';
      if (searchInDesc.value) params['f_sdesc'] = 'on';
      if (showExpunged.value) params['f_sh'] = 'on';
    }

    return params.isNotEmpty ? params : null;
  }

  Future<void> _fetchGalleryList() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final advParams = _buildAdvancedParams() ?? <String, dynamic>{};
      if (_currentSection == 'ranklist') {
        advParams['tl'] = _ranklistTl;
      }
      final result = await backendApiClient.fetchGalleryList(
        section: _currentSection,
        page: currentPage.value > 0 ? currentPage.value.toString() : null,
        search: _currentSearch.isNotEmpty ? _currentSearch : null,
        advancedParams: advParams.isNotEmpty ? advParams : null,
      );

      final galleryList = (result['galleries'] as List?) ?? [];
      galleries.value = galleryList.cast<Map<String, dynamic>>();

      final nextUrl = result['nextUrl'] as String? ?? '';
      final prevUrl = result['prevUrl'] as String? ?? '';
      hasNextPage.value = nextUrl.isNotEmpty;
      hasPrevPage.value = prevUrl.isNotEmpty;
    } catch (e) {
      errorMessage.value = 'home.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  void toggleCategory(int index) {
    categoryFilter.value ^= _categoryBits[index];
  }

  bool isCategoryEnabled(int index) {
    return (categoryFilter.value & _categoryBits[index]) == 0;
  }

  void cycleListMode() {
    final modes = ['grid', 'list', 'listCompact'];
    final idx = modes.indexOf(listMode.value);
    listMode.value = modes[(idx + 1) % modes.length];
    web.window.localStorage.setItem('jh_web_list_mode', listMode.value);
  }

  IconData get listModeIcon {
    return switch (listMode.value) {
      'list' => Icons.view_list,
      'listCompact' => Icons.view_headline,
      _ => Icons.grid_view,
    };
  }

  void loadQuickSearches() async {
    try {
      quickSearches.value = (await backendApiClient.listQuickSearches()).cast<Map<String, dynamic>>();
    } catch (_) {}
  }

  Future<void> saveCurrentAsQuickSearch(String name) async {
    final config = jsonEncode({
      'keyword': _currentSearch,
      'categoryFilter': categoryFilter.value,
      'minimumRating': minimumRating.value,
      'searchInName': searchInName.value,
      'searchInTags': searchInTags.value,
      'searchInDesc': searchInDesc.value,
      'showExpunged': showExpunged.value,
    });
    await backendApiClient.saveQuickSearch(name, config);
    loadQuickSearches();
  }

  void applyQuickSearch(Map<String, dynamic> item) {
    try {
      final config = jsonDecode(item['config'] as String? ?? '{}') as Map<String, dynamic>;
      final keyword = config['keyword'] as String? ?? '';
      searchController.text = keyword;
      _currentSearch = keyword;
      categoryFilter.value = config['categoryFilter'] as int? ?? 0;
      minimumRating.value = config['minimumRating'] as int? ?? 0;
      searchInName.value = config['searchInName'] as bool? ?? true;
      searchInTags.value = config['searchInTags'] as bool? ?? true;
      searchInDesc.value = config['searchInDesc'] as bool? ?? false;
      showExpunged.value = config['showExpunged'] as bool? ?? false;
      currentPage.value = 0;
      _currentSection = 'home';
      _fetchGalleryList();
    } catch (_) {}
  }

  Future<void> deleteQuickSearch(String name) async {
    await backendApiClient.deleteQuickSearch(name);
    loadQuickSearches();
  }
}

class WebHomePage extends GetView<WebHomeController> {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _TwoPaneHome(controller: controller);
        }
        return _SinglePaneHome(controller: controller);
      },
    );
  }

  static Widget buildHomeContent(BuildContext context, WebHomeController controller, {bool isLeftPane = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: _SearchField(controller: controller)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'home.advancedSearch'.tr,
                onPressed: () => _showAdvancedSearchStatic(context, controller),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => controller.refresh(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
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
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => controller.refresh(),
                      label: Text('common.retry'.tr),
                    ),
                  ],
                ),
              );
            }
            if (controller.galleries.isEmpty) {
              return Center(child: Text('home.noGalleries'.tr));
            }
            return Column(
              children: [
                Expanded(child: _buildGalleryGridStatic(context, controller, isLeftPane: isLeftPane)),
                _buildPaginationBarStatic(context, controller),
              ],
            );
          }),
        ),
      ],
    );
  }

  static void _showAdvancedSearchStatic(BuildContext context, WebHomeController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AdvancedSearchSheet(controller: controller),
    );
  }

  static Widget _buildPaginationBarStatic(BuildContext context, WebHomeController controller) {
    return Obx(() {
      if (!controller.hasPrevPage.value && !controller.hasNextPage.value) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.chevron_left),
              label: Text('home.previous'.tr),
              onPressed: controller.hasPrevPage.value ? controller.prevPage : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('home.page'.trParams({'page': '${controller.currentPage.value + 1}'}),
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
            TextButton.icon(
              icon: const Icon(Icons.chevron_right),
              label: Text('home.next'.tr),
              onPressed: controller.hasNextPage.value ? controller.nextPage : null,
            ),
          ],
        ),
      );
    });
  }

  static Widget _buildGalleryGridStatic(BuildContext context, WebHomeController controller, {bool isLeftPane = false}) {
    return LayoutBuilder(builder: (context, constraints) {
      return Obx(() {
        final mode = controller.listMode.value;
        if (mode == 'list' || mode == 'listCompact' || isLeftPane) {
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: controller.galleries.length,
            itemBuilder: (context, index) {
              final gallery = controller.galleries[index];
              return _GalleryListTile(gallery: gallery, compact: mode == 'listCompact' || isLeftPane, isLeftPane: isLeftPane);
            },
          );
        }
        final crossAxisCount = constraints.maxWidth > 1200 ? 4
            : constraints.maxWidth > 800 ? 3
            : constraints.maxWidth > 500 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: controller.galleries.length,
          itemBuilder: (context, index) {
            final gallery = controller.galleries[index];
            return _GalleryCard(gallery: gallery);
          },
        );
      });
    });
  }

}

class _SinglePaneHome extends StatelessWidget {
  final WebHomeController controller;
  const _SinglePaneHome({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _HomeDrawer(controller: controller),
      appBar: AppBar(
        title: Text('home.title'.tr),
        actions: [
          Obx(() => IconButton(
            icon: Icon(controller.listModeIcon),
            onPressed: controller.cycleListMode,
            tooltip: 'listMode.toggle'.tr,
          )),
          IconButton(
            icon: const Icon(Icons.bookmark),
            onPressed: () => _showQuickSearchDialog(context),
            tooltip: 'quickSearch.title'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Get.toNamed('/web/history'),
            tooltip: 'home.history'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => Get.toNamed('/web/downloads'),
            tooltip: 'home.downloads'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: () => Get.toNamed('/web/local'),
            tooltip: 'home.localGalleries'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Get.toNamed('/web/settings'),
            tooltip: 'home.settings'.tr,
          ),
        ],
      ),
      body: WebHomePage.buildHomeContent(context, controller),
    );
  }

  void _showQuickSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Obx(() {
        final items = controller.quickSearches.toList();
        return AlertDialog(
          title: Text('quickSearch.title'.tr),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('quickSearch.empty'.tr, style: const TextStyle(color: Colors.grey)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final name = item['name'] as String? ?? '';
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.bookmark_outline, size: 20),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(ctx);
                            controller.applyQuickSearch(item);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => controller.deleteQuickSearch(name),
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, size: 20),
                  title: Text('quickSearch.saveCurrent'.tr),
                  onTap: () => _showSaveDialog(ctx),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
          ],
        );
      }),
    );
  }

  void _showSaveDialog(BuildContext parentCtx) {
    final nameController = TextEditingController();
    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        title: Text('quickSearch.saveTitle'.tr),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'quickSearch.nameLabel'.tr,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              controller.saveCurrentAsQuickSearch(v.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                controller.saveCurrentAsQuickSearch(name);
                Navigator.pop(ctx);
              }
            },
            child: Text('common.ok'.tr),
          ),
        ],
      ),
    );
  }
}

class _TwoPaneHome extends StatelessWidget {
  final WebHomeController controller;
  const _TwoPaneHome({required this.controller});

  @override
  Widget build(BuildContext context) {
    final layoutCtrl = Get.find<WebLayoutController>();
    final width = MediaQuery.of(context).size.width;
    final leftWidth = (width * 0.382).clamp(320.0, 480.0);

    return Scaffold(
      drawer: _HomeDrawer(controller: controller),
      appBar: AppBar(
        title: Text('home.title'.tr),
        actions: [
          Obx(() => IconButton(
            icon: Icon(controller.listModeIcon),
            onPressed: controller.cycleListMode,
            tooltip: 'listMode.toggle'.tr,
          )),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Get.toNamed('/web/history'),
            tooltip: 'home.history'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => Get.toNamed('/web/downloads'),
            tooltip: 'home.downloads'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Get.toNamed('/web/settings'),
            tooltip: 'home.settings'.tr,
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: leftWidth,
            child: WebHomePage.buildHomeContent(context, controller, isLeftPane: true),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Obx(() {
              final gid = layoutCtrl.selectedGid.value;
              final token = layoutCtrl.selectedToken.value;
              if (gid == null || token == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('home.selectGallery'.tr,
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }
              return _EmbeddedDetailPanel(key: ValueKey('detail_${gid}_$token'), gid: gid, token: token);
            }),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedDetailPanel extends StatefulWidget {
  final int gid;
  final String token;
  const _EmbeddedDetailPanel({super.key, required this.gid, required this.token});

  @override
  State<_EmbeddedDetailPanel> createState() => _EmbeddedDetailPanelState();
}

class _EmbeddedDetailPanelState extends State<_EmbeddedDetailPanel> {
  late WebGalleryDetailController _ctrl;
  final String _tag = 'embedded_detail';

  @override
  void initState() {
    super.initState();
    _ctrl = Get.put(
      WebGalleryDetailController(gid: widget.gid, token: widget.token),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<WebGalleryDetailController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebGalleryDetailPage(controllerTag: _tag);
  }
}

class _HomeDrawer extends StatelessWidget {
  final WebHomeController controller;
  const _HomeDrawer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('home.title'.tr,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('home.subtitle'.tr,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: Text('home.home'.tr),
            onTap: () {
              Navigator.pop(context);
              controller.refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_fire_department),
            title: Text('home.popular'.tr),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('popular');
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: Text('home.favorites'.tr),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('favorites');
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility),
            title: Text('home.watched'.tr),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('watched');
            },
          ),
          ListTile(
            leading: const Icon(Icons.leaderboard),
            title: Text('home.ranklist'.tr),
            onTap: () {
              Navigator.pop(context);
              _showRanklistPicker(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('home.history'.tr),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/history');
            },
          ),
          Obx(() {
            final qsList = controller.quickSearches.toList();
            if (qsList.isEmpty) return const SizedBox.shrink();
            return ExpansionTile(
              leading: const Icon(Icons.bookmark),
              title: Text('quickSearch.title'.tr),
              children: qsList.map((item) {
                final name = item['name'] as String? ?? '';
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    controller.applyQuickSearch(item);
                  },
                );
              }).toList(),
            );
          }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.download),
            title: Text('home.downloads'.tr),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/downloads');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: Text('home.localGalleries'.tr),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/local');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text('home.settings'.tr),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/settings');
            },
          ),
        ],
      ),
    );
  }

  void _showRanklistPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('ranklist.title'.tr),
        children: [
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); controller.loadUrl('ranklist', tl: '15'); },
            child: Text('ranklist.allTime'.tr),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); controller.loadUrl('ranklist', tl: '13'); },
            child: Text('ranklist.year'.tr),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); controller.loadUrl('ranklist', tl: '12'); },
            child: Text('ranklist.month'.tr),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); controller.loadUrl('ranklist', tl: '11'); },
            child: Text('ranklist.yesterday'.tr),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSearchSheet extends StatelessWidget {
  final WebHomeController controller;
  const _AdvancedSearchSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('home.categoryFilter'.tr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Obx(() => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(WebHomeController._categoryKeys.length, (i) {
                  final enabled = controller.isCategoryEnabled(i);
                  return FilterChip(
                    label: Text(WebHomeController._categoryKeys[i].tr),
                    selected: enabled,
                    onSelected: (_) => controller.toggleCategory(i),
                    selectedColor: _chipColor(i),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: enabled ? Colors.white : null,
                      fontSize: 12,
                    ),
                  );
                }),
              )),
              const SizedBox(height: 20),
              Text('home.minimumRating'.tr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Obx(() => Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: controller.minimumRating.value.toDouble(),
                      min: 0, max: 5, divisions: 5,
                      label: controller.minimumRating.value == 0
                          ? 'home.ratingAny'.tr
                          : '${controller.minimumRating.value}+',
                      onChanged: (v) => controller.minimumRating.value = v.round(),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      controller.minimumRating.value == 0 ? 'home.ratingAny'.tr : '${controller.minimumRating.value}+',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              )),
              const SizedBox(height: 16),
              Text('home.searchIn'.tr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Obx(() => Column(
                children: [
                  CheckboxListTile(
                    title: Text('home.galleryName'.tr),
                    value: controller.searchInName.value,
                    onChanged: (v) => controller.searchInName.value = v ?? true,
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.tags'.tr),
                    value: controller.searchInTags.value,
                    onChanged: (v) => controller.searchInTags.value = v ?? true,
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.description'.tr),
                    value: controller.searchInDesc.value,
                    onChanged: (v) => controller.searchInDesc.value = v ?? false,
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.showExpunged'.tr),
                    value: controller.showExpunged.value,
                    onChanged: (v) => controller.showExpunged.value = v ?? false,
                    dense: true,
                  ),
                ],
              )),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        controller.categoryFilter.value = 0;
                        controller.minimumRating.value = 0;
                        controller.searchInName.value = true;
                        controller.searchInTags.value = true;
                        controller.searchInDesc.value = false;
                        controller.showExpunged.value = false;
                      },
                      child: Text('common.reset'.tr),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        controller.search(controller.searchController.text);
                      },
                      child: Text('home.applySearch'.tr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _chipColor(int index) {
    const colors = [
      Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.teal,
      Colors.blue, Colors.indigo, Colors.purple, Colors.pink, Colors.grey,
    ];
    return colors[index % colors.length];
  }
}

class _SearchSuggestion {
  final String text;
  final String displayText;
  final bool isTag;
  final String? tagNamespace;

  const _SearchSuggestion({required this.text, required this.displayText, this.isTag = false, this.tagNamespace});
}

class _SearchField extends StatefulWidget {
  final WebHomeController controller;
  const _SearchField({required this.controller});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _focusNode = FocusNode();
  List<_SearchSuggestion> _suggestions = [];
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.searchController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.searchController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _onTextChanged();
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _onTextChanged() async {
    final text = widget.controller.searchController.text;
    final suggestions = <_SearchSuggestion>[];

    final history = widget.controller.searchHistory.toList();
    final query = text.toLowerCase();

    if (query.isEmpty) {
      for (final h in history.take(8)) {
        suggestions.add(_SearchSuggestion(text: h, displayText: h));
      }
    } else {
      for (final h in history.where((s) => s.toLowerCase().contains(query)).take(5)) {
        suggestions.add(_SearchSuggestion(text: h, displayText: h));
      }

      final lastToken = _extractLastToken(text);
      if (lastToken.length >= 2) {
        try {
          final tagResults = await backendApiClient.searchTags(lastToken, limit: 8);
          for (final tag in tagResults) {
            final ns = tag['namespace']?.toString() ?? '';
            final key = tag['key']?.toString() ?? '';
            final tagName = tag['tag_name']?.toString() ?? key;
            final display = '$ns:$tagName';
            final insertText = '$ns:"$key\$"';
            suggestions.add(_SearchSuggestion(
              text: insertText,
              displayText: display,
              isTag: true,
              tagNamespace: ns,
            ));
          }
        } catch (_) {}
      }
    }

    _suggestions = suggestions;
    if (suggestions.isNotEmpty && _focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  String _extractLastToken(String text) {
    final trimmed = text.trimRight();
    final lastSpace = trimmed.lastIndexOf(' ');
    return lastSpace >= 0 ? trimmed.substring(lastSpace + 1) : trimmed;
  }

  String _replaceLastToken(String text, String replacement) {
    final trimmed = text.trimRight();
    final lastSpace = trimmed.lastIndexOf(' ');
    if (lastSpace >= 0) {
      return '${trimmed.substring(0, lastSpace + 1)}$replacement ';
    }
    return '$replacement ';
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(builder: (context) {
      return Positioned(
        width: 500,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 350),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final s = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(s.isTag ? Icons.label : Icons.history, size: 18),
                          title: Text(s.displayText, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: s.isTag ? Text(s.text, style: const TextStyle(fontSize: 11, color: Colors.grey)) : null,
                          onTap: () {
                            if (s.isTag) {
                              widget.controller.searchController.text =
                                  _replaceLastToken(widget.controller.searchController.text, s.text);
                              widget.controller.searchController.selection = TextSelection.collapsed(
                                  offset: widget.controller.searchController.text.length);
                            } else {
                              widget.controller.searchController.text = s.text;
                            }
                            _removeOverlay();
                            if (!s.isTag) widget.controller.search(s.text);
                          },
                          trailing: s.isTag
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    backendApiClient.deleteSearchHistoryItem(s.text).catchError((_) {});
                                    widget.controller.searchHistory.remove(s.text);
                                    _onTextChanged();
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                  if (_suggestions.any((s) => !s.isTag))
                    InkWell(
                      onTap: () {
                        backendApiClient.clearSearchHistory().catchError((_) {});
                        widget.controller.searchHistory.clear();
                        _removeOverlay();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('searchHistory.clearAll'.tr,
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller.searchController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: 'home.search'.tr,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: (value) {
          _removeOverlay();
          widget.controller.search(value);
        },
      ),
    );
  }
}

class _GalleryListTile extends StatelessWidget {
  final Map<String, dynamic> gallery;
  final bool compact;
  final bool isLeftPane;

  const _GalleryListTile({required this.gallery, this.compact = false, this.isLeftPane = false});

  @override
  Widget build(BuildContext context) {
    final title = gallery['title'] as String? ?? '';
    final category = gallery['category'] as String? ?? '';
    final gid = gallery['gid'];
    final token = gallery['token'];
    final coverUrl = gallery['coverUrl'] as String? ?? '';
    final uploader = gallery['uploader'] as String? ?? '';
    final rating = (gallery['rating'] as num?)?.toDouble() ?? 0;
    final pageCount = gallery['pageCount'] as int? ?? 0;
    final tags = gallery['tags'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isLeftPane) {
            Get.find<WebLayoutController>().selectGallery(gid as int, token as String);
          } else {
            Get.toNamed('/web/gallery/$gid/$token');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverWithBadge(
                coverUrl: coverUrl,
                gid: gid is int ? gid : 0,
                width: 80,
                height: compact ? 80 : 110,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _categoryColor(category),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(category, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        if (uploader.isNotEmpty)
                          Text(uploader, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(rating.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        Text('${pageCount}P', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                    if (!compact && tags != null && tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: _buildTagChips(tags).take(12).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTagChips(Map<String, dynamic> tags) {
    final chips = <Widget>[];
    for (final entry in tags.entries) {
      final tagList = entry.value;
      if (tagList is List) {
        for (final tag in tagList) {
          chips.add(Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(tag.toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ));
        }
      }
    }
    return chips;
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
}

class _GalleryCard extends StatelessWidget {
  final Map<String, dynamic> gallery;

  const _GalleryCard({required this.gallery});

  @override
  Widget build(BuildContext context) {
    final title = gallery['title'] as String? ?? '';
    final category = gallery['category'] as String? ?? '';
    final gid = gallery['gid'];
    final token = gallery['token'];
    final coverUrl = gallery['coverUrl'] as String? ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed('/web/gallery/$gid/$token'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: _categoryColor(category),
              child: Text(
                category,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl.isNotEmpty
                      ? Image.network(
                          backendApiClient.proxyImageUrl(coverUrl),
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 32, color: Colors.grey),
                            ),
                          ),
                        )
                      : Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.photo_library, size: 48, color: Colors.grey),
                          ),
                        ),
                  _DownloadBadgeOverlay(gid: gid is int ? gid : 0),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
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
}

class _CoverWithBadge extends StatelessWidget {
  final String coverUrl;
  final int gid;
  final double width;
  final double height;

  const _CoverWithBadge({required this.coverUrl, required this.gid, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverUrl.isNotEmpty
                ? Image.network(
                    backendApiClient.proxyImageUrl(coverUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                    ),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.photo_library, size: 24, color: Colors.grey),
                  ),
            _DownloadBadgeOverlay(gid: gid),
          ],
        ),
      ),
    );
  }
}

class _DownloadBadgeOverlay extends StatelessWidget {
  final int gid;
  const _DownloadBadgeOverlay({required this.gid});

  @override
  Widget build(BuildContext context) {
    if (gid == 0) return const SizedBox.shrink();
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      final _ = svc.galleryTasks.length;
      final status = svc.getGalleryStatus(gid);
      if (status == null) return const SizedBox.shrink();

      final IconData icon;
      final Color bgColor;
      final Color iconColor;

      switch (status) {
        case 1:
          icon = Icons.downloading;
          bgColor = Colors.blue;
          iconColor = Colors.white;
        case 2:
          icon = Icons.pause;
          bgColor = Colors.orange;
          iconColor = Colors.white;
        case 3:
          icon = Icons.check_circle;
          bgColor = Colors.green;
          iconColor = Colors.white;
        case 4:
          icon = Icons.error;
          bgColor = Colors.red;
          iconColor = Colors.white;
        default:
          return const SizedBox.shrink();
      }

      return Positioned(
        right: 4,
        bottom: 4,
        child: Tooltip(
          message: 'downloads.gStatus$status'.tr,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
        ),
      );
    });
  }
}
