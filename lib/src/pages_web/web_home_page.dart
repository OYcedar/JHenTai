import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/consts/locale_consts.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_gallery_detail_page.dart';
import 'package:jhentai/src/pages_web/web_watched_tag_styles_controller.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

class WebHomeController extends GetxController {
  final searchController = TextEditingController();
  final galleries = <Map<String, dynamic>>[].obs;
  /// Keys `namespace:tagKey` → translated name (from `/api/tag/batch`, same as gallery detail).
  final tagTranslations = <String, String>{}.obs;
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

  /// EH `language:"..."` tag keys (same as native [SearchConfig.language]), excluding `japanese` from picker.
  final filterLanguage = Rxn<String>();
  final disableFilterForLanguage = false.obs;

  static final List<String> searchLanguageKeys = LocaleConsts.language2Abbreviation.keys
      .where((k) => k != 'japanese')
      .toList();

  // List mode: grid, list, listCompact
  final listMode = 'grid'.obs;

  // Scroll-to-top FAB
  final scrollController = ScrollController();
  final showFab = false.obs;

  // Quick search
  final quickSearches = <Map<String, dynamic>>[].obs;

  static const _categoryKeys = [
    'category.doujinshi', 'category.manga', 'category.artistCg', 'category.gameCg', 'category.western',
    'category.nonH', 'category.imageSet', 'category.cosplay', 'category.asianPorn', 'category.misc',
  ];

  /// Bit = excluded category. Must match [SearchConfig._computeFCats] / EH (Asian Porn = 128, not 1024).
  static const _categoryBits = [2, 4, 8, 16, 512, 256, 32, 64, 128, 1];

  static const _advancedSearchStorageKey = 'jh_web_advanced_search';
  static const _favSortStorageKey = 'jh_web_fav_sort';
  static const _favCatStorageKey = 'jh_web_fav_cat';

  @override
  void onInit() {
    super.onInit();
    final savedMode = web.window.localStorage.getItem('jh_web_list_mode');
    if (savedMode != null && ['grid', 'list', 'listCompact'].contains(savedMode)) {
      listMode.value = savedMode;
    }
    _loadAdvancedSearchFromStorage();
    _loadFavoritesListPrefs();
    final args = Get.arguments;
    if (args is Map<String, dynamic> && args['search'] is String) {
      final searchQuery = args['search'] as String;
      searchController.text = searchQuery;
      _currentSearch = searchQuery;
    }
    _loadHomePage();
    loadSearchHistory();
    loadQuickSearches();
    scrollController.addListener(_onScroll);
    unawaited(Get.find<WebWatchedTagStylesController>().refresh());
  }

  void _loadAdvancedSearchFromStorage() {
    final raw = web.window.localStorage.getItem(_advancedSearchStorageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      var cf = (m['categoryFilter'] as num?)?.toInt() ?? 0;
      // Older Web builds used 1024 for Asian Porn; EH uses 128 (see SearchConfig._computeFCats).
      if ((cf & 1024) != 0) {
        cf = (cf & ~1024) | 128;
      }
      categoryFilter.value = cf;
      minimumRating.value = (m['minimumRating'] as num?)?.toInt() ?? 0;
      searchInName.value = m['searchInName'] as bool? ?? true;
      searchInTags.value = m['searchInTags'] as bool? ?? true;
      searchInDesc.value = m['searchInDesc'] as bool? ?? false;
      showExpunged.value = m['showExpunged'] as bool? ?? false;
      final lang = m['filterLanguage'] as String?;
      filterLanguage.value = (lang != null && lang.isNotEmpty) ? lang : null;
      disableFilterForLanguage.value = m['disableFilterForLanguage'] as bool? ?? false;
    } catch (_) {}
  }

