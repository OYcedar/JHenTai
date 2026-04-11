import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart' as html_pkg;
import 'package:jhentai/src/consts/eh_consts.dart';
import 'package:jhentai/src/exception/eh_parse_exception.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_reader_wheel.dart';
import 'package:jhentai/src/pages_web/web_online_image_page_parse.dart';
import 'package:jhentai/src/pages_web/web_eh_thumbnail.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';
import 'package:web/web.dart' as web;

/// Same intent as UIConfig.scrollBehaviourWithoutScrollBarWithMouse: PageView /
/// ListView / thumbnail strip accept mouse drag on web (default Material omits mouse).
final ScrollBehavior _webReaderScrollBehavior =
    const MaterialScrollBehavior().copyWith(
  dragDevices: {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  },
  scrollbars: false,
);

/// Bottom thumbnail strip: thumb width (40) + horizontal margin (2+2).
const double _kWebReaderStripItemExtent = 44.0;

/// Start decoding network images into GPU cache (aligned with native reader preload).
String _webReaderImageFileExtension(String url) {
  try {
    final p = Uri.parse(url).path;
    final i = p.lastIndexOf('.');
    if (i > 0 && i < p.length - 1) return p.substring(i);
  } catch (_) {}
  return '.jpg';
}

String _webReaderSafeFileToken(String t) =>
    t.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');

void _webTriggerBytesDownload(Uint8List bytes, String fileName) {
  final parts = [bytes.toJS].toJS;
  final blob = web.Blob(parts);
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = objectUrl;
  anchor.download = fileName;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(objectUrl);
}

Future<void> _webDownloadImageFromSourceUrl(
  String sourceUrl, {
  required String fileName,
}) async {
  if (sourceUrl.isEmpty) return;
  if (!backendApiClient.shouldProxyImageUsePost(sourceUrl)) {
    web.window.open(backendApiClient.proxyImageUrl(sourceUrl), '_blank');
    return;
  }
  try {
    final bytes = await backendApiClient.fetchProxiedImageBytes(sourceUrl);
    if (bytes.isEmpty) {
      Get.snackbar('common.error'.tr, 'reader.saveFailed'.tr);
      return;
    }
    _webTriggerBytesDownload(bytes, fileName);
  } catch (_) {
    Get.snackbar('common.error'.tr, 'reader.saveFailed'.tr);
  }
}

Future<void> _webReaderCopyText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  Get.snackbar('common.success'.tr, 'hasCopiedToClipboard'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2));
}

/// Pop-up menu for a reader image (online / downloaded / archive / local).
Future<void> showWebReaderImageContextMenu(
  BuildContext context,
  WebReaderController controller,
  int index, {
  Offset? position,
}) async {
  final url = index < controller.imageUrls.length ? controller.imageUrls[index] : '';
  if (url.isEmpty) return;

  final box = context.findRenderObject() as RenderBox?;
  final pos = position ??
      box?.localToGlobal(const Offset(80, 80)) ??
      const Offset(80, 80);

  final mode = controller.mode;
  if (mode == ReaderMode.online) {
    final orig = controller.originalImageUrlAt(index);
    final showOriginal = orig != null &&
        orig.isNotEmpty &&
        controller.ehLoggedInForOriginal.value;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'reload', child: Text('reload'.tr)),
        PopupMenuItem(value: 'share', child: Text('share'.tr)),
        PopupMenuItem(
          value: 'save',
          child: Text('${'save'.tr}(${'resampleImage'.tr})'),
        ),
        if (showOriginal)
          PopupMenuItem(
            value: 'original',
            child: Text('${'save'.tr}(${'originalImage'.tr})'),
          ),
      ],
    );
    if (!context.mounted) return;
    final ext = _webReaderImageFileExtension(url);
    final fname =
        '${controller.gid}_${_webReaderSafeFileToken(controller.token)}_${index + 1}$ext';
    switch (selected) {
      case 'reload':
        controller.retryImage(index);
        break;
      case 'share':
        await _webReaderCopyText(url);
        break;
      case 'save':
        await _webDownloadImageFromSourceUrl(url, fileName: fname);
        break;
      case 'original':
        if (orig != null) {
          final oext = _webReaderImageFileExtension(orig);
          final oname =
              '${controller.gid}_${_webReaderSafeFileToken(controller.token)}_${index + 1}_orig$oext';
          await _webDownloadImageFromSourceUrl(orig, fileName: oname);
        }
        break;
      default:
        break;
    }
    return;
  }

  // Downloaded / archive / local: align with native local menu (share, save, re-download).
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    items: [
      PopupMenuItem(value: 'share', child: Text('share'.tr)),
      PopupMenuItem(value: 'save', child: Text('save'.tr)),
      if (mode == ReaderMode.downloaded || mode == ReaderMode.archive)
        PopupMenuItem(value: 'redl', child: Text('reDownload'.tr)),
    ],
  );
  if (!context.mounted) return;
  switch (selected) {
    case 'share':
      await _webReaderCopyText(url);
      break;
    case 'save':
      web.window.open(url, '_blank');
      break;
    case 'redl':
      Get.snackbar('reDownload'.tr, 'reader.redownloadHint'.tr);
      Get.toNamed('/web/downloads');
      break;
    default:
      break;
  }
}

void _precacheNetworkImage(String proxyGetUrl) {
  final provider = NetworkImage(proxyGetUrl);
  final stream = provider.resolve(const ImageConfiguration());
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo image, bool synchronousCall) {
      stream.removeListener(listener);
    },
    onError: (Object exception, StackTrace? stackTrace) {
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
}

/// Pop the reader route when the navigator stack allows; otherwise replace with
/// gallery detail or local list (browser deep-link / refresh leaves no route to pop).
///
/// Uses [Navigator.maybePop] on the root navigator so Web history stays aligned with
/// the real stack (avoids canPop/Get.back occasionally disagreeing on Flutter Web).
void _popOrExitWebReader(BuildContext context, WebReaderController c) {
  Navigator.of(context, rootNavigator: true).maybePop().then((didPop) {
    if (didPop) return;
    if (c.gid == 0 && c.token == 'local') {
      Get.offNamed('/web/local');
    } else {
      Get.offNamed('/web/gallery/${c.gid}/${c.token}');
    }
  });
}

