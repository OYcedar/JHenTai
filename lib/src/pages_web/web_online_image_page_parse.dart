import 'package:get/get.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:jhentai/src/consts/eh_consts.dart';
import 'package:jhentai/src/exception/eh_parse_exception.dart';

/// Result of parsing an EH/EX `/s/...` image page HTML.
///
/// Web-only helper: avoids importing [EHSpiderParser], which pulls in sqlite/drift
/// and breaks `flutter build web`.
class WebParsedOnlineImagePage {
  final String url;
  final String? reloadKey;
  /// EH “Download original” link when present (mirrors native image-page parser).
  final String? originalImageUrl;

  WebParsedOnlineImagePage({
    required this.url,
    this.reloadKey,
    this.originalImageUrl,
  });
}

/// Mirrors [EHSpiderParser.imagePage2GalleryImage] for fields needed by the web reader.
WebParsedOnlineImagePage webParseOnlineImagePage(String html) {
  final Document document = parse(html);
  Element? img = document.querySelector('#img');
  if (img == null && document.querySelector('#pane_images') != null) {
    throw EHParseException(
      type: EHParseExceptionType.unsupportedImagePageStyle,
      message: 'unsupportedImagePageStyle'.tr,
    );
  }

  final style = img!.attributes['style']!;
  final url = img.attributes['src']!;
  if (url == EHConsts.EH509ImageUrl || url == EHConsts.EX509ImageUrl) {
    throw EHParseException(
      type: EHParseExceptionType.exceedLimit,
      message: 'exceedImageLimits'.tr,
    );
  }
  RegExpMatch? hm = RegExp(r'height:(\d+)px').firstMatch(style);
  RegExpMatch? wm = RegExp(r'width:(\d+)px').firstMatch(style);
  if (hm == null || wm == null) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }

  final hashElement = document.querySelector('#i6 div a');
  if (hashElement == null) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }
  final href = hashElement.attributes['href'];
  if (href == null) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }
  final hashMatch = RegExp(r'f_shash=(\w+)').firstMatch(href);
  if (hashMatch == null) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }

  final reloadKeyElement = document.querySelector('#loadfail');
  final onclick = reloadKeyElement?.attributes['onclick'];
  if (reloadKeyElement == null || onclick == null) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }
  final rk = RegExp(r"return nl\('(.*)'\)").firstMatch(onclick)?.group(1);
  if (rk == null || rk.isEmpty) {
    throw EHParseException(
      type: EHParseExceptionType.getMetaDataFailed,
      message: 'getMetaDataFailed'.tr,
      shouldPauseAllDownloadTasks: false,
    );
  }

  final originalImg = document
      .querySelector('#i6 a[id]')
      ?.parent
      ?.nextElementSibling
      ?.querySelector('a');
  final originalHref = originalImg?.attributes['href']?.trim();
  final originalUrl = (originalHref != null && originalHref.isNotEmpty)
      ? originalHref.replaceAll('&amp;', '&').trim()
      : null;

  return WebParsedOnlineImagePage(
    url: url,
    reloadKey: rk,
    originalImageUrl: originalUrl,
  );
}