  /// Persists category bitmask and advanced search toggles across reloads.
  void persistAdvancedSearchSettings() {
    web.window.localStorage.setItem(
      _advancedSearchStorageKey,
      jsonEncode({
        'categoryFilter': categoryFilter.value,
        'minimumRating': minimumRating.value,
        'searchInName': searchInName.value,
        'searchInTags': searchInTags.value,
        'searchInDesc': searchInDesc.value,
        'showExpunged': showExpunged.value,
        'filterLanguage': filterLanguage.value,
        'disableFilterForLanguage': disableFilterForLanguage.value,
      }),
    );
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    super.onClose();
  }

  void _onScroll() {
    showFab.value = scrollController.hasClients && scrollController.offset > 300;
  }

  /// Gallery list section: `home`, `popular`, `favorites`, etc. Filters apply only on [home].
  final currentSection = 'home'.obs;
  String _currentSearch = '';
  String _ranklistTl = '15';

  /// EH file lookup → [fetchGalleryListByUrl] pagination chain.
  final listByUrlMode = false.obs;
  final listByUrlHumanPage = 1.obs;
  String? _listByUrlActiveUrl;
  String? _listByUrlNextUrl;
  String? _listByUrlPrevUrl;

  void _exitListByUrlMode() {
    listByUrlMode.value = false;
    _listByUrlActiveUrl = null;
    _listByUrlNextUrl = null;
    _listByUrlPrevUrl = null;
    listByUrlHumanPage.value = 1;
  }

  Future<void> exitImageSearchMode() async {
    if (!listByUrlMode.value) return;
    _exitListByUrlMode();
    currentPage.value = 0;
    await _fetchGalleryList();
  }