enum ReaderMode { online, downloaded, archive, local }
enum ReadDirection { ltr, rtl, vertical, fitWidth, doubleColumn }

class WebReaderController extends GetxController {
  late int gid;
  late String token;
  late ReaderMode mode;

  final imageUrls = <String>[].obs;
  final galleryThumbnails = <Map<String, dynamic>>[].obs;
  final currentPage = 0.obs;
  final totalPages = 0.obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final showOverlay = true.obs;
  final readDirection = ReadDirection.ltr.obs;
  /// Mouse wheel over image: page turn vs zoom (PageView modes only; see [kWebReaderWheelActionKey]).
  final wheelAction = WebReaderWheelAction.page.obs;
  /// When wheel turns pages, invert next/prev mapping (see [kWebReaderWheelInvertPageKey]).
  final wheelInvertPageTurn = false.obs;

  final isAutoMode = false.obs;
  final autoInterval = 5.0.obs;
  Timer? _autoTimer;

  final _imagePageUrls = <String>[];
  final _loadedImageUrls = <int, String>{};
  /// Online: indices currently fetching HTML to resolve CDN URL (for visible loading shell).
  final resolvingImageIndexes = <int>[].obs;
  /// Online: EH `nl` reload key from last successful image-page parse (per page index).
  final _imagePageReloadKeys = <int, String>{};
  /// Online: “original” download href from image-page HTML when present.
  final _originalImageUrls = <int, String>{};
  /// Backend `/api/health` `loggedIn` — used to show “save original” like native.
  final ehLoggedInForOriginal = false.obs;
  /// Double-column: first screen shows only page 0 (persisted).
  final displayFirstPageAlone = false.obs;
  /// Gallery title from route args, query `title=`, or API when available.
  final galleryTitle = ''.obs;
  /// Online: user-visible message when HTML parse / image-page fetch fails for a page.
  final imageLoadErrors = <int, String>{}.obs;
  int _resolveGeneration = 0;
  final _activeResolveGeneration = <int, int>{};

  late PageController pageController;
  final scrollController = ScrollController();
  /// Horizontal thumbnail strip at bottom (mouse drag + wheel).
  final stripScrollController = ScrollController();
  final focusNode = FocusNode();

  List<String>? localImages;

  Timer? _saveProgressTimer;
  int? _startPage;
  Timer? _stripScrollTimer;
  late final Worker _stripScrollOnPageWorker;

  @override
  void onInit() {
    super.onInit();
    _readWebRouteAndQueryParams();

    pageController = PageController();
    _loadSavedDirection();
    _loadDisplayFirstPageAlone();
    _refreshEhLoggedInForOriginal();
    _loadWheelAction();
    _loadGallery();
    _stripScrollOnPageWorker =
        ever(currentPage, (_) => _scheduleScrollThumbnailStripToCurrent());
  }

  @override
  void onClose() {
    _stripScrollOnPageWorker.dispose();
    _stripScrollTimer?.cancel();
    _autoTimer?.cancel();
    _saveProgressTimer?.cancel();
    _saveProgressNow();
    pageController.dispose();
    scrollController.dispose();
    stripScrollController.dispose();
    focusNode.dispose();
    super.onClose();
  }

  void _scheduleScrollThumbnailStripToCurrent() {
    _stripScrollTimer?.cancel();
    _stripScrollTimer =
        Timer(const Duration(milliseconds: 48), _scrollThumbnailStripToCurrent);
  }

