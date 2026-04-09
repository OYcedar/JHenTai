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

  @override
  void onInit() {
    super.onInit();
    _loadHomePage();
  }

  String _currentSection = 'home';
  String _currentSearch = '';

  Future<void> _loadHomePage() async {
    _currentSection = 'home';
    _currentSearch = '';
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

  Future<void> _fetchGalleryList() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchGalleryList(
        section: _currentSection,
        page: currentPage.value > 0 ? currentPage.value.toString() : null,
        search: _currentSearch.isNotEmpty ? _currentSearch : null,
      );

      final galleryList = (result['galleries'] as List?) ?? [];
      galleries.value = galleryList.cast<Map<String, dynamic>>();

      final nextUrl = result['nextUrl'] as String? ?? '';
      final prevUrl = result['prevUrl'] as String? ?? '';
      hasNextPage.value = nextUrl.isNotEmpty;
      hasPrevPage.value = prevUrl.isNotEmpty;
    } catch (e) {
      errorMessage.value = 'Failed to load: $e';
    } finally {
      isLoading.value = false;
    }
  }
}

class WebHomePage extends GetView<WebHomeController> {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text('JHenTai'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => Get.toNamed('/web/downloads'),
            tooltip: 'Downloads',
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: () => Get.toNamed('/web/local'),
            tooltip: 'Local Galleries',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Get.toNamed('/web/settings'),
            tooltip: 'Settings',
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
                      hintText: 'Search galleries...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (value) => controller.search(value),
                  ),
                ),
                const SizedBox(width: 8),
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
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              if (controller.galleries.isEmpty) {
                return const Center(child: Text('No galleries found'));
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
                Text('JHenTai',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('E-Hentai Client',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              controller.refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_fire_department),
            title: const Text('Popular'),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('popular');
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: const Text('Favorites'),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('favorites');
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('Watched'),
            onTap: () {
              Navigator.pop(context);
              controller.loadUrl('watched');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Downloads'),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/downloads');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Local Galleries'),
            onTap: () {
              Navigator.pop(context);
              Get.toNamed('/web/local');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
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
              label: const Text('Previous'),
              onPressed: controller.hasPrevPage.value ? controller.prevPage : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Page ${controller.currentPage.value + 1}',
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
            TextButton.icon(
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
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
