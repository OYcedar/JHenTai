import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/model/gallery_image_page_url.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_eh_thumbnail.dart';
import 'package:jhentai/src/pages_web/web_watched_tag_styles_controller.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:jhentai/src/pages_web/web_group_name_selector.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';
import 'package:jhentai/src/utils/date_util.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:web/web.dart' as web;

List<String> _sortedDownloadGroupCandidates(WebDownloadService svc) {
  final set = <String>{};
  for (final t in svc.galleryTasks.values) {
    set.add((t['group_name'] ?? t['groupName'] ?? 'default') as String);
  }
  for (final t in svc.archiveTasks.values) {
    set.add((t['group_name'] ?? t['groupName'] ?? 'default') as String);
  }
  if (set.isEmpty) set.add('default');
  final list = set.toList();
  list.sort((a, b) {
    if (a == 'default') return -1;
    if (b == 'default') return 1;
    return a.compareTo(b);
  });
  return list;
}

int? _webDetailThumbnailColumnsSetting() {
  final raw =
      web.window.localStorage.getItem('jh_web_detail_thumbnail_columns');
  final value = int.tryParse(raw ?? '');
  return value != null && value >= 2 && value <= 8 ? value : null;
}

bool _webMoveCoverToRightSetting() {
  return web.window.localStorage.getItem('jh_web_move_cover_to_right') ==
      'true';
}

Map<String, dynamic> _thumbMapForDetail(
    WebGalleryDetailController c, int index) {
  if (index < c.galleryThumbnails.length) {
    return Map<String, dynamic>.from(c.galleryThumbnails[index]);
  }
  if (index < c.thumbnailImageUrls.length) {
    final u = c.thumbnailImageUrls[index];
    if (u.isNotEmpty) {
      return {'thumbUrl': u, 'isLarge': true};
    }
  }
  return {'thumbUrl': '', 'isLarge': true};
}

String _webSimilarTitleQuery(String title) {
  final cleaned = title.replaceAll(RegExp(r'\[.*?\]|\(.*?\)|{.*?}'), '').trim();
  if (cleaned.isEmpty) return title.trim();
  return 'title:"$cleaned"';
}

String _webUploaderSearchQuery(String uploader) {
  final escaped = uploader.trim().replaceAll('"', r'\"');
  return 'uploader:"$escaped"';
}

String _webPreferredTime(String value) {
  if (WebPreferenceSettings.showUtcTime || value.trim().isEmpty) {
    return value;
  }
  try {
    return DateUtil.transformUtc2LocalTimeString(value);
  } catch (_) {
    return value;
  }
}

class WebGalleryDetailController extends GetxController {
  late int gid;
  late String token;

  final int? _paramGid;
  final String? _paramToken;

  WebGalleryDetailController({int? gid, String? token})
      : _paramGid = gid,
        _paramToken = token;

  final title = ''.obs;
  final titleJpn = ''.obs;
  final category = ''.obs;
  final uploader = ''.obs;
  final pageCount = 0.obs;
  final rating = 0.0.obs;
  final coverUrl = ''.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final galleryUrl = ''.obs;
  final archiverUrl = ''.obs;
  final imagePageUrls = <String>[].obs;
  final thumbnailImageUrls = <String>[].obs;
  final galleryThumbnails = <Map<String, dynamic>>[].obs;
  final tags = <String, List<String>>{}.obs;

  /// Server [tagsRich]: EH `#taglist` inline colors, aligned by `name` with [tags].
  final tagsRich = <String, List<Map<String, dynamic>>>{}.obs;
  final translatedTags = <String, String>{}.obs;
  final comments = <Map<String, dynamic>>[].obs;

  final favoriteSlot = Rxn<int>();
  final favoriteName = Rxn<String>();
  final isFavLoading = false.obs;
  final site = 'EH'.obs;
  final favoriteNames = <String>[].obs;
  final favoriteCounts = <int>[].obs;
  final publishDate = ''.obs;
  final fileSize = ''.obs;
  final language = ''.obs;
  final parentUrl = Rxn<String>();
  final ratingCount = 0.obs;
  final newerVersionUrl = Rxn<String>();
  final childVersions = <Map<String, dynamic>>[].obs;
  final torrentCount = 0.obs;
  final readProgress = 0.obs;

  /// True while fetching full thumbnail strip via [fetchGalleryImagePages] (EH shows ~20 per HTML page).
  final isThumbsLoading = false.obs;

  int? apiuid;
  String? apikey;

  Future<void> refreshDetail() => _loadDetail();

  /// Query string for `/web/reader/$gid/$token` (includes gallery title when known).
  String buildReaderQuery({int? startPage, String? mode}) {
    final parts = <String>[];
    if (startPage != null) {
      parts.add('startPage=$startPage');
    }
    if (mode != null && mode.isNotEmpty) {
      parts.add('mode=${Uri.encodeQueryComponent(mode)}');
    }
    final t = title.value.trim();
    if (t.isNotEmpty) {
      parts.add('title=${Uri.encodeQueryComponent(t)}');
    }
    if (parts.isEmpty) return '';
    return '?${parts.join('&')}';
  }

  String get shareableGalleryUrl {
    final exact = galleryUrl.value.trim();
    if (exact.isNotEmpty) {
      return exact;
    }
    final domain = site.value == 'EX' ? 'exhentai.org' : 'e-hentai.org';
    return 'https://$domain/g/$gid/$token/';
  }

  @override
  void onInit() {
    super.onInit();
    gid = _paramGid ?? (int.tryParse(Get.parameters['gid'] ?? '') ?? 0);
    token = _paramToken ?? (Get.parameters['token'] ?? '');
    _loadDetail().then((_) => _loadReadProgress());
    _loadSiteAndFavNames();
    unawaited(Get.find<WebWatchedTagStylesController>().refresh());
  }

  Future<void> _loadSiteAndFavNames() async {
    try {
      final status = await backendApiClient.getAuthStatus();
      site.value = status['site'] as String? ?? 'EH';
    } catch (_) {}
    try {
      final f = await backendApiClient.fetchFavoriteFolders();
      favoriteNames.value = f.names;
      final counts = f.counts;
      if (counts.length >= favoriteNames.length) {
        favoriteCounts.assignAll(counts.take(favoriteNames.length).toList());
      } else {
        favoriteCounts.assignAll([
          ...counts,
          ...List.filled(favoriteNames.length - counts.length, 0),
        ]);
      }
    } catch (_) {}
  }

  Future<void> _loadDetail() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await backendApiClient.fetchGalleryDetail(gid, token);
      final err = result['error'] as String?;
      if (err != null && err.isNotEmpty) {
        errorMessage.value = err;
        return;
      }
      title.value = result['title'] as String? ?? 'Unknown';
      titleJpn.value = result['titleJpn'] as String? ?? '';
      category.value = result['category'] as String? ?? '';
      uploader.value = result['uploader'] as String? ?? '';
      coverUrl.value = result['coverUrl'] as String? ?? '';
      rating.value = (result['rating'] as num?)?.toDouble() ?? 0;
      pageCount.value = result['pageCount'] as int? ?? 0;
      archiverUrl.value = result['archiverUrl'] as String? ?? '';
      galleryUrl.value = result['galleryUrl'] as String? ?? '';
      final pages = result['imagePageUrls'] as List?;
      imagePageUrls.value = pages?.cast<String>() ?? [];
      final thumbs = result['thumbnailImageUrls'] as List?;
      thumbnailImageUrls.value = thumbs?.cast<String>() ?? [];
      final gt = result['galleryThumbnails'] as List?;
      if (gt != null) {
        galleryThumbnails.value =
            gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        galleryThumbnails.value = [];
      }

      final rawTags = result['tags'] as Map<String, dynamic>?;
      if (rawTags != null) {
        tags.value =
            rawTags.map((k, v) => MapEntry(k, (v as List).cast<String>()));
      } else {
        tags.clear();
      }

      tagsRich.clear();
      final rawRich = result['tagsRich'] as Map<String, dynamic>?;
      if (rawRich != null) {
        for (final e in rawRich.entries) {
          final v = e.value;
          if (v is List) {
            tagsRich[e.key] = v
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
          }
        }
      }
      tagsRich.refresh();

      apiuid = result['apiuid'] as int?;
      apikey = result['apikey'] as String?;

      favoriteSlot.value = result['favoriteSlot'] as int?;
      favoriteName.value = result['favoriteName'] as String?;

      final rawComments = result['comments'] as List?;
      if (rawComments != null) {
        comments.value = rawComments.cast<Map<String, dynamic>>();
      }

      publishDate.value = result['publishDate'] as String? ?? '';
      fileSize.value = result['fileSize'] as String? ?? '';
      language.value = result['language'] as String? ?? '';
      parentUrl.value = result['parentUrl'] as String?;
      ratingCount.value = result['ratingCount'] as int? ?? 0;
      newerVersionUrl.value = result['newerVersionUrl'] as String?;
      final rawChildVersions = result['childVersions'] as List?;
      childVersions.value = rawChildVersions
              ?.map((item) => Map<String, dynamic>.from(item as Map))
              .toList() ??
          [];
      torrentCount.value = (result['torrentCount'] as num?)?.toInt() ?? 0;

      backendApiClient
          .recordHistory(
            gid: gid,
            token: token,
            title: title.value,
            coverUrl: coverUrl.value,
            category: category.value,
          )
          .catchError((_) {});

      _loadTagTranslations();