  void _scrollThumbnailStripToCurrent() {
    final c = stripScrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients || totalPages.value <= 1) return;
      final page =
          currentPage.value.clamp(0, totalPages.value - 1);
      final viewport = c.position.viewportDimension;
      var offset = page * _kWebReaderStripItemExtent -
          viewport / 2 +
          _kWebReaderStripItemExtent / 2;
      offset = offset.clamp(0.0, c.position.maxScrollExtent);
      if ((c.offset - offset).abs() > 0.5) {
        c.jumpTo(offset);
      }
    });
  }

  /// Reads `?startPage=` / `?mode=` from the browser URL; Get.parameters often omits query on Flutter Web.
  void _readWebRouteAndQueryParams() {
    final uri = Uri.parse(web.window.location.href);
    final q = uri.queryParameters;

    _startPage = int.tryParse(q['startPage'] ?? Get.parameters['startPage'] ?? '');

    final modeParam = q['mode'] ?? Get.parameters['mode'] ?? 'online';
    mode = switch (modeParam) {
      'downloaded' => ReaderMode.downloaded,
      'archive' => ReaderMode.archive,
      'local' => ReaderMode.local,
      _ => ReaderMode.online,
    };

    var gidStr = Get.parameters['gid'] ?? '';
    var tokenStr = Get.parameters['token'] ?? '';
    if (gidStr.isEmpty || tokenStr.isEmpty) {
      final segs = uri.pathSegments;
      final i = segs.indexOf('reader');
      if (i >= 0 && i + 2 < segs.length) {
        gidStr = segs[i + 1];
        tokenStr = segs[i + 2];
      }
    }
    gid = int.tryParse(gidStr) ?? 0;
    token = tokenStr;

    final titleQ = q['title'] ?? Get.parameters['title'];
    if (titleQ != null && titleQ.isNotEmpty) {
      try {
        galleryTitle.value = Uri.decodeComponent(titleQ);
      } catch (_) {
        galleryTitle.value = titleQ;
      }
    }
  }

  String? originalImageUrlAt(int index) => _originalImageUrls[index];

  Future<void> _refreshEhLoggedInForOriginal() async {
    try {
      final h = await backendApiClient.health();
      ehLoggedInForOriginal.value = h['loggedIn'] == true;
    } catch (_) {
      ehLoggedInForOriginal.value = false;
    }
  }

  Future<void> _loadDisplayFirstPageAlone() async {
    try {
      final saved = await backendApiClient.getSetting('web_display_first_page_alone');
      if (saved == 'true') {
        displayFirstPageAlone.value = true;
      } else if (saved == 'false') {
        displayFirstPageAlone.value = false;
      }
    } catch (_) {}
  }

  int doubleColumnScreenIndexForImagePage(int page) {
    final t = totalPages.value;
    if (t <= 0) return 0;
    if (page < 0) return 0;
    if (page >= t) {
      final n = doubleColumnPageCount();
      return n <= 0 ? 0 : n - 1;
    }
    if (displayFirstPageAlone.value) {
      if (page == 0) return 0;
      return 1 + (page - 1) ~/ 2;
    }
    return page ~/ 2;
  }

  int doubleColumnPageCount() {
    final t = totalPages.value;
    if (t <= 0) return 0;
    if (displayFirstPageAlone.value) {
      return 1 + ((t - 1) / 2).ceil();
    }
    return (t / 2).ceil();
  }

  List<int> doubleColumnIndicesForScreen(int screenIndex) {
    final t = totalPages.value;
    if (displayFirstPageAlone.value) {
      if (screenIndex == 0) return [0];
      final left = 1 + (screenIndex - 1) * 2;
      if (left >= t) return [];
      final right = left + 1;
      if (right < t) {
        return [left, right];
      }
      return [left];
    }
    final left = screenIndex * 2;
    if (left >= t) return [];
    final right = left + 1;
    if (right < t) {
      return [left, right];
    }
    return [left];
  }

  void toggleDisplayFirstPageAlone() {
    if (readDirection.value != ReadDirection.doubleColumn) return;
    displayFirstPageAlone.value = !displayFirstPageAlone.value;
    backendApiClient
        .putSetting('web_display_first_page_alone', displayFirstPageAlone.value)
        .catchError((_) {});
    final screen = doubleColumnScreenIndexForImagePage(currentPage.value);
    pageController.dispose();
    pageController = PageController(initialPage: screen);
  }

  Future<void> _loadSavedDirection() async {
    try {
      final saved = await backendApiClient.getSetting('web_read_direction');
      if (saved != null) {
        final idx = int.tryParse(saved);
        if (idx != null && idx >= 0 && idx < ReadDirection.values.length) {
          readDirection.value = ReadDirection.values[idx];
        }
      }
    } catch (_) {}
  }

  Future<void> _loadWheelAction() async {
    try {
      final raw = await backendApiClient.getSetting(kWebReaderWheelActionKey);
      wheelAction.value = webReaderWheelActionFromStorage(raw);
      final inv = await backendApiClient.getSetting(kWebReaderWheelInvertPageKey);
      wheelInvertPageTurn.value = webReaderWheelInvertPageFromStorage(inv);
    } catch (_) {}
  }

  Future<void> _restoreProgress() async {
    if (_startPage != null && _startPage! >= 0) {
      currentPage.value = _startPage!;
      _initPageController(_startPage!);
      return;
    }
    if (gid == 0) return;
    try {
      final saved = await backendApiClient.getSetting('read_progress_$gid');
      if (saved != null) {
        final page = int.tryParse(saved) ?? 0;
        if (page > 0 && page < totalPages.value) {
          currentPage.value = page;
          _initPageController(page);
        }
      }
    } catch (_) {}
  }

  void _initPageController(int page) {
    final dir = readDirection.value;
    if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
      return;
    }
    if (dir == ReadDirection.doubleColumn) {
      pageController = PageController(initialPage: doubleColumnScreenIndexForImagePage(page));
    } else {
      pageController = PageController(initialPage: page);
    }
  }

  void _scheduleSaveProgress() {
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer(const Duration(seconds: 2), _saveProgressNow);
  }

  void _saveProgressNow() {
    if (gid == 0) return;
    backendApiClient.putSetting('read_progress_$gid', currentPage.value).catchError((_) {});
  }

  Future<void> _loadGallery() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      switch (mode) {
        case ReaderMode.online:
          await _loadOnline();
          break;
        case ReaderMode.downloaded:
          await _loadDownloaded();
          break;
        case ReaderMode.archive:
          await _loadArchive();
          break;
        case ReaderMode.local:
          _loadLocal();
          break;
      }
      await _restoreProgress();
      if (mode == ReaderMode.online) {
        _preloadAround(currentPage.value);
      }
    } catch (e) {
      errorMessage.value = 'reader.loadFailed'.trParams({'error': '$e'});
    } finally {
      isLoading.value = false;
      // Strip mounts only after loading; align once if progress was restored earlier.
      _scheduleScrollThumbnailStripToCurrent();
    }
  }

  Future<void> _loadOnline() async {
    _imagePageReloadKeys.clear();
    _originalImageUrls.clear();
    imageLoadErrors.clear();
    final result = await backendApiClient.fetchGalleryImagePages(gid, token);
    final pages = (result['imagePageUrls'] as List?)?.cast<String>() ?? [];
    final total = result['totalPages'] as int? ?? pages.length;
    _imagePageUrls.clear();
    _imagePageUrls.addAll(pages);
    totalPages.value = total;
    imageUrls.value = List.filled(_imagePageUrls.length, '');
    final gt = result['galleryThumbnails'] as List?;
    if (gt != null) {
      galleryThumbnails.value = gt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      galleryThumbnails.value = [];
    }
    _preloadAround(0);
    imageUrls.refresh();
  }

  Future<void> _loadDownloaded() async {
    final filenames = await backendApiClient.getGalleryDownloadImages(gid);
    totalPages.value = filenames.length;
    imageUrls.value = filenames
        .map((f) => backendApiClient.galleryImageUrl(gid, f))
        .toList();
  }

  Future<void> _loadArchive() async {
    final filenames = await backendApiClient.getArchiveDownloadImages(gid);
    totalPages.value = filenames.length;
    imageUrls.value = filenames
        .map((f) => backendApiClient.archiveImageUrl(gid, f))
        .toList();
  }

  void _loadLocal() {
    if (localImages == null || localImages!.isEmpty) {
      errorMessage.value = 'reader.noImages'.tr;
      return;
    }
    totalPages.value = localImages!.length;
    imageUrls.value = localImages!
        .map((path) => backendApiClient.imageFileUrl(path))
        .toList();
  }

  /// Online preload window: similar spirit to read_setting.preloadPageCount / preloadDistance
  /// (native reader), but fixed for web so EH pages resolve ahead of the visible page.
  static const int _preloadBehindPages = 2;
  static const int _preloadAheadPages = 12;

  void _preloadAround(int center) {
    if (mode != ReaderMode.online) return;
    if (_imagePageUrls.isEmpty) return;
    final start = math.max(0, center - _preloadBehindPages);
    final end = math.min(_imagePageUrls.length - 1, center + _preloadAheadPages);
    for (int i = start; i <= end; i++) {
      if (!_loadedImageUrls.containsKey(i)) {
        _loadImageAtIndex(i);
      }
    }
  }

  Future<void> _loadImageAtIndex(int index, {String? nl}) async {
    if (index < 0 || index >= _imagePageUrls.length) return;
    if (_loadedImageUrls.containsKey(index)) return;
    if (resolvingImageIndexes.contains(index)) return;

    final gen = ++_resolveGeneration;
    _activeResolveGeneration[index] = gen;
    resolvingImageIndexes.add(index);
    try {
      await _resolveImagePageOnce(index, nl: nl);
    } catch (e, st) {
      debugPrint('Failed to load image $index: $e\n$st');
      if (_activeResolveGeneration[index] == gen) {
        imageLoadErrors[index] = 'reader.imageFailed'.tr;
        imageLoadErrors.refresh();
      }
    } finally {
      if (_activeResolveGeneration[index] == gen) {
        _activeResolveGeneration.remove(index);
        resolvingImageIndexes.remove(index);
      }
    }
  }

  static String _unescImgSrc(String s) => s.replaceAll('&amp;', '&').trim();

  static String? _fallbackParseImgSrc(String html) {
    final doc = html_pkg.parse(html);
    final src = doc.querySelector('#img')?.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return _unescImgSrc(src);
  }

  static String? _fallbackParseReloadKey(String html) {
    final doc = html_pkg.parse(html);
    final loadfail = doc.querySelector('#loadfail');
    final oc = loadfail?.attributes['onclick'];
    if (oc == null || oc.isEmpty) return null;
    final m = RegExp(r"return nl\('(.*)'\)").firstMatch(oc);
    return m?.group(1);
  }

  /// Fetches one image page (optional EH `nl`) and updates [imageUrls] / errors. No resolving wrapper.
  Future<void> _resolveImagePageOnce(int index, {String? nl, int depth = 0}) async {
    imageLoadErrors.remove(index);

    final result = await backendApiClient.proxyGet(
      url: _imagePageUrls[index],
      queryParameters: nl != null && nl.isNotEmpty ? {'nl': nl} : null,
    );
    final html = (result as Map<String, dynamic>)['data']?.toString() ?? '';

    WebParsedOnlineImagePage? wp;
    try {
      wp = webParseOnlineImagePage(html);
    } on EHParseException catch (e) {
      if (e.type == EHParseExceptionType.exceedLimit) {
        final rk = _fallbackParseReloadKey(html);
        if (rk != null && rk.isNotEmpty && depth < 1 && nl != rk) {
          await _resolveImagePageOnce(index, nl: rk, depth: depth + 1);
          return;
        }
        imageLoadErrors[index] = e.message;
        imageLoadErrors.refresh();
        return;
      }
      if (e.type == EHParseExceptionType.unsupportedImagePageStyle) {
        imageLoadErrors[index] = e.message;
        imageLoadErrors.refresh();
        return;
      }
      wp = null;
    }

    String? imageUrl;
    String? reloadKey;
    if (wp != null) {
      imageUrl = _unescImgSrc(wp.url);
      reloadKey = wp.reloadKey;
    } else {
      imageUrl = _fallbackParseImgSrc(html);
      reloadKey = _fallbackParseReloadKey(html);
    }

    if (imageUrl == EHConsts.EH509ImageUrl || imageUrl == EHConsts.EX509ImageUrl) {
      final rk = reloadKey ?? _fallbackParseReloadKey(html);
      if (rk != null && rk.isNotEmpty && depth < 1 && nl != rk) {
        await _resolveImagePageOnce(index, nl: rk, depth: depth + 1);
        return;
      }
      imageLoadErrors[index] = 'exceedImageLimits'.tr;
      imageLoadErrors.refresh();
      return;
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (reloadKey != null && reloadKey.isNotEmpty) {
        _imagePageReloadKeys[index] = reloadKey;
      }
      if (wp != null &&
          wp.originalImageUrl != null &&
          wp.originalImageUrl!.isNotEmpty) {
        _originalImageUrls[index] = wp.originalImageUrl!;
      } else {
        _originalImageUrls.remove(index);
      }
      _loadedImageUrls[index] = imageUrl;
      if (index < imageUrls.length) {
        imageUrls[index] = imageUrl;
        imageUrls.refresh();
      }
      if (!backendApiClient.shouldProxyImageUsePost(imageUrl)) {
        _precacheNetworkImage(backendApiClient.proxyImageUrl(imageUrl));
      }
    } else {
      imageLoadErrors[index] = 'reader.imageFailed'.tr;
      imageLoadErrors.refresh();
    }
  }

  void reloadCurrentImages() {
    if (readDirection.value == ReadDirection.doubleColumn) {
      final screen = doubleColumnScreenIndexForImagePage(currentPage.value);
      for (final i in doubleColumnIndicesForScreen(screen)) {
        if (i < totalPages.value) {
          retryImage(i);
        }
      }
    } else {
      retryImage(currentPage.value);
    }
  }

  void retryImage(int index) {
    if (mode == ReaderMode.online) {
      final nl = _imagePageReloadKeys[index];
      _activeResolveGeneration.remove(index);
      resolvingImageIndexes.remove(index);
      _loadedImageUrls.remove(index);
      _originalImageUrls.remove(index);
      imageLoadErrors.remove(index);
      imageUrls[index] = '';
      imageUrls.refresh();
      _loadImageAtIndex(index, nl: nl);
    }
  }

  void onPageChanged(int page) {
    if (readDirection.value == ReadDirection.doubleColumn) {
      final idxs = doubleColumnIndicesForScreen(page);
      if (idxs.isEmpty) return;
      currentPage.value = idxs.first.clamp(0, math.max(0, totalPages.value - 1));
    } else {
      currentPage.value = page;
    }
    if (mode == ReaderMode.online) {
      _preloadAround(currentPage.value);
    }
    _scheduleSaveProgress();
  }

  void goToPage(int page) {
    if (page < 0 || page >= totalPages.value) return;
    final dir = readDirection.value;
    if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
      return;
    }
    if (dir == ReadDirection.doubleColumn) {
      pageController.animateToPage(doubleColumnScreenIndexForImagePage(page),
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      pageController.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void nextPage() {
    final dir = readDirection.value;
    if (dir == ReadDirection.doubleColumn) {
      final p = currentPage.value;
      final maxP = totalPages.value - 1;
      if (displayFirstPageAlone.value && p == 0) {
        goToPage(1.clamp(0, maxP));
        return;
      }
      goToPage((p + 2).clamp(0, maxP));
    } else {
      goToPage(currentPage.value + 1);
    }
  }

  void prevPage() {
    final dir = readDirection.value;
    if (dir == ReadDirection.doubleColumn) {
      final p = currentPage.value;
      if (displayFirstPageAlone.value && p == 1) {
        goToPage(0);
        return;
      }
      if (p >= 2) {
        goToPage(p - 2);
        return;
      }
    }
    goToPage(currentPage.value - 1);
  }

  void toggleOverlay() => showOverlay.value = !showOverlay.value;

  void setReadDirection(ReadDirection newDir) {
    final prev = readDirection.value;
    if (prev == newDir) return;
    readDirection.value = newDir;
    backendApiClient.putSetting('web_read_direction', newDir.index).catchError((_) {});
    if (newDir != ReadDirection.vertical && newDir != ReadDirection.fitWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentPage.value < totalPages.value) {
          pageController.dispose();
          if (newDir == ReadDirection.doubleColumn) {
            pageController = PageController(
                initialPage: doubleColumnScreenIndexForImagePage(currentPage.value));
          } else {
            pageController = PageController(initialPage: currentPage.value);
          }
        }
      });
    }
  }

  void showDeviceOrientationHint() {
    Get.snackbar(
      'reader.deviceOrientation'.tr,
      'reader.deviceOrientationWebHint'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
    );
  }

  void toggleAutoMode() {
    if (isAutoMode.value) {
      isAutoMode.value = false;
      _autoTimer?.cancel();
      return;
    }
    _showAutoIntervalDialog();
  }

  void _showAutoIntervalDialog() {
    double selectedInterval = autoInterval.value;
    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Auto Mode Interval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${selectedInterval.toStringAsFixed(1)}s'),
              Slider(
                value: selectedInterval,
                min: 2,
                max: 15,
                divisions: 26,
                label: '${selectedInterval.toStringAsFixed(1)}s',
                onChanged: (v) => setState(() => selectedInterval = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Get.back();
                autoInterval.value = selectedInterval;
                isAutoMode.value = true;
                _startAutoTimer();
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  void setAutoInterval(double seconds) {
    autoInterval.value = seconds;
    if (isAutoMode.value) {
      _autoTimer?.cancel();
      _startAutoTimer();
    }
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(Duration(milliseconds: (autoInterval.value * 1000).round()), (_) {
      final dir = readDirection.value;
      if (dir == ReadDirection.vertical || dir == ReadDirection.fitWidth) {
        if (scrollController.hasClients) {
          final target = scrollController.offset + 600;
          if (target >= scrollController.position.maxScrollExtent) {
            isAutoMode.value = false;
            _autoTimer?.cancel();
            return;
          }
          scrollController.animateTo(target,
              duration: Duration(milliseconds: (autoInterval.value * 800).round()),
              curve: Curves.linear);
        }
      } else {
        if (currentPage.value >= totalPages.value - 1) {
          isAutoMode.value = false;
          _autoTimer?.cancel();
          return;
        }
        nextPage();
      }
    });
  }

  Future<void> retry() => _loadGallery();
}

class WebReaderPage extends StatelessWidget {
  const WebReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WebReaderController>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text('reader.loading'.tr, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          );
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(controller.errorMessage.value,
                    style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: controller.retry, child: Text('common.retry'.tr)),
              ],
            ),
          );
        }
        return _ReaderBody(controller: controller);
      }),
    );
  }
}

