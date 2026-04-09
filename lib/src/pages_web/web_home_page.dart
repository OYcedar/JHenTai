import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

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

  static const _categoryKeys = [
    'category.doujinshi', 'category.manga', 'category.artistCg', 'category.gameCg', 'category.western',
    'category.nonH', 'category.imageSet', 'category.cosplay', 'category.asianPorn', 'category.misc',
  ];
  static const _categoryBits = [2, 4, 8, 16, 512, 256, 32, 64, 1024, 1];

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map<String, dynamic> && args['search'] is String) {
      final searchQuery = args['search'] as String;
      searchController.text = searchQuery;
      _currentSearch = searchQuery;
    }
    _loadHomePage();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  String _currentSection = 'home';
  String _currentSearch = '';

  Future<void> _loadHomePage() async {
    _currentSection = 'home';
    if (_currentSearch.isEmpty) _currentSearch = '';
    await _fetchGalleryList();
  }

  Future<void> search(String keyword) async {
    _currentSearch = keyword;
    _currentSection = 'home';
    currentPage.value = 0;
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

  Future<void> loadUrl(String section) async {
    _currentSection = section;
    _currentSearch = '';
    currentPage.value = 0;
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
      final result = await backendApiClient.fetchGalleryList(
        section: _currentSection,
        page: currentPage.value > 0 ? currentPage.value.toString() : null,
        search: _currentSearch.isNotEmpty ? _currentSearch : null,
        advancedParams: _buildAdvancedParams(),
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
}

class WebHomePage extends GetView<WebHomeController> {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: Text('home.title'.tr),
        actions: [
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.searchController,
                    decoration: InputDecoration(
                      hintText: 'home.search'.tr,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (value) => controller.search(value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'home.advancedSearch'.tr,
                  onPressed: () => _showAdvancedSearch(context),
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
                  Expanded(child: _buildGalleryGrid(context)),
                  _buildPaginationBar(context),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showAdvancedSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AdvancedSearchSheet(controller: controller),
    );
  }

  Widget _buildDrawer(BuildContext context) {
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

  Widget _buildPaginationBar(BuildContext context) {
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

  Widget _buildGalleryGrid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = constraints.maxWidth > 1200 ? 4
          : constraints.maxWidth > 800 ? 3
          : constraints.maxWidth > 500 ? 2 : 1;

      return Obx(() => GridView.builder(
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
      ));
    });
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
              child: coverUrl.isNotEmpty
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