      if (pageCount.value > 0 &&
          (thumbnailImageUrls.length < pageCount.value ||
              galleryThumbnails.length < pageCount.value)) {
        _loadFullThumbnails();
      }
    } catch (e) {
      errorMessage.value = 'detail.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
    }
  }

  /// Merges all pages of `#gdt` thumbs (same as reader) so the detail grid is not limited to ~20.
  Future<void> _loadFullThumbnails() async {
    isThumbsLoading.value = true;
    try {
      final result = await backendApiClient.fetchGalleryImagePages(gid, token);
      final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
      final thumbs =
          (result['thumbnailImageUrls'] as List?)?.cast<String>() ?? [];
      final gt = result['galleryThumbnails'] as List?;
      final total = (result['totalPages'] as num?)?.toInt();

      if (pages.isNotEmpty &&
          (imagePageUrls.isEmpty || pages.length >= imagePageUrls.length)) {
        imagePageUrls.value = pages;
      }
      if (thumbs.isNotEmpty &&
          (thumbnailImageUrls.isEmpty ||
              thumbs.length >= thumbnailImageUrls.length)) {
        thumbnailImageUrls.value = thumbs;
      }
      if (gt != null && gt.isNotEmpty) {
        if (galleryThumbnails.isEmpty ||
            gt.length >= galleryThumbnails.length) {
          galleryThumbnails.value =
              gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      if (total != null && total > 0) {
        final current = pageCount.value;
        if (current == 0 || total >= current) {
          pageCount.value = total;
        }
      }
      thumbnailImageUrls.refresh();
      galleryThumbnails.refresh();
      imagePageUrls.refresh();
    } catch (_) {
      // Keep first-page thumbs from fetchGalleryDetail
    } finally {
      isThumbsLoading.value = false;
    }
  }

  Future<void> _loadTagTranslations() async {
    try {
      final tagList = <Map<String, String>>[];
      for (final entry in tags.entries) {
        for (final tag in entry.value) {
          tagList.add({'namespace': entry.key, 'key': tag});
        }
      }
      if (tagList.isEmpty) return;
      final translations = await backendApiClient.translateTags(tagList);
      translatedTags.value = translations;
    } catch (_) {}
  }

  Future<void> _loadReadProgress() async {
    try {
      final val = await backendApiClient.getSetting('read_progress_$gid');
      if (val != null) {
        readProgress.value = int.tryParse(val) ?? 0;
      }
    } catch (_) {}
  }

  String getTranslatedTag(String namespace, String tag) {
    final key = '$namespace:$tag';
    return translatedTags[key] ?? tag;
  }

  /// Inline ARGB from gallery HTML (`tagsRich`), same order as [tags] rows.
  ({int? colorArgb, int? backgroundArgb})? tagHtmlStyleArgb(
      String namespace, String tagName) {
    final m = tagRichMeta(namespace, tagName);
    if (m == null) return null;
    int? asArgb(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return (
      colorArgb: asArgb(m['color']),
      backgroundArgb: asArgb(m['backgroundColor']),
    );
  }

  Map<String, dynamic>? tagRichMeta(String namespace, String tagName) {
    final list = tagsRich[namespace];
    if (list == null) return null;
    for (final m in list) {
      if (m['name'] == tagName) {
        return m;
      }
    }
    return null;
  }

  void updateTagVoteStatus(String namespace, String tagName, int vote) {
    final m = tagRichMeta(namespace, tagName);
    if (m == null) return;
    final current = m['voteStatus'] as String? ?? 'none';
    if (vote > 0) {
      m['voteStatus'] = current == 'up' ? 'none' : 'up';
    } else {
      m['voteStatus'] = current == 'down' ? 'none' : 'down';
    }
    tagsRich.refresh();
  }

  /// [slotIndex] 0–9. If already in that folder, removes from favorites (EH behavior).
  Future<void> applyFavoriteFolder(int slotIndex, String favnote) async {
    isFavLoading.value = true;
    try {
      if (favoriteSlot.value != null && favoriteSlot.value == slotIndex) {
        await backendApiClient.removeFavorite(gid, token);
        favoriteSlot.value = null;
        favoriteName.value = null;
        Get.snackbar('detail.favRemoved'.tr, 'detail.favRemovedMsg'.tr,
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      await backendApiClient.addFavorite(gid, token,
          favcat: slotIndex, favnote: favnote);
      favoriteSlot.value = slotIndex;
      final name = getFavSlotName(slotIndex);
      favoriteName.value = name;
      Get.snackbar(
          'detail.favAdded'.tr, 'detail.favAddedMsg'.trParams({'name': name}),
          snackPosition: SnackPosition.BOTTOM);
      _loadSiteAndFavNames().catchError((_) {});
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'detail.favError'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      isFavLoading.value = false;
    }
  }

  Future<void> submitRating(double newRating) async {
    if (apiuid == null || apikey == null) {
      Get.snackbar('common.error'.tr, 'detail.rateLoginRequired'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final result = await backendApiClient.rateGallery(
        gid: gid,
        token: token,
        apiuid: apiuid!,
        apikey: apikey!,
        rating: newRating,
      );
      final avg = result['rating_avg'] as num?;
      if (avg != null) rating.value = avg.toDouble();
      Get.snackbar('detail.rated'.tr,
          'detail.ratedMsg'.trParams({'rating': newRating.toStringAsFixed(1)}),
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'detail.rateFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> startGalleryDownload(
      {String group = 'default',
      int priority = 0,
      bool downloadOriginalImage = false}) async {
    try {
      await backendApiClient.startGalleryDownload(
        gid: gid,
        token: token,
        title: title.value,
        galleryUrl: galleryUrl.value,
        category: category.value,
        pageCount: pageCount.value,
        coverUrl: coverUrl.value,
        uploader: uploader.value,
        group: group,
        priority: priority,
        downloadOriginalImage: downloadOriginalImage,
      );
      Get.snackbar('detail.downloadStarted'.tr, 'detail.galleryQueued'.tr,
          snackPosition: SnackPosition.BOTTOM);
      await Get.find<WebDownloadService>().refresh();
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'detail.downloadFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> upgradeToNewVersion() async {
    final url = newerVersionUrl.value;
    if (url == null || url.isEmpty) return;
    try {
      final r = await backendApiClient.upgradeGalleryDownload(
          fromGid: gid, newerVersionUrl: url);
      if (r['success'] != true) {
        final err = r['error']?.toString() ?? 'unknown';
        Get.snackbar(
            'common.error'.tr, 'detail.upgradeFailed'.trParams({'error': err}),
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withValues(alpha: 0.7));
        return;
      }
      await Get.find<WebDownloadService>().refresh();
      Get.snackbar('common.success'.tr, 'detail.upgradeOk'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'detail.upgradeFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> startArchiveDownload({
    bool isOriginal = false,
    String group = 'default',
    int priority = 0,
  }) async {
    if (archiverUrl.isEmpty) {
      Get.snackbar('common.error'.tr, 'detail.noArchive'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await backendApiClient.startArchiveDownload(
        gid: gid,
        token: token,
        title: title.value,
        galleryUrl: galleryUrl.value,
        archivePageUrl: archiverUrl.value,
        category: category.value,
        pageCount: pageCount.value,
        coverUrl: coverUrl.value,
        uploader: uploader.value,
        isOriginal: isOriginal,
        group: group,
        priority: priority,
      );
      Get.snackbar('detail.downloadStarted'.tr, 'detail.archiveQueued'.tr,
          snackPosition: SnackPosition.BOTTOM);
      await Get.find<WebDownloadService>().refresh();
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'detail.archiveFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> postComment(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final result = await backendApiClient.postComment(
          gid: gid, token: token, comment: text);
      if (result['success'] == false) {
        throw result['message'] ?? result['error'] ?? 'Post comment failed';
      }
      Get.snackbar('comment.posted'.tr, 'comment.postedMsg'.tr,
          snackPosition: SnackPosition.BOTTOM);
      _loadDetail();
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'comment.postFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<bool> updateComment({
    required int commentId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return false;
    try {
      final result = await backendApiClient.updateComment(
        gid: gid,
        token: token,
        commentId: commentId,
        comment: text,
      );
      if (result['success'] == false) {
        throw result['message'] ?? result['error'] ?? 'Update comment failed';
      }
      Get.snackbar('comment.updated'.tr, 'comment.updatedMsg'.tr,
          snackPosition: SnackPosition.BOTTOM);
      await _loadDetail();
      return true;
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'comment.updateFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
      return false;
    }
  }

  Future<void> voteComment(int commentId, int vote) async {
    if (apiuid == null || apikey == null) {
      Get.snackbar('common.error'.tr, 'detail.rateLoginRequired'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final result = await backendApiClient.voteComment(
        gid: gid,
        token: token,
        apiuid: apiuid!,
        apikey: apikey!,
        commentId: commentId,
        vote: vote,
      );
      if (result['success'] == false) {
        throw result['message'] ?? result['error'] ?? 'Vote failed';
      }
      final newScore = result['comment_score'];
      final idx = comments.indexWhere((c) => c['id'] == commentId.toString());
      if (idx >= 0) {
        final current = Map<String, dynamic>.from(comments[idx]);
        final wasVotedUp = current['votedUp'] == true;
        final wasVotedDown = current['votedDown'] == true;
        comments[idx] = {
          ...current,
          if (newScore != null) 'score': '$newScore',
          'votedUp': vote > 0 ? !wasVotedUp : false,
          'votedDown': vote < 0 ? !wasVotedDown : false,
        };
      }
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'comment.voteFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> blockCommentUser(Map<String, dynamic> comment) async {
    final author = comment['author']?.toString() ?? '';
    final userId = comment['userId']?.toString() ?? '';
    if (author.isEmpty) return;
    try {
      final groupId = 'comment-user-${DateTime.now().microsecondsSinceEpoch}';
      await backendApiClient.saveBlockRule(
        groupId: groupId,
        target: 'comment',
        attribute: 'userName',
        pattern: 'equal',
        expression: author,
      );
      if (userId.isNotEmpty) {
        await backendApiClient.saveBlockRule(
          groupId: groupId,
          target: 'comment',
          attribute: 'userId',
          pattern: 'equal',
          expression: userId,
        );
      }
      comments.removeWhere((item) =>
          item['author']?.toString() == author ||
          (userId.isNotEmpty && item['userId']?.toString() == userId));
      comments.refresh();
      Get.snackbar('blockRule.blocked'.tr,
          'blockRule.commentUserBlocked'.trParams({'user': author}),
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  String getFavSlotName(int i) {
    if (i < favoriteNames.length && favoriteNames[i].isNotEmpty) {
      return favoriteNames[i];
    }
    return 'detail.favSlot'.trParams({'n': '$i'});
  }

  static String favSlotName(int i) => 'detail.favSlot'.trParams({'n': '$i'});
}

class WebGalleryDetailPage extends StatelessWidget {
  final String? controllerTag;
  const WebGalleryDetailPage({super.key, this.controllerTag});

  WebGalleryDetailController get controller =>
      Get.find<WebGalleryDetailController>(tag: controllerTag);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() =>
            Text(controller.title.value, overflow: TextOverflow.ellipsis)),
        actions: [
          Obx(() {
            return IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'detail.copyUrl'.tr,
              onPressed: () {
                final url = controller.shareableGalleryUrl;
                Clipboard.setData(ClipboardData(text: url));
                Get.snackbar('detail.copied'.tr, url,
                    snackPosition: SnackPosition.BOTTOM);
              },
            );
          }),
          Obx(() {
            if (controller.isFavLoading.value) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final isFav = controller.favoriteSlot.value != null;
            return IconButton(
              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav
                      ? _favSlotColor(controller.favoriteSlot.value ?? 0)
                      : null),
              tooltip: 'detail.addToFavTitle'.tr,
              onPressed: () => _handleFavoriteTap(context, controller),
              onLongPress: WebPreferenceSettings.enableDefaultFavorite
                  ? () => _showFavoriteFolderDialog(context, controller)
                  : null,
            );
          }),
          PopupMenuButton<String>(
            onSelected: (value) => _handleOverflowMenu(context, value),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                      leading: const Icon(Icons.share, size: 20),
                      title: Text('detail.shareUrl'.tr),
                      dense: true,
                      contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: 'jumpToPage',
                  child: ListTile(
                      leading: const Icon(Icons.format_list_numbered, size: 20),
                      title: Text('detail.jumpToPage'.tr),
                      dense: true,
                      contentPadding: EdgeInsets.zero)),
              if (controller.parentUrl.value != null ||
                  controller.childVersions.isNotEmpty)
                PopupMenuItem(
                    value: 'versionHistory',
                    child: ListTile(
                        leading: const Icon(Icons.history, size: 20),
                        title: Text('detail.versionHistory'.tr),
                        dense: true,
                        contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: 'stats',
                  child: ListTile(
                      leading: const Icon(Icons.bar_chart, size: 20),
                      title: Text('detail.stats'.tr),
                      dense: true,
                      contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: 'similarSearch',
                  child: ListTile(
                      leading: const Icon(Icons.title, size: 20),
                      title: Text('detail.similarByTitle'.tr),
                      dense: true,
                      contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: 'blockGallery',
                  child: ListTile(
                      leading: const Icon(Icons.block,
                          size: 20, color: Colors.orange),
                      title: Text('detail.blockGallery'.tr),
                      dense: true,
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(child: Text(controller.errorMessage.value));
        }
        return _buildDetail(context);
      }),
    );
  }

  void _showStartGalleryDownloadDialog(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    final candidates = _sortedDownloadGroupCandidates(svc);
    final rawG =
        web.window.localStorage.getItem('jh_web_default_gallery_group');
    var group = (rawG != null && rawG.isNotEmpty) ? rawG : 'default';
    var downloadOriginalImage =
        web.window.localStorage.getItem('jh_web_default_gallery_original') ==
            'true';
    final priorityCtrl = TextEditingController(
      text:
          web.window.localStorage.getItem('jh_web_default_gallery_priority') ??
              '0',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('detail.startDownloadTitle'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGroupNameSelector(
                currentGroup: group,
                candidates: candidates,
                listener: (g) => group = g,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priorityCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'detail.downloadPriority'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setState) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: downloadOriginalImage,
                  onChanged: (value) => setState(
                    () => downloadOriginalImage = value ?? false,
                  ),
                  title: Text('downloadOriginalImage'.tr),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () async {
              final g = group.trim().isEmpty ? 'default' : group.trim();
              final p = int.tryParse(priorityCtrl.text.trim()) ?? 0;
              web.window.localStorage
                  .setItem('jh_web_default_gallery_group', g);
              web.window.localStorage
                  .setItem('jh_web_default_gallery_priority', '$p');
              web.window.localStorage.setItem('jh_web_default_gallery_original',
                  downloadOriginalImage ? 'true' : 'false');
              Navigator.pop(ctx);
              await controller.startGalleryDownload(
                group: g,
                priority: p,
                downloadOriginalImage: downloadOriginalImage,
              );
            },
            child: Text('common.ok'.tr),
          ),
        ],
      ),
    );
  }

  void _showStartArchiveDownloadDialog(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    final candidates = _sortedDownloadGroupCandidates(svc);
    final rawG =
        web.window.localStorage.getItem('jh_web_default_archive_group');
    var group = (rawG != null && rawG.isNotEmpty) ? rawG : 'default';
    final priorityCtrl = TextEditingController(
      text:
          web.window.localStorage.getItem('jh_web_default_archive_priority') ??
              '0',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('detail.startDownloadTitle'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGroupNameSelector(
                currentGroup: group,
                candidates: candidates,
                listener: (g) => group = g,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priorityCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'detail.downloadPriority'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.archive),
                    label: Text('detail.archiveResample'.tr),
                    onPressed: () async {
                      final g = group.trim().isEmpty ? 'default' : group.trim();
                      final p = int.tryParse(priorityCtrl.text.trim()) ?? 0;
                      web.window.localStorage
                          .setItem('jh_web_default_archive_group', g);
                      web.window.localStorage
                          .setItem('jh_web_default_archive_priority', '$p');
                      Navigator.pop(ctx);
                      await controller.startArchiveDownload(
                          isOriginal: false, group: g, priority: p);
                    },
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.archive_outlined),
                    label: Text('detail.archiveOriginal'.tr),
                    onPressed: () async {
                      final g = group.trim().isEmpty ? 'default' : group.trim();
                      final p = int.tryParse(priorityCtrl.text.trim()) ?? 0;
                      web.window.localStorage
                          .setItem('jh_web_default_archive_group', g);
                      web.window.localStorage
                          .setItem('jh_web_default_archive_priority', '$p');
                      Navigator.pop(ctx);
                      await controller.startArchiveDownload(
                          isOriginal: true, group: g, priority: p);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr)),
        ],
      ),
    );
  }

  void _showFavoriteFolderDialog(
      BuildContext context, WebGalleryDetailController c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WebFavoriteFolderDialog(controller: c),
    );
  }

  void _handleFavoriteTap(BuildContext context, WebGalleryDetailController c) {
    if (!WebPreferenceSettings.enableDefaultFavorite ||
        !_applyDefaultFavorite(c)) {
      _showFavoriteFolderDialog(context, c);
    }
  }

  bool _applyDefaultFavorite(WebGalleryDetailController c) {
    final raw = web.window.localStorage.getItem('jh_web_default_favcat');
    if (raw == null || raw.isEmpty) return false;
    final slot = int.tryParse(raw);
    if (slot == null || slot < 0 || slot > 9) return false;
    c.applyFavoriteFolder(slot, '');
    return true;
  }

  void _handleOverflowMenu(BuildContext context, String value) {
    switch (value) {
      case 'share':
        final url = controller.shareableGalleryUrl;
        try {
          final shareData =
              web.ShareData(title: controller.title.value, url: url);
          web.window.navigator.share(shareData);
        } catch (_) {
          Clipboard.setData(ClipboardData(text: url));
          Get.snackbar('detail.copied'.tr, url,
              snackPosition: SnackPosition.BOTTOM);
        }
        break;
      case 'jumpToPage':
        _showJumpToPageDialog(context);
        break;
      case 'versionHistory':
        _showVersionHistoryDialog(context);
        break;
      case 'stats':
        Get.toNamed('/web/stats/${controller.gid}/${controller.token}');
        break;
      case 'similarSearch':
        Get.offAllNamed('/web/home', arguments: {
          'search': _webSimilarTitleQuery(controller.title.value)
        });
        break;
      case 'blockGallery':
        _blockGallery();
        break;
    }
  }

  void _showJumpToPageDialog(BuildContext context) {
    final textCtrl = TextEditingController();
    int? parsePage() {
      final page = int.tryParse(textCtrl.text);
      if (page != null && page >= 1 && page <= controller.pageCount.value) {
        return page;
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('detail.jumpToPage'.tr),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1 - ${controller.pageCount.value}',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) {
            final page = parsePage();
            if (page != null) {
              Navigator.pop(ctx);
              Get.toNamed(
                  '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(startPage: page - 1)}');
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () {
              final page = parsePage();
              if (page != null) {
                Navigator.pop(ctx);
                Get.toNamed(
                    '/web/thumbnails/${controller.gid}/${controller.token}?page=$page');
              }
            },
            child: Text('detail.jumpToThumbnail'.tr),
          ),
          FilledButton(
            onPressed: () {
              final page = parsePage();
              if (page != null) {
                Navigator.pop(ctx);
                Get.toNamed(
                    '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(startPage: page - 1)}');
              }
            },
            child: Text('common.ok'.tr),
          ),
        ],
      ),
    );
  }

  void _showVersionHistoryDialog(BuildContext context) {
    final children = controller.childVersions.toList().reversed.toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('detail.versionHistory'.tr),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          ...children.map((item) {
            final url = item['url']?.toString() ?? '';
            final title = item['title']?.toString() ?? '';
            final updateTime = item['updateTime']?.toString() ?? '';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.update, size: 20),
              title: Text(
                title.isEmpty ? 'detail.newerVersion'.tr : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: updateTime.isEmpty ? null : Text(updateTime),
              onTap: () {
                Navigator.pop(ctx);
                _openGalleryUrl(url);
              },
            );
          }),
          ListTile(
            dense: true,
            leading: const Icon(Icons.radio_button_checked, size: 20),
            title: Text(
              controller.title.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('detail.currentVersion'.tr),
            selected: true,
          ),
          if (controller.parentUrl.value != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.exit_to_app, size: 20),
              title: Text('detail.parentGallery'.tr),
              onTap: () {
                Navigator.pop(ctx);
                _openGalleryUrl(controller.parentUrl.value!);
              },
            ),
        ],
      ),
    );
  }

  void _openGalleryUrl(String url) {
    final m = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(url);
    if (m != null) {
      Get.toNamed('/web/gallery/${m.group(1)}/${m.group(2)}');
    }
  }

  Future<void> _blockGallery() async {
    try {
      await backendApiClient.saveBlockRule(
        target: 'gallery',
        attribute: 'gid',
        pattern: 'equal',
        expression: '${controller.gid}',
      );
      Get.snackbar('blockRule.blocked'.tr, 'detail.galleryBlocked'.tr,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildDetail(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return RefreshIndicator(
      onRefresh: () => controller.refreshDetail(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isWide)
                  _buildWideHeader(context)
                else
                  _buildNarrowHeader(context),
                const SizedBox(height: 20),
                _buildActionButtons(context),
                const SizedBox(height: 24),
                _buildTags(context),
                if (WebPreferenceSettings.showComments) ...[
                  const SizedBox(height: 24),
                  _buildComments(context),
                ],
                const SizedBox(height: 24),
                _buildThumbnails(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideHeader(BuildContext context) {
    final cover = _buildCover(context, width: 220, height: 310);
    final metadata = Expanded(child: _buildMetadata(context));
    const gap = SizedBox(width: 20);
    final children = _webMoveCoverToRightSetting()
        ? [metadata, gap, cover]
        : [cover, gap, metadata];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildNarrowHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _buildCover(context, width: 200, height: 280)),
        const SizedBox(height: 16),
        _buildMetadata(context),
      ],
    );
  }

  Widget _buildCover(BuildContext context,
      {required double width, required double height}) {
    return Obx(() {
      final url = controller.coverUrl.value;
      return GestureDetector(
        onTap: url.isNotEmpty ? () => _showFullCoverDialog(context, url) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: width,
            height: height,
            child: url.isNotEmpty
                ? WebProxiedImage(
                    sourceUrl: url,
                    fit: BoxFit.cover,
                    width: width,
                    height: height,
                    readerErrorChild: Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.photo_library,
                          size: 48, color: Colors.grey),
                    ),
                  )
                : Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.photo_library,
                        size: 48, color: Colors.grey),
                  ),
          ),
        ),
      );
    });
  }

  void _showFullCoverDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              maxScale: 5.0,
              child: WebProxiedImage(
                sourceUrl: url,
                fit: BoxFit.contain,
                errorIconSize: 64,
                readerErrorChild: const Center(
                  child:
                      Icon(Icons.broken_image, size: 64, color: Colors.white54),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => _SelectableSearchText(
              text: controller.title.value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 5,
              onSearch: _searchKeyword,
            )),
        Obx(() {
          final titleJpn = controller.titleJpn.value.trim();
          if (!WebPreferenceSettings.showAllGalleryTitles || titleJpn.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _SelectableSearchText(
              text: titleJpn,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.grey),
              maxLines: 3,
              onSearch: _searchKeyword,
            ),
          );
        }),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Obx(() => _CategoryChip(category: controller.category.value)),
            Obx(() => GestureDetector(
                  onTap: controller.uploader.value.isEmpty
                      ? null
                      : () => _searchUploader(controller.uploader.value),
                  onSecondaryTapUp: (details) {
                    _showUploaderContextMenu(context, details.globalPosition,
                        controller.uploader.value);
                  },
                  onLongPressStart: (details) {
                    _showUploaderContextMenu(context, details.globalPosition,
                        controller.uploader.value);
                  },
                  child: Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(controller.uploader.value),
                    visualDensity: VisualDensity.compact,
                  ),
                )),
            Obx(() => Chip(
                  avatar: const Icon(Icons.photo_library, size: 16),
                  label: Text('common.pages'
                      .trParams({'count': '${controller.pageCount.value}'})),
                  visualDensity: VisualDensity.compact,
                )),
            Obx(() => InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showRatingDialog(context),
                  child: Chip(
                    avatar:
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                    label: Text(controller.rating.value.toStringAsFixed(1)),
                    visualDensity: VisualDensity.compact,
                  ),
                )),
            Obx(() {
              final fav = controller.favoriteName.value;
              if (fav == null) return const SizedBox.shrink();
              return Chip(
                avatar: Icon(Icons.favorite,
                    size: 16,
                    color: _favSlotColor(controller.favoriteSlot.value ?? 0)),
                label: Text(fav),
                visualDensity: VisualDensity.compact,
              );
            }),
            Obx(() => controller.language.value.isNotEmpty
                ? Chip(
                    avatar: const Icon(Icons.language, size: 16),
                    label: Text(controller.language.value),
                    visualDensity: VisualDensity.compact,
                  )
                : const SizedBox.shrink()),
            Obx(() => controller.fileSize.value.isNotEmpty
                ? Chip(
                    avatar: const Icon(Icons.storage, size: 16),
                    label: Text(controller.fileSize.value),
                    visualDensity: VisualDensity.compact,
                  )
                : const SizedBox.shrink()),
          ],
        ),
        Obx(() => controller.publishDate.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      _webPreferredTime(controller.publishDate.value),
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink()),
        Obx(() {
          final parent = controller.parentUrl.value;
          final newer = controller.newerVersionUrl.value;
          if (parent == null && newer == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 12,
              children: [
                if (parent != null)
                  InkWell(
                    onTap: () {
                      final m = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(parent);
                      if (m != null)
                        Get.toNamed('/web/gallery/${m.group(1)}/${m.group(2)}');
                    },
                    child: Text('detail.parentGallery'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline)),
                  ),
                if (newer != null)
                  InkWell(
                    onTap: () {
                      final m = RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(newer);
                      if (m != null)
                        Get.toNamed('/web/gallery/${m.group(1)}/${m.group(2)}');
                    },
                    child: Text('detail.newerVersion'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline)),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showRatingDialog(BuildContext context) {
    double selected = controller.rating.value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('detail.rateTitle'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starVal = (i + 1).toDouble();
                  final halfVal = i + 0.5;
                  return GestureDetector(
                    onTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        final localX = details.localPosition.dx;
                        setState(
                            () => selected = localX < 16 ? halfVal : starVal);
                      }
                    },
                    onTap: () => setState(() => selected = starVal),
                    child: Icon(
                      selected >= starVal
                          ? Icons.star
                          : selected >= halfVal
                              ? Icons.star_half
                              : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text('${selected.toStringAsFixed(1)} / 5.0'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('common.cancel'.tr)),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                controller.submitRating(selected);
              },
              child: Text('detail.rateSubmit'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final svc = Get.find<WebDownloadService>();
    return Obx(() {
      // Touch the maps to ensure reactivity
      final _ = svc.galleryTasks.length + svc.archiveTasks.length;
      final gTask = svc.getGalleryTask(controller.gid);
      final aTask = svc.getArchiveTask(controller.gid);
      final gStatus = gTask?['status'] as int?;
      final aStatus = aTask?['status'] as int?;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final newer = controller.newerVersionUrl.value;
            if (newer == null || !svc.isGalleryDownloaded(controller.gid)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  leading: Icon(Icons.system_update_alt,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text('detail.upgradeDownload'.tr),
                  trailing: FilledButton(
                    onPressed: controller.upgradeToNewVersion,
                    child: Text('common.ok'.tr),
                  ),
                ),
              ),
            );
          }),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Obx(() {
                final progress = controller.readProgress.value;
                final label = progress > 0
                    ? 'detail.readOnlineResume'
                        .trParams({'page': '${progress + 1}'})
                    : 'detail.readOnline'.tr;
                return FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text(label),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                  onPressed: () {
                    final q = controller.buildReaderQuery(
                        startPage: progress > 0 ? progress : null);
                    Get.toNamed(
                        '/web/reader/${controller.gid}/${controller.token}$q');
                  },
                );
              }),
              _buildGalleryDownloadButton(context, gTask, gStatus),
              if (gStatus == 3)
                FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text('detail.readDownloaded'.tr),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Get.toNamed(
                      '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(mode: 'downloaded')}'),
                ),
              _buildArchiveButton(context, aTask, aStatus),
              Obx(() => OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text('detail.hhDownload'.tr),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(160, 44)),
                    onPressed: controller.archiverUrl.isNotEmpty
                        ? () => _showHHDownloadDialog(context)
                        : null,
                  )),
              Obx(() => OutlinedButton.icon(
                    icon: const Icon(Icons.file_present),
                    label: Text('detail.torrentCount'.trParams(
                        {'count': '${controller.torrentCount.value}'})),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(160, 44)),
                    onPressed: controller.torrentCount.value > 0
                        ? () => _showTorrentsDialog(context)
                        : null,
                  )),
              if (gTask != null || aTask != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text('detail.deleteDownload'.tr,
                      style: const TextStyle(color: Colors.red)),
                  onPressed: () => _confirmDeleteDownload(
                      context, gTask != null, aTask != null),
                ),
            ],
          ),
          if (gStatus == 1 || gStatus == 2 || gStatus == 4)
            _buildProgressBar(context, gTask!),
          if (aStatus != null && aStatus >= 1 && aStatus <= 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('downloads.aStatus$aStatus'.tr,
                      style:
                          TextStyle(fontSize: 13, color: Colors.blue.shade700)),
                  const SizedBox(width: 8),
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _buildGalleryDownloadButton(
      BuildContext context, Map<String, dynamic>? task, int? status) {
    if (task == null || status == null || status == 0) {
      return FilledButton.tonalIcon(
        icon: const Icon(Icons.download),
        label: Text('detail.downloadGallery'.tr),
        style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
        onPressed: () => _showStartGalleryDownloadDialog(context),
      );
    }
    final svc = Get.find<WebDownloadService>();
    switch (status) {
      case 1: // Downloading
        final completed = task['completedCount'] as int? ?? 0;
        final total = task['pageCount'] as int? ?? 0;
        return FilledButton.tonalIcon(
          icon: Icon(Icons.pause_circle_outline, color: Colors.blue.shade900),
          label: Text('${'downloads.pause'.tr}  $completed/$total'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, 44),
            backgroundColor: Colors.blue.shade100,
            foregroundColor: Colors.blue.shade900,
          ),
          onPressed: () => svc.pauseGallery(controller.gid),
        );
      case 2: // Paused
        final completed = task['completedCount'] as int? ?? 0;
        final total = task['pageCount'] as int? ?? 0;
        return FilledButton.tonalIcon(
          icon: Icon(Icons.play_circle_outline, color: Colors.orange.shade900),
          label: Text('${'downloads.resume'.tr}  $completed/$total'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, 44),
            backgroundColor: Colors.orange.shade100,
            foregroundColor: Colors.orange.shade900,
          ),
          onPressed: () => svc.resumeGallery(controller.gid),
        );
      case 3: // Completed
        return FilledButton.tonalIcon(
          icon: Icon(Icons.check_circle, color: Colors.green.shade900),
          label: Text('detail.completed'.tr),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, 44),
            backgroundColor: Colors.green.shade100,
            foregroundColor: Colors.green.shade900,
          ),
          onPressed: () => Get.toNamed(
              '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(mode: 'downloaded')}'),
        );
      case 4: // Failed
        return FilledButton.tonalIcon(
          icon: Icon(Icons.refresh, color: Colors.red.shade900),
          label: Text('detail.retryDownload'.tr),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, 44),
            backgroundColor: Colors.red.shade100,
            foregroundColor: Colors.red.shade900,
          ),
          onPressed: () => svc.resumeGallery(controller.gid),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildArchiveButton(
      BuildContext context, Map<String, dynamic>? task, int? status) {
    if (task == null || status == null) {
      return Obx(() {
        final newer = controller.newerVersionUrl.value;
        final m = newer != null
            ? RegExp(r'/g/(\d+)/([^/]+)/').firstMatch(newer)
            : null;
        final buttons = controller.archiverUrl.isNotEmpty
            ? OutlinedButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: Text('detail.downloadArchive'.tr),
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                onPressed: () => _showStartArchiveDownloadDialog(context),
              )
            : const SizedBox.shrink();
        if (m == null) return buttons;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('detail.archiveNewVersionHint'.tr,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            TextButton(
              onPressed: () =>
                  Get.toNamed('/web/gallery/${m.group(1)}/${m.group(2)}'),
              child: Text('detail.openNewVersion'.tr),
            ),
            buttons,
          ],
        );
      });
    }
    final svc = Get.find<WebDownloadService>();
    if (status == 6) {
      return FilledButton.tonalIcon(
        icon: Icon(Icons.check_circle, color: Colors.green.shade900),
        label: Text('detail.archiveCompleted'.tr),
        style: FilledButton.styleFrom(
          minimumSize: const Size(160, 44),
          backgroundColor: Colors.green.shade100,
          foregroundColor: Colors.green.shade900,
        ),
        onPressed: () => Get.toNamed(
            '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(mode: 'archive')}'),
      );
    }
    if (status == 7) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.play_circle_outline, color: Colors.orange),
        label: Text('downloads.resume'.tr),
        onPressed: () => svc.resumeArchive(controller.gid),
      );
    }
    if (status == 8) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.refresh, color: Colors.red),
        label: Text('detail.retryDownload'.tr),
        onPressed: () => svc.resumeArchive(controller.gid),
      );
    }
    return OutlinedButton.icon(
      icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      label: Text('downloads.aStatus$status'.tr),
      onPressed: null,
    );
  }

  Widget _buildProgressBar(BuildContext context, Map<String, dynamic> task) {
    final completed = task['completedCount'] as int? ?? 0;
    final total = task['pageCount'] as int? ?? 0;
    final progress = total > 0 ? completed / total : 0.0;
    final error = task['error'] as String?;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              const SizedBox(width: 12),
              Text('$completed / $total',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ),
        ],
      ),
    );
  }

  void _confirmDeleteDownload(
      BuildContext context, bool hasGallery, bool hasArchive) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('detail.deleteDownload'.tr),
        content: Text('detail.deleteDownloadConfirm'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final svc = Get.find<WebDownloadService>();
              if (hasGallery) svc.deleteGallery(controller.gid);
              if (hasArchive) svc.deleteArchive(controller.gid);
            },
            child: Text('common.delete'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentTile(Map<String, dynamic> torrent) {
    final title = torrent['title']?.toString() ?? '';
    final postTime = _webPreferredTime(torrent['postTime']?.toString() ?? '');
    final size = torrent['size']?.toString() ?? '';
    final seeds = (torrent['seeds'] as num?)?.toInt() ?? 0;
    final peers = (torrent['peers'] as num?)?.toInt() ?? 0;
    final downloads = (torrent['downloads'] as num?)?.toInt() ?? 0;
    final downloadUrl = torrent['downloadUrl']?.toString() ?? '';
    final magnetUrl = torrent['magnetUrl']?.toString() ?? '';

    return ListTile(
      dense: true,
      leading: const Icon(Icons.file_present),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          if (postTime.isNotEmpty) Text(postTime),
          if (size.isNotEmpty) Text(size),
          Text('detail.torrentSeeds'.trParams({'count': '$seeds'})),
          Text('detail.torrentPeers'.trParams({'count': '$peers'})),
          Text('detail.torrentDownloads'.trParams({'count': '$downloads'})),
        ],
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'detail.downloadTorrent'.tr,
            onPressed: downloadUrl.isEmpty
                ? null
                : () => web.window.open(downloadUrl, '_blank'),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'detail.copyMagnet'.tr,
            onPressed: magnetUrl.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: magnetUrl));
                    Get.snackbar('hasCopiedToClipboard'.tr, magnetUrl,
                        snackPosition: SnackPosition.BOTTOM);
                  },
          ),
        ],
      ),
    );
  }

  void _showTorrentsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WebTorrentDialog(
        gid: controller.gid,
        token: controller.token,
        buildTorrentTile: _buildTorrentTile,
      ),
    );
  }

  void _showHHDownloadDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WebHHDownloadDialog(
        archivePageUrl: controller.archiverUrl.value,
      ),
    );
  }

  Widget _buildTags(BuildContext context) {
    return Obx(() {
      if (controller.tags.isEmpty) return const SizedBox.shrink();

      final accountWatchedBg = Get.find<WebWatchedTagStylesController>()
          .backgroundArgbByTagKey
          .value;
      final showVoteStatus = WebPreferenceSettings.showGalleryTagVoteStatus;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('detail.tags'.tr,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'tagVote.addTag'.tr,
                onPressed:
                    controller.apiuid != null && controller.apikey != null
                        ? () => _showAddTagDialog(context)
                        : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...controller.tags.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _namespaceColor(entry.key),
                          ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: entry.value.map((tag) {
                        final translated =
                            controller.getTranslatedTag(entry.key, tag);
                        final showTranslated = translated != tag;
                        final html =
                            controller.tagHtmlStyleArgb(entry.key, tag);
                        final rich = controller.tagRichMeta(entry.key, tag);
                        final voteStatus = showVoteStatus
                            ? (rich?['voteStatus'] as String? ?? 'none')
                            : 'none';
                        final htmlBg = html?.backgroundArgb;
                        final htmlFg = html?.colorArgb;
                        final watchedBgArgb =
                            WebWatchedTagStylesController.lookupBackgroundArgb(
                          accountWatchedBg,
                          entry.key,
                          tag,
                        );
                        final mergedBgArgb = htmlBg ?? watchedBgArgb;
                        final Color? bg =
                            mergedBgArgb != null ? Color(mergedBgArgb) : null;
                        final ns = _namespaceColor(entry.key);
                        final Color defaultFg =
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.white70
                                : Colors.black87;
                        final Color labelFg = htmlFg != null
                            ? Color(htmlFg)
                            : (bg != null
                                ? (ThemeData.estimateBrightnessForColor(bg) ==
                                        Brightness.light
                                    ? const Color(0xFF090909)
                                    : const Color(0xFFF1F1F1))
                                : defaultFg);
                        final Color chipBg = bg ?? ns.withValues(alpha: 0.14);
                        final Color borderColor = bg != null
                            ? bg.withValues(alpha: 0.9)
                            : (htmlFg != null
                                ? Color(htmlFg).withValues(alpha: 0.55)
                                : ns.withValues(alpha: 0.55));
                        return GestureDetector(
                          onSecondaryTapUp: (details) {
                            _showTagContextMenu(context, details.globalPosition,
                                entry.key, tag);
                          },
                          onLongPressStart: (details) {
                            _showTagContextMenu(context, details.globalPosition,
                                entry.key, tag);
                          },
                          child: Tooltip(
                            message: showTranslated ? tag : '',
                            child: ActionChip(
                              label: Text(
                                _tagLabelWithVoteStatus(
                                  showTranslated ? translated : tag,
                                  voteStatus,
                                ),
                                style: TextStyle(fontSize: 12, color: labelFg),
                              ),
                              backgroundColor: chipBg,
                              side: BorderSide(color: borderColor, width: 1),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onPressed: () {
                                final query = '${entry.key}:"$tag\$"';
                                Get.offAllNamed('/web/home',
                                    arguments: {'search': query});
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    });
  }

  void _showAddTagDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WebAddTagDialog(
        onSubmit: (tags) => _addTags(tags),
      ),
    );
  }

  void _showTagContextMenu(
      BuildContext context, Offset position, String namespace, String tag) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.search, size: 20),
            title:
                Text('tagVote.search'.tr, style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () {
            final query = '$namespace:"$tag\$"';
            Get.offAllNamed('/web/home', arguments: {'search': query});
          },
        ),
        if (controller.apiuid != null && controller.apikey != null) ...[
          PopupMenuItem(
            child: ListTile(
              leading:
                  const Icon(Icons.thumb_up, size: 20, color: Colors.green),
              title: Text('tagVote.voteUp'.tr,
                  style: const TextStyle(fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: () => _voteTag(namespace, tag, 1),
          ),
          PopupMenuItem(
            child: ListTile(
              leading:
                  const Icon(Icons.thumb_down, size: 20, color: Colors.red),
              title: Text('tagVote.voteDown'.tr,
                  style: const TextStyle(fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: () => _voteTag(namespace, tag, -1),
          ),
        ],
        PopupMenuItem(
          child: ListTile(
            leading:
                const Icon(Icons.favorite_outline, size: 20, color: Colors.red),
            title:
                Text('usertags.watch'.tr, style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _addUsertagFromDetail(namespace, tag, watch: true),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.visibility_off_outlined,
                size: 20, color: Colors.blueGrey),
            title: Text('usertags.hidden'.tr,
                style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _addUsertagFromDetail(namespace, tag, watch: false),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.block, size: 20, color: Colors.orange),
            title: Text('blockRule.blockTag'.tr,
                style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _quickBlockTag(namespace, tag),
        ),
      ],
    );
  }

  Future<void> _addUsertagFromDetail(
    String namespace,
    String tag, {
    required bool watch,
  }) async {
    try {
      int? tagSetNo;
      if (WebPreferenceSettings.enableDefaultTagSet) {
        tagSetNo = WebPreferenceSettings.defaultTagSetNo;
      }
      if (tagSetNo == null) {
        final result = await _showTagSetChoiceDialog();
        if (result == null) {
          return;
        }
        tagSetNo = result.tagSetNo;
        if (result.remember) {
          WebPreferenceSettings.saveDefaultTagSetNo(tagSetNo);
        }
      }

      await backendApiClient.addUsertag(
        tag: '$namespace:$tag',
        tagSetNo: tagSetNo,
        watch: watch,
        hidden: !watch,
      );
      Get.snackbar(
        'common.success'.tr,
        watch ? 'usertags.watchAdded'.tr : 'usertags.hiddenAdded'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      unawaited(Get.find<WebWatchedTagStylesController>().refresh());
      await controller.refreshDetail();
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        '$e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    }
  }

  Future<({int tagSetNo, bool remember})?> _showTagSetChoiceDialog() async {
    try {
      final data = await backendApiClient.listUsertags(tagset: 1);
      final sets =
          (data['tagSets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (sets.isEmpty) {
        return null;
      }
      var remember = false;
      return Get.dialog<({int tagSetNo, bool remember})>(
        StatefulBuilder(
          builder: (context, setDialogState) => SimpleDialog(
            title: Text('chooseTagSet'.tr),
            children: [
              ...sets.map((set) {
                final number = (set['number'] as num?)?.toInt() ?? 1;
                return ListTile(
                  title: Text(set['name']?.toString() ?? '$number'),
                  onTap: () => Navigator.of(context).pop((
                    tagSetNo: number,
                    remember: remember,
                  )),
                );
              }),
              if (WebPreferenceSettings.enableDefaultTagSet)
                CheckboxListTile(
                  dense: true,
                  title: Text('asYourDefault'.tr),
                  value: remember,
                  onChanged: (value) =>
                      setDialogState(() => remember = value ?? false),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'usertags.loadFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
      return null;
    }
  }

  void _showUploaderContextMenu(
      BuildContext context, Offset position, String uploader) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.search, size: 20),
            title: Text('tagVote.searchUploader'.tr,
                style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _searchUploader(uploader),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.block, size: 20, color: Colors.orange),
            title: Text('blockRule.blockUploader'.tr,
                style: const TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _quickBlockUploader(uploader),
        ),
      ],
    );
  }

  void _searchUploader(String uploader) {
    final value = uploader.trim();
    if (value.isEmpty) return;
    Get.offAllNamed('/web/home',
        arguments: {'search': _webUploaderSearchQuery(value)});
  }

  void _searchKeyword(String keyword) {
    final value = keyword.trim();
    if (value.isEmpty) return;
    Get.offAllNamed('/web/home', arguments: {'search': value});
  }

  Future<void> _voteTag(String namespace, String tag, int vote) async {
    try {
      final result = await backendApiClient.voteTag(
        gid: controller.gid,
        token: controller.token,
        apiuid: controller.apiuid!,
        apikey: controller.apikey!,
        namespace: namespace,
        tag: tag,
        vote: vote,
      );
      if (result['success'] == false) {
        throw result['message'] ?? result['error'] ?? 'Tag vote failed';
      }
      controller.updateTagVoteStatus(namespace, tag, vote);
      Get.snackbar(
        'tagVote.success'.tr,
        vote > 0
            ? 'tagVote.votedUp'.trParams({'tag': tag})
            : 'tagVote.votedDown'.trParams({'tag': tag}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'tagVote.failed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<bool> _addTags(String tags) async {
    final value = tags.trim();
    if (value.isEmpty) return false;
    if (controller.apiuid == null || controller.apikey == null) {
      Get.snackbar('common.error'.tr, 'detail.rateLoginRequired'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    try {
      final result = await backendApiClient.addTags(
        gid: controller.gid,
        token: controller.token,
        apiuid: controller.apiuid!,
        apikey: controller.apikey!,
        tags: value,
      );
      if (result['success'] == false) {
        throw result['message'] ?? result['error'] ?? 'Add tag failed';
      }
      Get.snackbar('tagVote.addSuccess'.tr, value,
          snackPosition: SnackPosition.BOTTOM);
      await controller.refreshDetail();
      return true;
    } catch (e) {
      Get.snackbar(
          'common.error'.tr, 'tagVote.addFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.7));
      return false;
    }
  }

  Future<void> _quickBlockTag(String namespace, String tag) async {
    try {
      await backendApiClient.saveBlockRule(
        target: 'gallery',
        attribute: 'tag',
        pattern: 'like',
        expression: '$namespace:$tag',
      );
      Get.snackbar('blockRule.blocked'.tr,
          'blockRule.tagBlocked'.trParams({'tag': '$namespace:$tag'}),
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _quickBlockUploader(String uploader) async {
    try {
      await backendApiClient.saveBlockRule(
        target: 'gallery',
        attribute: 'uploader',
        pattern: 'equal',
        expression: uploader,
      );
      Get.snackbar('blockRule.blocked'.tr,
          'blockRule.uploaderBlocked'.trParams({'uploader': uploader}),
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildThumbnails(BuildContext context) {
    return Obx(() {
      final total = controller.pageCount.value;
      if (total <= 0) return const SizedBox.shrink();
      final displayCount = total > 40 ? 40 : total;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('detail.thumbnails'.trParams({'count': '$total'}),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (controller.isThumbsLoading.value)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final configuredColumns = _webDetailThumbnailColumnsSetting();
              final autoColumns = constraints.maxWidth > 900
                  ? 6
                  : constraints.maxWidth > 640
                      ? 5
                      : constraints.maxWidth > 420
                          ? 4
                          : 3;
              final columns = configuredColumns ?? autoColumns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: displayCount,
                itemBuilder: (ctx, index) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Get.toNamed(
                        '/web/reader/${controller.gid}/${controller.token}${controller.buildReaderQuery(startPage: index)}'),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        Positioned.fill(
                          child: WebEhThumbnail(
                            data: _thumbMapForDetail(controller, index),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (total > 40) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: () => Get.toNamed(
                    '/web/thumbnails/${controller.gid}/${controller.token}'),
                child: Text('detail.viewAllThumbnails'.tr),
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _buildComments(BuildContext context) {
    return Obx(() {
      final disableCommentVotes =
          controller.comments.any((comment) => comment['fromMe'] == true);
      final showAllInline = WebPreferenceSettings.showAllComments;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    'detail.comments'
                        .trParams({'count': '${controller.comments.length}'}),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (controller.comments.isNotEmpty && !showAllInline)
                TextButton(
                  onPressed: () => _showAllComments(context),
                  child: Text('detail.allComments'.tr),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _CommentInput(controller: controller),
          const SizedBox(height: 8),
          if (controller.comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('comment.placeholder'.tr,
                      style: const TextStyle(color: Colors.grey))),
            )
          else if (showAllInline)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.comments.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CommentCard(
                  comment: controller.comments[i],
                  onVote: (id, vote) => controller.voteComment(id, vote),
                  disableVoting: disableCommentVotes,
                  onBlockUser: (comment) =>
                      _confirmBlockCommentUser(context, comment),
                  onEdit: (comment) => _showEditCommentDialog(context, comment),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: controller.comments.length,
                itemBuilder: (ctx, i) => SizedBox(
                  width: 280,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CommentCard(
                      comment: controller.comments[i],
                      onVote: (id, vote) => controller.voteComment(id, vote),
                      disableVoting: disableCommentVotes,
                      onBlockUser: (comment) =>
                          _confirmBlockCommentUser(context, comment),
                      onEdit: (comment) =>
                          _showEditCommentDialog(context, comment),
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  void _showAllComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('detail.allComments'.tr,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: Obx(() {
                final disableCommentVotes = controller.comments
                    .any((comment) => comment['fromMe'] == true);
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: controller.comments.length,
                  itemBuilder: (ctx, i) => _CommentCard(
                    comment: controller.comments[i],
                    onVote: (id, vote) => controller.voteComment(id, vote),
                    disableVoting: disableCommentVotes,
                    onBlockUser: (comment) =>
                        _confirmBlockCommentUser(ctx, comment),
                    onEdit: (comment) => _showEditCommentDialog(ctx, comment),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBlockCommentUser(
      BuildContext context, Map<String, dynamic> comment) async {
    final author = comment['author']?.toString() ?? 'detail.anonymous'.tr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('blockRule.blockCommentUser'.tr),
        content: Text(
            'blockRule.blockCommentUserConfirm'.trParams({'user': author})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('blockRule.blocked'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.blockCommentUser(comment);
    }
  }

  void _showEditCommentDialog(
      BuildContext context, Map<String, dynamic> comment) {
    final commentId = int.tryParse(comment['id']?.toString() ?? '');
    if (commentId == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _WebEditCommentDialog(
        initialText: _plainCommentText(comment['body']?.toString() ?? ''),
        onSubmit: (text) =>
            controller.updateComment(commentId: commentId, text: text),
      ),
    );
  }

  String _plainCommentText(String body) {
    return body
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }
}

class _CommentInput extends StatefulWidget {
  final WebGalleryDetailController controller;
  const _CommentInput({required this.controller});

  @override
  State<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<_CommentInput> {
  final _textController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'comment.placeholder'.tr,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            maxLines: 2,
            minLines: 1,
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          onPressed: _sending ? null : _send,
          tooltip: 'comment.send'.tr,
        ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await widget.controller.postComment(text);
    _textController.clear();
    setState(() => _sending = false);
  }
}

class _WebEditCommentDialog extends StatefulWidget {
  final String initialText;
  final Future<bool> Function(String text) onSubmit;

  const _WebEditCommentDialog({
    required this.initialText,
    required this.onSubmit,
  });

  @override
  State<_WebEditCommentDialog> createState() => _WebEditCommentDialogState();
}

class _WebEditCommentDialogState extends State<_WebEditCommentDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.length <= 2) {
      Get.snackbar('common.error'.tr, 'comment.tooShort'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _saving = true);
    try {
      final ok = await widget.onSubmit(text);
      if (ok && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('comment.update'.tr),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 10,
          decoration: InputDecoration(
            labelText: 'comment.atLeast3Characters'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text('common.save'.tr),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _CommentCard extends StatelessWidget {
  final Map<String, dynamic> comment;
  final void Function(int commentId, int vote)? onVote;
  final void Function(Map<String, dynamic> comment)? onBlockUser;
  final void Function(Map<String, dynamic> comment)? onEdit;
  final bool compact;
  final bool disableVoting;
  const _CommentCard(
      {required this.comment,
      this.onVote,
      this.onBlockUser,
      this.onEdit,
      this.compact = false,
      this.disableVoting = false});

  @override
  Widget build(BuildContext context) {
    final author = comment['author'] as String? ?? 'detail.anonymous'.tr;
    final date = _webPreferredTime(comment['date'] as String? ?? '');
    final score = comment['score'] as String? ?? '';
    final scoreDetails = (comment['scoreDetails'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        [];
    final votedUp = comment['votedUp'] == true;
    final votedDown = comment['votedDown'] == true;
    final fromMe = comment['fromMe'] == true;
    final body = comment['body'] as String? ?? '';
    final commentId = int.tryParse(comment['id']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(author,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (score.isNotEmpty)
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: scoreDetails.isEmpty
                        ? null
                        : () => _showScoreDetails(context, scoreDetails),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: score.startsWith('-')
                            ? Colors.red.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(score,
                          style: TextStyle(
                            fontSize: 12,
                            color: score.startsWith('-')
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          )),
                    ),
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('uploader'.tr,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (score.isNotEmpty &&
                    !fromMe &&
                    !disableVoting &&
                    commentId != null &&
                    onVote != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => onVote!(commentId, 1),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        votedUp ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 16,
                        color: votedUp
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => onVote!(commentId, -1),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        votedDown
                            ? Icons.thumb_down
                            : Icons.thumb_down_outlined,
                        size: 16,
                        color: votedDown
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ],
                if (fromMe && onEdit != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => onEdit!(comment),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit_note, size: 18),
                    ),
                  ),
                ],
                if (onBlockUser != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => onBlockUser!(comment),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.block, size: 16),
                    ),
                  ),
                ],
              ],
            ),
            if (date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(date,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey)),
              ),
            const SizedBox(height: 4),
            _LinkedCommentBody(
              body: body,
              maxLines: compact ? 4 : 100,
              showImages: !compact,
            ),
          ],
        ),
      ),
    );
  }

  void _showScoreDetails(BuildContext context, List<String> scoreDetails) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('comment.scoreDetails'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: scoreDetails.map(Text.new).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.ok'.tr),
          ),
        ],
      ),
    );
  }
}

class _CommentTextRun {
  final String text;
  final String? url;
  final bool image;

  const _CommentTextRun(this.text, {this.url, this.image = false});
}

class _LinkedCommentBody extends StatefulWidget {
  final String body;
  final int maxLines;
  final bool showImages;

  const _LinkedCommentBody({
    required this.body,
    required this.maxLines,
    this.showImages = false,
  });

  @override
  State<_LinkedCommentBody> createState() => _LinkedCommentBodyState();
}

class _LinkedCommentBodyState extends State<_LinkedCommentBody> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final style = Theme.of(context).textTheme.bodyMedium;
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    final spans = <InlineSpan>[];
    for (final run in _parseCommentRuns(widget.body)) {
      if (run.text.isEmpty && !run.image) continue;
      final url = run.url;
      if (run.image && widget.showImages && url != null && url.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 360, maxHeight: 260),
                child: WebProxiedImage(
                  sourceUrl: url,
                  fit: BoxFit.contain,
                  readerErrorChild: Container(
                    width: 160,
                    height: 90,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
          ),
        ));
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      if (url == null || url.isEmpty) {
        spans.add(TextSpan(text: run.text, style: style));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openCommentUrl(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: run.text,
        style: linkStyle,
        recognizer: recognizer,
      ));
    }

    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

List<_CommentTextRun> _parseCommentRuns(String body) {
  final fragment = html_parser.parseFragment(
    body.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '<br>'),
  );
  final runs = <_CommentTextRun>[];

  void addText(String text, {String? url}) {
    if (text.isEmpty) return;
    if (url != null && url.isNotEmpty) {
      runs.add(_CommentTextRun(text, url: _normalizeCommentUrl(url)));
      return;
    }
    runs.addAll(_splitPlainCommentLinks(text));
  }

  void walk(html_dom.Node node) {
    if (node is html_dom.Text) {
      addText(node.text);
      return;
    }
    if (node is! html_dom.Element) return;
    final tag = node.localName?.toLowerCase();
    if (tag == 'br') {
      addText('\n');
      return;
    }
    if (tag == 'a') {
      final href = node.attributes['href'] ?? '';
      addText(node.text.isEmpty ? href : node.text, url: href);
      return;
    }
    if (tag == 'img') {
      final src = node.attributes['src'] ?? '';
      if (src.isEmpty) return;
      runs.add(_CommentTextRun('[${'image'.tr}]',
          url: _normalizeCommentUrl(src), image: true));
      return;
    }
    for (final child in node.nodes) {
      walk(child);
    }
  }

  for (final node in fragment.nodes) {
    walk(node);
  }
  return runs;
}

List<_CommentTextRun> _splitPlainCommentLinks(String text) {
  final urlRe = RegExp(r'https?://[^\s<>"\]]+', caseSensitive: false);
  final runs = <_CommentTextRun>[];
  var last = 0;
  for (final m in urlRe.allMatches(text)) {
    if (m.start > last) {
      runs.add(_CommentTextRun(text.substring(last, m.start)));
    }
    final raw = m.group(0)!;
    final trailing = RegExp(r'[.,;:!?)]*$').firstMatch(raw)?.group(0) ?? '';
    final url =
        trailing.isEmpty ? raw : raw.substring(0, raw.length - trailing.length);
    if (url.isNotEmpty) runs.add(_CommentTextRun(url, url: url));
    if (trailing.isNotEmpty) runs.add(_CommentTextRun(trailing));
    last = m.end;
  }
  if (last < text.length) runs.add(_CommentTextRun(text.substring(last)));
  return runs;
}

String _normalizeCommentUrl(String url) {
  if (url.startsWith('//')) return 'https:$url';
  return url;
}

Future<void> _openCommentUrl(String url) async {
  final normalized = _normalizeCommentUrl(url);
  final galleryUrl = GalleryUrl.tryParse(normalized);
  if (galleryUrl != null) {
    Get.toNamed('/web/gallery/${galleryUrl.gid}/${galleryUrl.token}');
    return;
  }

  final imagePageUrl = GalleryImagePageUrl.tryParse(normalized);
  if (imagePageUrl != null) {
    try {
      final resolved = await backendApiClient.resolveImagePageUrl(
        imagePageUrl.url,
      );
      final gid = (resolved['gid'] as num?)?.toInt();
      final token = resolved['token']?.toString() ?? '';
      final pageNo =
          (resolved['pageNo'] as num?)?.toInt() ?? imagePageUrl.pageNo;
      if (gid == null || token.isEmpty) {
        throw resolved['error']?.toString() ?? 'Parent gallery not found';
      }
      final startPage = (pageNo - 1).clamp(0, 1 << 30);
      Get.toNamed('/web/reader/$gid/$token?startPage=$startPage');
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'detail.loadFailed'.trParams({'error': '$e'}),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.7),
      );
    }
    return;
  }

  web.window.open(normalized, '_blank');
}

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _categoryColor(category),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(category,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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

Color _namespaceColor(String namespace) {
  return switch (namespace.toLowerCase()) {
    'artist' => Colors.deepPurple,
    'group' || 'circle' => Colors.teal,
    'parody' => Colors.orange,
    'character' => Colors.green,
    'female' => Colors.pink,
    'male' => Colors.blue,
    'language' => Colors.brown,
    'reclass' => Colors.red,
    'other' => Colors.grey,
    _ => Colors.grey.shade600,
  };
}

String _tagLabelWithVoteStatus(String label, String voteStatus) {
  return switch (voteStatus) {
    'up' => '$label↑',
    'down' => '$label↓',
    _ => label,
  };
}

Color _favSlotColor(int slot) {
  const colors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];
  return colors[slot % colors.length];
}

class _WebTorrentDialog extends StatefulWidget {
  final int gid;
  final String token;
  final Widget Function(Map<String, dynamic> torrent) buildTorrentTile;

  const _WebTorrentDialog({
    required this.gid,
    required this.token,
    required this.buildTorrentTile,
  });

  @override
  State<_WebTorrentDialog> createState() => _WebTorrentDialogState();
}

class _WebTorrentDialogState extends State<_WebTorrentDialog> {
  bool _isLoading = true;
  String _error = '';
  List<Map<String, dynamic>> _torrents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final torrents =
          await backendApiClient.fetchGalleryTorrents(widget.gid, widget.token);
      if (mounted) {
        setState(() => _torrents = torrents);
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'detail.loadTorrentsFailed'.trParams({'error': '$e'}));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest =
        _torrents.where((torrent) => torrent['outdated'] != true).toList();
    final outdated =
        _torrents.where((torrent) => torrent['outdated'] == true).toList();
    return AlertDialog(
      title: Text('detail.torrents'.tr),
      content: SizedBox(
        width: 560,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text('common.retry'.tr),
                          onPressed: _load,
                        ),
                      ],
                    ),
                  )
                : _torrents.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('detail.noTorrents'.tr),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 460),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ...latest.map(widget.buildTorrentTile),
                            if (latest.isNotEmpty && outdated.isNotEmpty)
                              const Divider(),
                            if (outdated.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'detail.outdatedTorrents'.tr,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ...outdated.map(widget.buildTorrentTile),
                          ],
                        ),
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr),
        ),
      ],
    );
  }
}

class _WebAddTagDialog extends StatefulWidget {
  final Future<bool> Function(String tags) onSubmit;

  const _WebAddTagDialog({required this.onSubmit});

  @override
  State<_WebAddTagDialog> createState() => _WebAddTagDialogState();
}

class _WebAddTagDialogState extends State<_WebAddTagDialog> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tags = _controller.text.trim();
    if (tags.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final ok = await widget.onSubmit(tags);
      if (ok && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('tagVote.addTag'.tr),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'tagVote.addTagHint'.tr,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr),
        ),
        FilledButton.icon(
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text('tagVote.addTag'.tr),
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }
}

class _WebHHDownloadDialog extends StatefulWidget {
  final String archivePageUrl;

  const _WebHHDownloadDialog({required this.archivePageUrl});

  @override
  State<_WebHHDownloadDialog> createState() => _WebHHDownloadDialogState();
}

class _WebHHDownloadDialogState extends State<_WebHHDownloadDialog> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _error = '';
  Map<String, dynamic> _info = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final info =
          await backendApiClient.fetchGalleryHHInfo(widget.archivePageUrl);
      if (mounted) {
        setState(() => _info = info);
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = 'detail.loadHHFailed'.trParams({'error': '$e'}));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit(Map<String, dynamic> archive) async {
    final resolution = archive['resolution']?.toString() ?? '';
    if (resolution.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final message = await backendApiClient.requestGalleryHHDownload(
        widget.archivePageUrl,
        resolution,
      );
      if (!mounted) return;
      Navigator.pop(context);
      Get.snackbar(
        'detail.hhDownload'.tr,
        message.isEmpty ? 'detail.hhSubmitted'.tr : message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = 'detail.hhSubmitFailed'.trParams({'error': '$e'}));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final archives = (_info['archives'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        [];
    final gp = _info['gpCount'];
    final credits = _info['creditCount'];
    return AlertDialog(
      title: Text('detail.hhDownload'.tr),
      content: SizedBox(
        width: 520,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text('common.retry'.tr),
                          onPressed: _isSubmitting ? null : _load,
                        ),
                      ],
                    ),
                  )
                : archives.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('detail.noHHArchives'.tr),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 460),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (gp != null || credits != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      if (gp != null)
                                        Chip(
                                          avatar: const Icon(Icons.toll),
                                          label: Text('GP: $gp'),
                                        ),
                                      if (credits != null)
                                        Chip(
                                          avatar:
                                              const Icon(Icons.paid_outlined),
                                          label: Text('Credits: $credits'),
                                        ),
                                    ],
                                  ),
                                ),
                              ...archives.map((archive) {
                                final desc =
                                    archive['resolutionDesc']?.toString() ?? '';
                                final size = archive['size']?.toString() ?? '';
                                final cost = archive['cost']?.toString() ?? '';
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: OutlinedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => _submit(archive),
                                    style: OutlinedButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 14),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                            Icons.cloud_download_outlined),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(desc,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                children: [
                                                  if (size.isNotEmpty)
                                                    Text(size),
                                                  if (cost.isNotEmpty)
                                                    Text(cost),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              if (_isSubmitting)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: LinearProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr),
        ),
      ],
    );
  }
}

class _WebFavoriteFolderDialog extends StatefulWidget {
  final WebGalleryDetailController controller;
  const _WebFavoriteFolderDialog({required this.controller});

  @override
  State<_WebFavoriteFolderDialog> createState() =>
      _WebFavoriteFolderDialogState();
}

class _WebFavoriteFolderDialogState extends State<_WebFavoriteFolderDialog> {
  late final TextEditingController _note;
  bool _loadingNote = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
    if (widget.controller.favoriteSlot.value != null) {
      _loadingNote = true;
      backendApiClient
          .fetchFavoriteNote(widget.controller.gid, widget.controller.token)
          .then((n) {
        if (mounted) {
          setState(() {
            _note.text = n;
            _loadingNote = false;
          });
        }
      }).catchError((_) {
        if (mounted) setState(() => _loadingNote = false);
      });
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AlertDialog(
      title: Text('detail.addToFavTitle'.tr),
      content: SizedBox(
        width: 420,
        child: _loadingNote
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _note,
                      maxLines: 3,
                      maxLength: 200,
                      inputFormatters: [LengthLimitingTextInputFormatter(200)],
                      decoration: InputDecoration(
                        labelText: 'detail.favNoteHint'.tr,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(10, (i) {
                      final isSel = c.favoriteSlot.value == i;
                      final countStr = c.favoriteCounts.length > i
                          ? '${c.favoriteCounts[i]}'
                          : '';
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.favorite, color: _favSlotColor(i)),
                        title: Text(c.getFavSlotName(i)),
                        subtitle: countStr.isEmpty ? null : Text(countStr),
                        selected: isSel,
                        onTap: () async {
                          Navigator.pop(context);
                          await c.applyFavoriteFolder(i, _note.text);
                        },
                      );
                    }),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr),
        ),
      ],
    );
  }
}

class _SelectableSearchText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final ValueChanged<String> onSearch;

  const _SelectableSearchText({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      minLines: 1,
      maxLines: maxLines,
      style: style,
      contextMenuBuilder: (context, editableTextState) {
        final toolbar = AdaptiveTextSelectionToolbar.buttonItems(
          buttonItems: editableTextState.contextMenuButtonItems,
          anchors: editableTextState.contextMenuAnchors,
        );
        final selection = editableTextState.currentTextEditingValue.selection;
        if (!selection.isCollapsed) {
          toolbar.buttonItems?.add(
            ContextMenuButtonItem(
              label: 'tagVote.search'.tr,
              onPressed: () {
                ContextMenuController.removeAny();
                onSearch(selection.textInside(text));
              },
            ),
          );
        }
        return toolbar;
      },
    );
  }
}