class _ReaderBody extends StatelessWidget {
  final WebReaderController controller;
  const _ReaderBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: controller.focusNode..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space) {
            controller.nextPage();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            controller.prevPage();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _popOrExitWebReader(context, controller);
          }
        }
      },
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: controller.toggleOverlay,
            child: Obx(() {
              final dir = controller.readDirection.value;
              // Rebuild double-column [PageView] when [displayFirstPageAlone] toggles.
              controller.displayFirstPageAlone.value;
              return switch (dir) {
                ReadDirection.vertical => _buildVerticalReader(context),
                ReadDirection.fitWidth => _buildFitWidthReader(context),
                ReadDirection.doubleColumn => _buildDoubleColumnReader(context),
                _ => _buildPageReader(context),
              };
            }),
          ),
          _TopOverlay(controller: controller),
          _BottomOverlay(controller: controller),
          Positioned(
            right: 16,
            bottom: 16,
            child: Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${controller.currentPage.value + 1} / ${controller.totalPages.value}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildPageReader(BuildContext context) {
    return Obx(() => ScrollConfiguration(
          behavior: _webReaderScrollBehavior,
          child: PageView.builder(
            controller: controller.pageController,
            reverse: controller.readDirection.value == ReadDirection.rtl,
            itemCount: controller.totalPages.value,
            onPageChanged: controller.onPageChanged,
            allowImplicitScrolling: true,
            padEnds: false,
            itemBuilder: (context, index) => _DoubleTapZoomImage(controller: controller, index: index),
          ),
        ));
  }

  Widget _buildVerticalReader(BuildContext context) {
    return Obx(() => NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0) {
            final page = (metrics.pixels / metrics.maxScrollExtent * (controller.totalPages.value - 1)).round();
            if (page != controller.currentPage.value) {
              controller.currentPage.value = page;
              if (controller.mode == ReaderMode.online) {
                controller._preloadAround(page);
              }
            }
          }
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: _webReaderScrollBehavior,
        child: ListView.builder(
          controller: controller.scrollController,
          itemCount: controller.totalPages.value,
          cacheExtent: math.max(1200, MediaQuery.sizeOf(context).height * 2),
          itemBuilder: (context, index) => _ImagePage(controller: controller, index: index, isVertical: true),
        ),
      ),
    ));
  }

  Widget _buildFitWidthReader(BuildContext context) {
    return Obx(() => NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0) {
            final page = (metrics.pixels / metrics.maxScrollExtent * (controller.totalPages.value - 1)).round();
            if (page != controller.currentPage.value) {
              controller.currentPage.value = page;
              if (controller.mode == ReaderMode.online) {
                controller._preloadAround(page);
              }
            }
          }
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: _webReaderScrollBehavior,
        child: ListView.builder(
          controller: controller.scrollController,
          itemCount: controller.totalPages.value,
          cacheExtent: math.max(1200, MediaQuery.sizeOf(context).height * 2),
          itemBuilder: (context, index) => _ImagePage(controller: controller, index: index, isVertical: true, fitWidth: true),
        ),
      ),
    ));
  }

  Widget _buildDoubleColumnReader(BuildContext context) {
    return Obx(() {
      final total = controller.totalPages.value;
      final pageCount = controller.doubleColumnPageCount();
      return ScrollConfiguration(
        behavior: _webReaderScrollBehavior,
        child: PageView.builder(
          controller: controller.pageController,
          itemCount: pageCount,
          onPageChanged: controller.onPageChanged,
          allowImplicitScrolling: true,
          padEnds: false,
          itemBuilder: (context, screenIndex) {
            final idxs = controller.doubleColumnIndicesForScreen(screenIndex);
            if (idxs.isEmpty) {
              return const SizedBox.shrink();
            }
            if (idxs.length == 1) {
              return Row(
                children: [
                  Expanded(
                    child: _DoubleTapZoomImage(
                      controller: controller,
                      index: idxs[0],
                    ),
                  ),
                  const Expanded(child: SizedBox.shrink()),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: _DoubleTapZoomImage(
                    controller: controller,
                    index: idxs[0],
                  ),
                ),
                Expanded(
                  child: _DoubleTapZoomImage(
                    controller: controller,
                    index: idxs[1],
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }
}

class _DoubleTapZoomImage extends StatefulWidget {
  final WebReaderController controller;
  final int index;
  const _DoubleTapZoomImage({required this.controller, required this.index});

  @override
  State<_DoubleTapZoomImage> createState() => _DoubleTapZoomImageState();
}

class _DoubleTapZoomImageState extends State<_DoubleTapZoomImage> with SingleTickerProviderStateMixin {
  final _transformationController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;
  /// When false, [InteractiveViewer] does not pan so mouse drags reach the parent [PageView].
  bool _pannable = false;
  DateTime? _lastWheelPageTurnAt;
  static const _wheelPageTurnCooldown = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        if (_animation != null) _transformationController.value = _animation!.value;
      });
  }

  void _onTransformChanged() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _pannable) {
      setState(() => _pannable = zoomed);
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _animController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final pos = _doubleTapDetails?.localPosition ?? Offset.zero;
    if (_transformationController.value.isIdentity()) {
      final end = Matrix4.identity()
        ..translate(-pos.dx, -pos.dy)
        ..scale(2.0)
        ..translate(pos.dx, pos.dy);
      _animation = Matrix4Tween(begin: _transformationController.value, end: end).animate(_animController);
      _animController.forward(from: 0);
    } else {
      _animation = Matrix4Tween(begin: _transformationController.value, end: Matrix4.identity()).animate(_animController);
      _animController.forward(from: 0);
    }
  }

  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;

  void _applyWheelPageTurn(PointerScrollEvent e) {
    final now = DateTime.now();
    if (_lastWheelPageTurnAt != null &&
        now.difference(_lastWheelPageTurnAt!) < _wheelPageTurnCooldown) {
      return;
    }

    final dx = e.scrollDelta.dx;
    final dy = e.scrollDelta.dy;
    var delta = dx.abs() >= dy.abs() ? dx : dy;
    if (widget.controller.wheelInvertPageTurn.value) {
      delta = -delta;
    }
    if (delta.abs() < 0.25) return;

    _lastWheelPageTurnAt = now;
    if (delta > 0) {
      widget.controller.nextPage();
    } else {
      widget.controller.prevPage();
    }
  }

  void _applyWheelZoom(PointerScrollEvent e) {
    final delta = e.scrollDelta.dy + e.scrollDelta.dx;
    if (delta.abs() < 0.25) return;
    final m = _transformationController.value.clone();
    final s = m.getMaxScaleOnAxis();
    final factor = math.exp(-delta * 0.002);
    final sNew = (s * factor).clamp(_minScale, _maxScale);
    if ((sNew - s).abs() < 1e-6) return;
    final scaleBy = sNew / s;
    final focal = e.localPosition;
    final inner = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(scaleBy)
      ..translate(-focal.dx, -focal.dy);
    _transformationController.value = m * inner;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dir = widget.controller.readDirection.value;
      final zoomWheel = widget.controller.wheelAction.value == WebReaderWheelAction.zoom &&
          dir != ReadDirection.vertical &&
          dir != ReadDirection.fitWidth;

      final viewer = GestureDetector(
        onDoubleTapDown: (d) => _doubleTapDetails = d,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          panEnabled: _pannable,
          scaleEnabled: zoomWheel || _pannable,
          trackpadScrollCausesScale: zoomWheel,
          minScale: _minScale,
          maxScale: _maxScale,
          child: Center(child: _ImageContent(controller: widget.controller, index: widget.index)),
        ),
      );

      /// Web: [InteractiveViewer] still scales on wheel when [trackpadScrollCausesScale] is ignored
      /// or mis-detected; claim [PointerScrollEvent] so [PageView] / our handler wins.
      if (zoomWheel) {
        return Listener(
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            GestureBinding.instance.pointerSignalResolver.register(signal, (PointerSignalEvent e) {
              if (e is PointerScrollEvent) _applyWheelZoom(e);
            });
          },
          child: viewer,
        );
      }

      return Listener(
        onPointerSignal: (signal) {
          if (signal is! PointerScrollEvent) return;
          if (_transformationController.value.getMaxScaleOnAxis() > 1.02) return;
          GestureBinding.instance.pointerSignalResolver.register(signal, (PointerSignalEvent e) {
            if (e is PointerScrollEvent) _applyWheelPageTurn(e);
          });
        },
        child: viewer,
      );
    });
  }
}