  Future<void> pickImageAndSearch() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      Get.snackbar('common.error'.tr, 'home.imageSearchFailed'.trParams({'error': 'empty file'}),
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final b64 = base64Encode(bytes);
      final redirect = await backendApiClient.imageLookupBase64(b64, filename: f.name);
      if (redirect == null || redirect.isEmpty) {
        Get.snackbar('common.error'.tr, 'home.imageSearchFailed'.trParams({'error': 'no redirect'}),
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      listByUrlMode.value = true;
      currentPage.value = 0;
      listByUrlHumanPage.value = 1;
      _currentSearch = '';
      searchController.clear();
      currentSection.value = 'home';
      await _fetchListByUrl(redirect);
    } catch (e) {
      Get.snackbar('common.error'.tr, 'home.imageSearchFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchListByUrl(String url) async {
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchGalleryListByUrl(url);
      final galleryList = (result['galleries'] as List?) ?? [];
      galleries.value = galleryList.cast<Map<String, dynamic>>();
      unawaited(_fetchGalleryListTagTranslations());
      _listByUrlActiveUrl = url;
      _listByUrlNextUrl = result['nextUrl'] as String?;
      _listByUrlPrevUrl = result['prevUrl'] as String?;
      hasNextPage.value = (_listByUrlNextUrl ?? '').isNotEmpty;
      hasPrevPage.value = (_listByUrlPrevUrl ?? '').isNotEmpty;
    } catch (e) {
      errorMessage.value = 'home.loadFailed'.trParams({'error': '$e'});
    }
  }

  /// Favorites list only: `true` = fs_f (by favorited time), `false` = fs_p (by published time).
  final favoriteSortFavoritedFirst = true.obs;
  /// `null` = all folders; `0`–`9` = one EH favorite category.
  final favoriteCategoryFilter = Rxn<int>();
  /// Labels for the favorites folder strip (from EH).
  final favoriteFolderNames = <String>[].obs;

  final searchHistory = <String>[].obs;

  void _loadFavoritesListPrefs() {
    final sort = web.window.localStorage.getItem(_favSortStorageKey);
    if (sort == 'fs_p') {
      favoriteSortFavoritedFirst.value = false;
    }
    final cat = web.window.localStorage.getItem(_favCatStorageKey);
    if (cat != null && cat.isNotEmpty) {
      final n = int.tryParse(cat);
      if (n != null && n >= 0 && n <= 9) {
        favoriteCategoryFilter.value = n;
      }
    }
  }

  void persistFavoritesListPrefs() {
    web.window.localStorage.setItem(
      _favSortStorageKey,
      favoriteSortFavoritedFirst.value ? 'fs_f' : 'fs_p',
    );
    final c = favoriteCategoryFilter.value;
    if (c == null) {
      web.window.localStorage.removeItem(_favCatStorageKey);
    } else {
      web.window.localStorage.setItem(_favCatStorageKey, '$c');
    }
  }

  Future<void> _ensureFavoriteFolderNames() async {
    if (favoriteFolderNames.isNotEmpty) return;
    try {
      final f = await backendApiClient.fetchFavoriteFolders();
      favoriteFolderNames.value = List<String>.from(f.names);
    } catch (_) {}
  }

  Future<void> reloadFavoriteFolderNames() async {
    try {
      final f = await backendApiClient.fetchFavoriteFolders();
      favoriteFolderNames.value = List<String>.from(f.names);
    } catch (_) {}
  }

  void loadSearchHistory() async {
    try {
      final items = await backendApiClient.fetchSearchHistory();
      searchHistory.value = items.map((e) => (e['keyword'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
    } catch (_) {}
  }

  Future<void> _loadHomePage() async {
    _exitListByUrlMode();
    currentSection.value = 'home';
    if (_currentSearch.isEmpty) _currentSearch = '';
    await _fetchGalleryList();
  }

  Future<void> search(String keyword) async {
    _exitListByUrlMode();
    _currentSearch = keyword;
    currentSection.value = 'home';
    currentPage.value = 0;
    if (keyword.trim().isNotEmpty) {
      backendApiClient.recordSearchHistory(keyword.trim()).catchError((_) {});
      loadSearchHistory();
    }
    await _fetchGalleryList();
  }

  Future<void> nextPage() async {
    if (listByUrlMode.value) {
      final next = _listByUrlNextUrl;
      if (next == null || next.isEmpty) return;
      listByUrlHumanPage.value++;
      isLoading.value = true;
      try {
        await _fetchListByUrl(next);
      } finally {
        isLoading.value = false;
      }
      return;
    }
    currentPage.value++;
    await _fetchGalleryList();
  }

  Future<void> prevPage() async {
    if (listByUrlMode.value) {
      final prev = _listByUrlPrevUrl;
      if (prev == null || prev.isEmpty) return;
      if (listByUrlHumanPage.value > 1) listByUrlHumanPage.value--;
      isLoading.value = true;
      try {
        await _fetchListByUrl(prev);
      } finally {
        isLoading.value = false;
      }
      return;
    }
    if (currentPage.value > 0) currentPage.value--;
    await _fetchGalleryList();
  }

  Future<void> refresh() async {
    if (listByUrlMode.value) {
      final u = _listByUrlActiveUrl;
      if (u != null && u.isNotEmpty) {
        isLoading.value = true;
        await _fetchListByUrl(u);
        isLoading.value = false;
      }
      return;
    }
    await _fetchGalleryList();
  }

  Future<void> loadUrl(String section, {String? tl}) async {
    _exitListByUrlMode();
    currentSection.value = section;
    _currentSearch = '';
    currentPage.value = 0;
    if (tl != null) _ranklistTl = tl;
    await _fetchGalleryList();
  }

  /// Native [SearchConfig.toQueryParameters]: append ` language:"$key"` to `f_search`.
  String _composeFSearch(String keyword) {
    final base = keyword.trim();
    final lang = filterLanguage.value;
    if (lang == null || lang.isEmpty) return base;
    return '${base.isEmpty ? '' : base} language:"$lang"';
  }

  Map<String, dynamic>? _buildAdvancedParams() {
    if (currentSection.value == 'watched') {
      if (!disableFilterForLanguage.value) return null;
      return {'f_sfl': 'on'};
    }
    if (currentSection.value != 'home') return null;

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
    if (disableFilterForLanguage.value) {
      params['f_sfl'] = 'on';
    }

    return params.isNotEmpty ? params : null;
  }

  Future<void> _fetchGalleryList() async {
    if (listByUrlMode.value) {
      final u = _listByUrlActiveUrl;
      if (u != null && u.isNotEmpty) {
        isLoading.value = true;
        errorMessage.value = '';
        try {
          await _fetchListByUrl(u);
        } finally {
          isLoading.value = false;
        }
      }
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      if (currentSection.value == 'favorites') {
        await _ensureFavoriteFolderNames();
      }
      final advParams = _buildAdvancedParams() ?? <String, dynamic>{};
      if (currentSection.value == 'ranklist') {
        advParams['tl'] = _ranklistTl;
      }
      String? favSort;
      int? favcat;
      if (currentSection.value == 'favorites') {
        favSort = favoriteSortFavoritedFirst.value ? 'fs_f' : 'fs_p';
        favcat = favoriteCategoryFilter.value;
      }
      final composedSearch = _composeFSearch(_currentSearch);
      final result = await backendApiClient.fetchGalleryList(
        section: currentSection.value,
        page: currentPage.value > 0 ? currentPage.value.toString() : null,
        search: composedSearch.isNotEmpty ? composedSearch : null,
        advancedParams: advParams.isNotEmpty ? advParams : null,
        favSort: favSort,
        favcat: favcat,
      );

      final galleryList = (result['galleries'] as List?) ?? [];
      galleries.value = galleryList.cast<Map<String, dynamic>>();
      unawaited(_fetchGalleryListTagTranslations());

      final nextUrl = result['nextUrl'] as String? ?? '';
      // Do not rely only on parsed prevUrl — on many EH layouts the < link is easy to miss;
      // we drive page index ourselves, so "previous" is available whenever not on first page.
      hasNextPage.value = nextUrl.isNotEmpty;
      hasPrevPage.value = currentPage.value > 0;
    } catch (e) {
      errorMessage.value = 'home.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchGalleryListTagTranslations() async {
    final pending = <String, Map<String, String>>{};
    for (final g in galleries) {
      final rawTags = g['tags'] as Map<String, dynamic>?;
      if (rawTags == null) continue;
      for (final e in rawTags.entries) {
        final ns = e.key.toString();
        final list = e.value;
        if (list is! List) continue;
        for (final item in list) {
          final key = _parseTagListEntryKey(item);
          if (key.isEmpty) continue;
          final mk = '$ns:$key';
          if (tagTranslations.containsKey(mk)) continue;
          pending[mk] = {'namespace': ns, 'key': key};
        }
      }
    }
    if (pending.isEmpty) return;
    final batch = pending.values.toList();
    const chunkSize = 120;
    for (var i = 0; i < batch.length; i += chunkSize) {
      final end = i + chunkSize > batch.length ? batch.length : i + chunkSize;
      final slice = batch.sublist(i, end);
      try {
        final tr = await backendApiClient.translateTags(slice);
        if (tr.isNotEmpty) {
          tagTranslations.addAll(tr);
          tagTranslations.refresh();
        }
      } catch (_) {}
    }
  }

  void toggleCategory(int index) {
    categoryFilter.value ^= _categoryBits[index];
    persistAdvancedSearchSettings();
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
      'filterLanguage': filterLanguage.value,
      'disableFilterForLanguage': disableFilterForLanguage.value,
    });
    await backendApiClient.saveQuickSearch(name, config);
    loadQuickSearches();
  }

  void applyQuickSearch(Map<String, dynamic> item) {
    try {
      _exitListByUrlMode();
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
      final lang = config['filterLanguage'] as String?;
      filterLanguage.value = (lang != null && lang.isNotEmpty) ? lang : null;
      disableFilterForLanguage.value = config['disableFilterForLanguage'] as bool? ?? false;
      currentPage.value = 0;
      currentSection.value = 'home';
      persistAdvancedSearchSettings();
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
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: _SearchField(controller: controller)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.image_search),
                    tooltip: 'home.imageSearch'.tr,
                    onPressed: controller.pickImageAndSearch,
                  ),
                  Obx(() {
                    if (controller.currentSection.value != 'home') {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      icon: const Icon(Icons.tune),
                      tooltip: 'home.searchFilterSheetTitle'.tr,
                      onPressed: () => _showAdvancedSearchStatic(context, controller),
                    );
                  }),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => controller.refresh(),
                  ),
                ],
              ),
            ),
            Obx(() {
              if (!controller.listByUrlMode.value) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.image_search, size: 18),
                    label: Text('home.imageSearchMode'.tr),
                    onDeleted: () => controller.exitImageSearchMode(),
                  ),
                ),
              );
            }),
            Obx(() {
              if (controller.currentSection.value != 'favorites') {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sort),
                      tooltip: 'home.favSortTitle'.tr,
                      onPressed: () => _showFavoriteSortDialog(context, controller),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Obx(() => Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: FilterChip(
                                    label: Text('home.favAllFolders'.tr),
                                    selected: controller.favoriteCategoryFilter.value == null,
                                    onSelected: (_) {
                                      controller.favoriteCategoryFilter.value = null;
                                      controller.persistFavoritesListPrefs();
                                      controller.currentPage.value = 0;
                                      controller.refresh();
                                    },
                                  ),
                                ),
                                ...List.generate(10, (i) {
                                  final name = controller.favoriteFolderNames.length > i
                                      ? controller.favoriteFolderNames[i]
                                      : 'home.favSlotShort'.trParams({'n': '$i'});
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: FilterChip(
                                      label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      selected: controller.favoriteCategoryFilter.value == i,
                                      onSelected: (_) {
                                        controller.favoriteCategoryFilter.value = i;
                                        controller.persistFavoritesListPrefs();
                                        controller.currentPage.value = 0;
                                        controller.refresh();
                                      },
                                    ),
                                  );
                                }),
                              ],
                            )),
                      ),
                    ),
                  ],
                ),
              );
            }),
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
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => controller.refresh(),
                        child: _buildGalleryGridStatic(context, controller, isLeftPane: isLeftPane),
                      ),
                    ),
                    _buildPaginationBarStatic(context, controller),
                  ],
                );
              }),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Obx(() => controller.showFab.value
              ? FloatingActionButton.small(
                  onPressed: () => controller.scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                  ),
                  child: const Icon(Icons.arrow_upward),
                )
              : const SizedBox.shrink()),
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

  static void _showFavoriteSortDialog(BuildContext context, WebHomeController controller) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        var sortFavoritedFirst = controller.favoriteSortFavoritedFirst.value;
        return StatefulBuilder(
          builder: (context, setSt) => AlertDialog(
            title: Text('home.favSortTitle'.tr),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  title: Text('home.favSortFavorited'.tr),
                  value: true,
                  groupValue: sortFavoritedFirst,
                  onChanged: (v) {
                    if (v != null) setSt(() => sortFavoritedFirst = v);
                  },
                ),
                RadioListTile<bool>(
                  title: Text('home.favSortPublished'.tr),
                  value: false,
                  groupValue: sortFavoritedFirst,
                  onChanged: (v) {
                    if (v != null) setSt(() => sortFavoritedFirst = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common.cancel'.tr)),
              FilledButton(
                onPressed: () {
                  controller.favoriteSortFavoritedFirst.value = sortFavoritedFirst;
                  controller.persistFavoritesListPrefs();
                  controller.currentPage.value = 0;
                  Navigator.pop(ctx);
                  controller.refresh();
                },
                child: Text('common.ok'.tr),
              ),
            ],
          ),
        );
      },
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
              child: Text(
                  'home.page'.trParams({
                    'page': '${controller.listByUrlMode.value ? controller.listByUrlHumanPage.value : controller.currentPage.value + 1}',
                  }),
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
        if (mode == 'list' || mode == 'listCompact') {
          return ListView.builder(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: controller.galleries.length,
            itemBuilder: (context, index) {
              final gallery = controller.galleries[index];
              return _GalleryListTile(
                gallery: gallery,
                homeController: controller,
                compact: mode == 'listCompact',
                isLeftPane: isLeftPane,
              );
            },
          );
        }
        final crossAxisCount = isLeftPane
            ? (constraints.maxWidth >= 420 ? 2 : 1)
            : constraints.maxWidth > 1200
                ? 4
                : constraints.maxWidth > 800
                    ? 3
                    : constraints.maxWidth > 500
                        ? 2
                        : 1;
        return GridView.builder(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
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
            return _GalleryCard(
              gallery: gallery,
              homeController: controller,
              isLeftPane: isLeftPane,
            );
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

class _TwoPaneHome extends StatefulWidget {
  final WebHomeController controller;
  const _TwoPaneHome({required this.controller});

  @override
  State<_TwoPaneHome> createState() => _TwoPaneHomeState();
}

class _TwoPaneHomeState extends State<_TwoPaneHome> {
  static const _leftWidthStorageKey = 'jh_web_two_pane_left_width';
  late double _leftPaneWidth;
  bool _didInitWidth = false;

  WebHomeController get controller => widget.controller;

  static double _clampLeftWidth(double v, double screenW) {
    const minW = 260.0;
    final maxW = math.max(minW, screenW - 300.0);
    return v.clamp(minW, maxW);
  }

  /// Default left column width (same rule as first launch without saved prefs).
  static double defaultLeftPaneWidthForScreen(double screenW) {
    return _clampLeftWidth((screenW * 0.382).clamp(320.0, 480.0), screenW);
  }

  void _persistLeftWidth() {
    web.window.localStorage.setItem(_leftWidthStorageKey, _leftPaneWidth.round().toString());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitWidth) return;
    _didInitWidth = true;
    final sw = MediaQuery.sizeOf(context).width;
    final raw = web.window.localStorage.getItem(_leftWidthStorageKey);
    final parsed = double.tryParse(raw ?? '');
    if (parsed != null && parsed.isFinite) {
      _leftPaneWidth = _clampLeftWidth(parsed, sw);
    } else {
      _leftPaneWidth = defaultLeftPaneWidthForScreen(sw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutCtrl = Get.find<WebLayoutController>();
    final screenW = MediaQuery.sizeOf(context).width;
    final clamped = _clampLeftWidth(_leftPaneWidth, screenW);
    if (clamped != _leftPaneWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _leftPaneWidth = clamped);
      });
    }

    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      drawer: _HomeDrawer(controller: controller),
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                'home.title'.tr,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'home.leftPaneWidthPx'.trParams({'w': '${clamped.round()}'}),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          Obx(() => IconButton(
            icon: Icon(controller.listModeIcon),
            onPressed: controller.cycleListMode,
            tooltip: 'listMode.toggle'.tr,
          )),
          Obx(() {
            if (controller.currentSection.value != 'home') {
              return const SizedBox.shrink();
            }
            return IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'home.searchFilterSheetTitle'.tr,
              onPressed: () => WebHomePage._showAdvancedSearchStatic(context, controller),
            );
          }),
          IconButton(
            icon: const Icon(Icons.image_search),
            onPressed: controller.pickImageAndSearch,
            tooltip: 'home.imageSearch'.tr,
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: clamped,
            child: WebHomePage.buildHomeContent(context, controller, isLeftPane: true),
          ),
          Tooltip(
            message: 'home.twoPaneDividerTooltip'.trParams({'w': '${clamped.round()}'}),
            waitDuration: const Duration(milliseconds: 400),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () {
                  setState(() {
                    _leftPaneWidth = defaultLeftPaneWidthForScreen(screenW);
                  });
                  _persistLeftWidth();
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _leftPaneWidth = _clampLeftWidth(
                      _leftPaneWidth + details.delta.dx,
                      screenW,
                    );
                  });
                },
                onHorizontalDragEnd: (_) => _persistLeftWidth(),
                child: SizedBox(
                  width: 8,
                  child: VerticalDivider(
                    width: 8,
                    thickness: 2,
                    color: dividerColor,
                  ),
                ),
              ),
            ),
          ),
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
  late final String _tag;

  @override
  void initState() {
    super.initState();
    // Unique tag per gallery: Get.put with a fixed tag races with the previous
    // panel's dispose (Flutter may run new initState before old dispose). Reusing
    // the same tag makes Get.return the stale controller and then delete removes it.
    _tag = 'embedded_detail_${widget.gid}_${widget.token}';
    Get.put(
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
              // Must reset section — refresh() alone would keep e.g. favorites and only refetch that list.
              controller.loadUrl('home');
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
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'home.searchFilterSheetTitle'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              Text('home.language'.tr, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Obx(() => DropdownButtonFormField<String?>(
                    value: controller.filterLanguage.value,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('home.languageNone'.tr)),
                      ...WebHomeController.searchLanguageKeys.map((k) => DropdownMenuItem<String?>(
                            value: k,
                            child: Text(
                              k.isEmpty ? k : '${k[0].toUpperCase()}${k.substring(1)}',
                            ),
                          )),
                    ],
                    onChanged: (v) {
                      controller.filterLanguage.value = v;
                      controller.persistAdvancedSearchSettings();
                    },
                  )),
              const SizedBox(height: 2),
              Obx(() => SwitchListTile(
                    title: Text('home.disableFilterForLanguage'.tr),
                    value: controller.disableFilterForLanguage.value,
                    onChanged: (v) {
                      controller.disableFilterForLanguage.value = v;
                      controller.persistAdvancedSearchSettings();
                    },
                    contentPadding: EdgeInsets.zero,
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
                      onChanged: (v) {
                        controller.minimumRating.value = v.round();
                        controller.persistAdvancedSearchSettings();
                      },
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
                    onChanged: (v) {
                      controller.searchInName.value = v ?? true;
                      controller.persistAdvancedSearchSettings();
                    },
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.tags'.tr),
                    value: controller.searchInTags.value,
                    onChanged: (v) {
                      controller.searchInTags.value = v ?? true;
                      controller.persistAdvancedSearchSettings();
                    },
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.description'.tr),
                    value: controller.searchInDesc.value,
                    onChanged: (v) {
                      controller.searchInDesc.value = v ?? false;
                      controller.persistAdvancedSearchSettings();
                    },
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: Text('home.showExpunged'.tr),
                    value: controller.showExpunged.value,
                    onChanged: (v) {
                      controller.showExpunged.value = v ?? false;
                      controller.persistAdvancedSearchSettings();
                    },
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
                        controller.filterLanguage.value = null;
                        controller.disableFilterForLanguage.value = false;
                        controller.persistAdvancedSearchSettings();
                      },
                      child: Text('common.reset'.tr),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        controller.persistAdvancedSearchSettings();
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

/// Gallery list API may send `tags[ns]` as `List<String>` (legacy) or
/// `List<Map>` with `tag`, optional `color` / `backgroundColor` (ARGB ints from EH watched-tag styles).
String _parseTagListEntryLabel(dynamic raw) {
  if (raw is String) return raw;
  if (raw is Map) {
    return raw['tag']?.toString() ?? raw['name']?.toString() ?? '';
  }
  return raw.toString();
}

/// Tag key for `/api/tag/batch` (matches gallery detail `key` field).
String _parseTagListEntryKey(dynamic raw) {
  if (raw is String) return raw;
  if (raw is Map) {
    return raw['tag']?.toString() ?? raw['name']?.toString() ?? '';
  }
  return raw.toString();
}

(int?, int?) _parseTagListEntryColors(dynamic raw) {
  if (raw is! Map) return (null, null);
  final c = (raw['color'] as num?)?.toInt();
  final b = (raw['backgroundColor'] as num?)?.toInt();
  return (c, b);
}

bool _tagEntryIsWatched(dynamic raw) {
  final (c, b) = _parseTagListEntryColors(raw);
  return c != null || b != null;
}

List<Widget> _buildHomePageTagChips(
  Map<String, dynamic> tags, {
  required RxMap<String, String> tagTranslations,
  Map<String, int> accountWatchedBackgroundArgb = const {},
  int maxTags = 12,
}) {
  final entries = <({String namespace, dynamic raw})>[];
  for (final e in tags.entries) {
    final tagList = e.value;
    if (tagList is! List) continue;
    for (final raw in tagList) {
      entries.add((namespace: e.key.toString(), raw: raw));
    }
  }
  entries.sort((a, b) {
    final aw = _tagEntryIsWatched(a.raw);
    final bw = _tagEntryIsWatched(b.raw);
    if (aw && !bw) return -1;
    if (!aw && bw) return 1;
    return 0;
  });

  final chips = <Widget>[];
  for (final e in entries) {
    if (chips.length >= maxTags) break;
    final key = _parseTagListEntryKey(e.raw);
    final label = _parseTagListEntryLabel(e.raw);
    if (label.isEmpty) continue;
    final display = tagTranslations['${e.namespace}:$key'] ?? label;
    final showOriginalTooltip = display != key;
    var (cInt, bInt) = _parseTagListEntryColors(e.raw);
    final mk = '${e.namespace}:$key';
    if (cInt == null && bInt == null) {
      final fromAccount = accountWatchedBackgroundArgb[mk];
      if (fromAccount != null) {
        bInt = fromAccount;
      }
    }
    final watched = cInt != null || bInt != null;

    late final Color fg;
    late final Color borderColor;
    Color? fill;
    if (!watched) {
      fg = Colors.grey.shade700;
      borderColor = Colors.grey.shade400;
      fill = null;
    } else {
      final bg = bInt != null ? Color(bInt) : Colors.grey.shade300;
      fill = bg;
      final explicitFg = cInt != null ? Color(cInt) : null;
      fg = explicitFg ??
          (ThemeData.estimateBrightnessForColor(bg) == Brightness.light
              ? const Color(0xFF090909)
              : const Color(0xFFF1F1F1));
      final borderArgb = bInt ?? cInt;
      borderColor = borderArgb != null ? Color(borderArgb).withValues(alpha: 0.9) : Colors.grey.shade400;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: borderColor, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: watched ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
    chips.add(showOriginalTooltip ? Tooltip(message: key, child: chip) : chip);
  }
  return chips;
}

class _GalleryListTile extends StatelessWidget {
  final Map<String, dynamic> gallery;
  final WebHomeController homeController;
  final bool compact;
  final bool isLeftPane;

  const _GalleryListTile({
    required this.gallery,
    required this.homeController,
    this.compact = false,
    this.isLeftPane = false,
  });

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
                      Obx(() => Wrap(
                            spacing: 3,
                            runSpacing: 3,
                            children: _buildHomePageTagChips(
                              tags,
                              tagTranslations: homeController.tagTranslations,
                              accountWatchedBackgroundArgb:
                                  Get.find<WebWatchedTagStylesController>().backgroundArgbByTagKey.value,
                              maxTags: 12,
                            ),
                          )),
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
  final WebHomeController homeController;
  final bool isLeftPane;

  const _GalleryCard({
    required this.gallery,
    required this.homeController,
    this.isLeftPane = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = gallery['title'] as String? ?? '';
    final category = gallery['category'] as String? ?? '';
    final gid = gallery['gid'];
    final token = gallery['token'];
    final coverUrl = gallery['coverUrl'] as String? ?? '';
    final tags = gallery['tags'] as Map<String, dynamic>?;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isLeftPane) {
            Get.find<WebLayoutController>().selectGallery(gid as int, token as String);
          } else {
            Get.toNamed('/web/gallery/$gid/$token');
          }
        },
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
                      ? WebProxiedImage(
                          sourceUrl: coverUrl,
                          fit: BoxFit.cover,
                          surfaceLoadingPlaceholder: true,
                          readerErrorChild: Container(
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
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (tags != null && tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Obx(() => Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: _buildHomePageTagChips(
                        tags,
                        tagTranslations: homeController.tagTranslations,
                        accountWatchedBackgroundArgb:
                            Get.find<WebWatchedTagStylesController>().backgroundArgbByTagKey.value,
                        maxTags: 8,
                      ),
                    )),
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
                ? WebProxiedImage(
                    sourceUrl: coverUrl,
                    fit: BoxFit.cover,
                    readerErrorChild: Container(
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