/// Image-page parse / proxy failure (online reader).
Widget _webReaderImageErrorShell(
  BuildContext context, {
  required int pageIndex,
  required String message,
  required VoidCallback onRetry,
  required bool isVertical,
  required bool fitWidth,
}) {
  final sh = MediaQuery.sizeOf(context);
  final h = isVertical || fitWidth ? sh.height * 0.85 : sh.height * 0.72;
  return SizedBox(
    width: double.infinity,
    height: h,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, color: Colors.white54, size: 48),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          Text('${pageIndex + 1}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text('common.retry'.tr)),
        ],
      ),
    ),
  );
}

/// Full-viewport-style loading shell for web reader (HTML resolve or network decode).
Widget _webReaderImageLoadingShell(
  BuildContext context, {
  required int pageIndex,
  required bool isVertical,
  required bool fitWidth,
}) {
  final sh = MediaQuery.sizeOf(context);
  final h = isVertical || fitWidth ? sh.height * 0.85 : sh.height * 0.72;
  return SizedBox(
    width: double.infinity,
    height: h,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white54),
          const SizedBox(height: 12),
          Text('reader.loadingImage'.tr, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          Text('${pageIndex + 1}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    ),
  );
}

class _ImagePage extends StatelessWidget {
  final WebReaderController controller;
  final int index;
  final bool isVertical;
  final bool fitWidth;

  const _ImagePage({required this.controller, required this.index, this.isVertical = false, this.fitWidth = false});

  @override
  Widget build(BuildContext context) {
    return _ImageContent(controller: controller, index: index, isVertical: isVertical, fitWidth: fitWidth);
  }
}

class _ImageContent extends StatelessWidget {
  final WebReaderController controller;
  final int index;
  final bool isVertical;
  final bool fitWidth;

  const _ImageContent({required this.controller, required this.index, this.isVertical = false, this.fitWidth = false});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final url = index < controller.imageUrls.length ? controller.imageUrls[index] : '';
      controller.resolvingImageIndexes.contains(index);
      final parseErr = controller.imageLoadErrors[index];
      if (url.isEmpty &&
          parseErr != null &&
          parseErr.isNotEmpty &&
          controller.mode == ReaderMode.online) {
        return _webReaderImageErrorShell(
          context,
          pageIndex: index,
          message: parseErr,
          onRetry: () => controller.retryImage(index),
          isVertical: isVertical,
          fitWidth: fitWidth,
        );
      }
      if (url.isEmpty) {
        return _webReaderImageLoadingShell(
          context,
          pageIndex: index,
          isVertical: isVertical,
          fitWidth: fitWidth,
        );
      }

      return GestureDetector(
        onLongPress: () => showWebReaderImageContextMenu(context, controller, index),
        onSecondaryTapUp: (details) => showWebReaderImageContextMenu(
          context,
          controller,
          index,
          position: details.globalPosition,
        ),
        child: WebProxiedImage(
          sourceUrl: url,
          fit: (isVertical || fitWidth) ? BoxFit.fitWidth : BoxFit.contain,
          width: (isVertical || fitWidth) ? double.infinity : null,
          readerStyle: true,
          readerTallLoading: isVertical || fitWidth,
          readerFillMinLoadingHeight: !isVertical && !fitWidth,
          readerErrorChild: SizedBox(
            height: isVertical ? 400 : null,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  const SizedBox(height: 8),
                  Text('reader.imageFailed'.tr, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => controller.retryImage(index),
                    child: Text('common.retry'.tr),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

IconData _webReadDirectionIcon(ReadDirection d) => switch (d) {
      ReadDirection.ltr => Icons.arrow_forward,
      ReadDirection.rtl => Icons.arrow_back,
      ReadDirection.vertical => Icons.swap_vert,
      ReadDirection.fitWidth => Icons.fit_screen,
      ReadDirection.doubleColumn => Icons.view_column,
    };

String _webReadDirectionLabel(ReadDirection d) => switch (d) {
      ReadDirection.ltr => 'reader.ltr'.tr,
      ReadDirection.rtl => 'reader.rtl'.tr,
      ReadDirection.vertical => 'reader.vertical'.tr,
      ReadDirection.fitWidth => 'reader.fitWidth'.tr,
      ReadDirection.doubleColumn => 'reader.doubleColumn'.tr,
    };

class _TopOverlay extends StatelessWidget {
  final WebReaderController controller;
  const _TopOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    final barHeight = kToolbarHeight + MediaQuery.of(context).padding.top;
    return Obx(() {
      final show = controller.showOverlay.value;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                child: Container(
                  height: barHeight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !show,
              child: Visibility(
                visible: show,
                maintainState: true,
                maintainAnimation: true,
                child: SizedBox(
                  height: barHeight,
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => _popOrExitWebReader(context, controller),
                        ),
                        Expanded(
                          child: Obx(() {
                            final title = controller.galleryTitle.value.trim();
                            final pageStr =
                                '${controller.currentPage.value + 1} / ${controller.totalPages.value}';
                            final text = title.isEmpty
                                ? (controller.gid != 0 ? '$pageStr · gid:${controller.gid}' : pageStr)
                                : '$title · $pageStr';
                            return Text(
                              text,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                        ),
                        Obx(() => IconButton(
                              icon: Icon(
                                controller.isAutoMode.value ? Icons.pause_circle : Icons.play_circle,
                                color: controller.isAutoMode.value ? Colors.amber : Colors.white,
                              ),
                              tooltip: controller.isAutoMode.value ? 'reader.autoStop'.tr : 'reader.autoStart'.tr,
                              onPressed: controller.toggleAutoMode,
                            )),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          tooltip: 'reader.reloadImage'.tr,
                          onPressed: controller.reloadCurrentImages,
                        ),
                        IconButton(
                          icon: const Icon(Icons.grid_view, color: Colors.white),
                          tooltip: 'thumbnails.grid'.tr,
                          onPressed: () => Get.toNamed(
                              '/web/thumbnails/${controller.gid}/${controller.token}'),
                        ),
                        Obx(() {
                          if (controller.readDirection.value != ReadDirection.doubleColumn) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: Icon(
                              Icons.filter_1,
                              color: controller.displayFirstPageAlone.value ? Colors.amber : Colors.white,
                            ),
                            tooltip: 'displayFirstPageAlone'.tr,
                            onPressed: controller.toggleDisplayFirstPageAlone,
                          );
                        }),
                        IconButton(
                          icon: const Icon(Icons.screen_rotation_outlined, color: Colors.white),
                          tooltip: 'reader.deviceOrientation'.tr,
                          onPressed: controller.showDeviceOrientationHint,
                        ),
                        Obx(() {
                          final d = controller.readDirection.value;
                          return PopupMenuButton<ReadDirection>(
                            icon: Icon(_webReadDirectionIcon(d), color: Colors.white),
                            tooltip: 'reader.directionLabel'.trParams({'dir': _webReadDirectionLabel(d)}),
                            color: Colors.grey.shade900,
                            onSelected: controller.setReadDirection,
                            itemBuilder: (context) => [
                              for (final e in ReadDirection.values)
                                PopupMenuItem(
                                  value: e,
                                  child: Row(
                                    children: [
                                      Icon(_webReadDirectionIcon(e), size: 20),
                                      const SizedBox(width: 12),
                                      Text(_webReadDirectionLabel(e)),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        }),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          tooltip: 'settings.readerSettings'.tr,
                          onPressed: () => Get.toNamed('/web/settings/read'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

Widget _readerStripThumb(WebReaderController controller, int pageIndex, String proxiedFullImageUrl) {
  if (pageIndex < controller.galleryThumbnails.length) {
    final m = controller.galleryThumbnails[pageIndex];
    final u = m['thumbUrl'] as String? ?? '';
    if (u.isNotEmpty) {
      return WebEhThumbnail(
        data: Map<String, dynamic>.from(m),
        height: 40,
        width: 40,
        borderRadius: BorderRadius.circular(3),
      );
    }
  }
  if (proxiedFullImageUrl.isNotEmpty) {
    return WebProxiedImage(
      sourceUrl: proxiedFullImageUrl,
      fit: BoxFit.cover,
      width: 40,
      height: 40,
      errorIconSize: 16,
      readerErrorChild: const Icon(Icons.image, color: Colors.white24, size: 16),
    );
  }
  return const Center(child: Icon(Icons.image, color: Colors.white24, size: 16));
}

class _BottomOverlay extends StatelessWidget {
  final WebReaderController controller;
  const _BottomOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    // AnimatedPositioned must be a direct Stack child; wrapping it outside IgnorePointer broke layout.
    return Obx(() => AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: controller.showOverlay.value ? 0 : -140,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controller.showOverlay.value,
        child: Container(
          padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 8, top: 8,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Obx(() => controller.totalPages.value > 1
                ? Slider(
                    value: controller.currentPage.value.toDouble().clamp(0, (controller.totalPages.value - 1).toDouble()),
                    min: 0,
                    max: (controller.totalPages.value - 1).toDouble(),
                    divisions: controller.totalPages.value > 1 ? controller.totalPages.value - 1 : 1,
                    label: '${controller.currentPage.value + 1}',
                    onChanged: (v) => controller.goToPage(v.round()),
                  )
                : const SizedBox.shrink()),
            Obx(() {
              if (!controller.isAutoMode.value) return const SizedBox.shrink();
              return Row(
                children: [
                  const Icon(Icons.timer, color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text('${controller.autoInterval.value.toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: controller.autoInterval.value,
                      min: 2, max: 15, divisions: 26,
                      onChanged: controller.setAutoInterval,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                ],
              );
            }),
            _buildThumbnailStrip(),
          ],
        ),
      ),
    ),
    ));
  }

  Widget _buildThumbnailStrip() {
    return Obx(() {
      if (controller.totalPages.value <= 1) return const SizedBox.shrink();
      final total = controller.totalPages.value;

      return SizedBox(
        height: 52,
        child: Listener(
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            final c = controller.stripScrollController;
            if (!c.hasClients) return;
            final delta = signal.scrollDelta.dy;
            final max = c.position.maxScrollExtent;
            c.jumpTo((c.offset + delta).clamp(0.0, max));
          },
          child: ScrollConfiguration(
            behavior: _webReaderScrollBehavior,
            child: ListView.builder(
              controller: controller.stripScrollController,
              scrollDirection: Axis.horizontal,
              itemExtent: _kWebReaderStripItemExtent,
              itemCount: total,
              itemBuilder: (context, pageIndex) {
                final url = pageIndex < controller.imageUrls.length
                    ? controller.imageUrls[pageIndex]
                    : '';
                final isActive = controller.currentPage.value == pageIndex;

                return GestureDetector(
                  onTap: () => controller.goToPage(pageIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isActive ? Colors.white : Colors.white24,
                          width: isActive ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: _readerStripThumb(controller, pageIndex, url),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}
