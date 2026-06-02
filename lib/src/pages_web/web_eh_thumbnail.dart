import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';
import 'package:jhentai/src/pages_web/web_proxied_image.dart';

/// Web counterpart to [EHThumbnail]: large = single image URL; small = sprite strip + cover into cell.
/// Uses canvas (not extended_image) so `flutter build web` works with current SDK.
class WebEhThumbnail extends StatefulWidget {
  final Map<String, dynamic> data;
  final double? height;
  final double? width;
  final BorderRadius borderRadius;

  const WebEhThumbnail({
    super.key,
    required this.data,
    this.height,
    this.width,
    this.borderRadius = BorderRadius.zero,
  });

  static double? _num(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) {
      return null;
    }
    if (v is num) {
      return v.toDouble();
    }
    return double.tryParse('$v');
  }

  static bool _isLarge(Map<String, dynamic> data) {
    final v = data['isLarge'];
    if (v == true) {
      return true;
    }
    if (v == false) {
      return false;
    }
    return data['offSet'] == null;
  }

  static bool useSpriteSheet(Map<String, dynamic> data) {
    if (_isLarge(data)) {
      return false;
    }
    final off = _num(data, 'offSet');
    final tw = _num(data, 'thumbWidth');
    final th = _num(data, 'thumbHeight');
    return off != null && tw != null && tw > 0 && th != null && th > 0;
  }

  /// Server sets when sprite offset is Y (e.g. `url(...) 0px -Npx`); default horizontal strip.
  static bool spriteCropY(Map<String, dynamic> data) =>
      data['spriteCropY'] == true;

  @override
  State<WebEhThumbnail> createState() => _WebEhThumbnailState();
}

class _WebEhThumbnailState extends State<WebEhThumbnail> {
  ui.Image? _image;
  String? _loadError;

  /// Source thumb URL (ehgt) we decoded for sprite mode.
  String? _resolvedSourceUrl;

  @override
  void dispose() {
    _releaseSpriteImage();
    super.dispose();
  }

  void _releaseSpriteImage() {
    final url = _resolvedSourceUrl;
    if (url != null) {
      _WebSpriteImageCache.release(url);
    }
    _image = null;
    _resolvedSourceUrl = null;
  }

  Future<void> _loadSpriteImage(String thumbUrl) async {
    if (_resolvedSourceUrl == thumbUrl &&
        _image != null &&
        _loadError == null) {
      return;
    }
    _releaseSpriteImage();
    _resolvedSourceUrl = thumbUrl;
    _loadError = null;

    if (!mounted) {
      return;
    }

    try {
      final image = await _WebSpriteImageCache.acquire(
        context,
        thumbUrl,
      );
      if (!mounted || _resolvedSourceUrl != thumbUrl) {
        _WebSpriteImageCache.release(thumbUrl);
        return;
      }
      setState(() {
        _image = image;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && _resolvedSourceUrl == thumbUrl) {
        _WebSpriteImageCache.release(thumbUrl);
        _resolvedSourceUrl = null;
        setState(() {
          _loadError = '$e';
          _image = null;
        });
      }
    }
  }

  bool get _noImageMode {
    if (Get.isRegistered<WebSettingsController>()) {
      return Get.find<WebSettingsController>().noImageMode.value;
    }
    return WebPreferenceSettings.noImageMode;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
    if (_noImageMode ||
        thumbUrl.isEmpty ||
        !WebEhThumbnail.useSpriteSheet(widget.data)) {
      return;
    }
    _loadSpriteImage(thumbUrl);
  }

  @override
  void didUpdateWidget(WebEhThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldU = oldWidget.data['thumbUrl'] as String? ?? '';
    final newU = widget.data['thumbUrl'] as String? ?? '';
    if (oldU == newU &&
        WebEhThumbnail.useSpriteSheet(widget.data) ==
            WebEhThumbnail.useSpriteSheet(oldWidget.data) &&
        WebEhThumbnail.spriteCropY(widget.data) ==
            WebEhThumbnail.spriteCropY(oldWidget.data)) {
      return;
    }
    final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
    if (_noImageMode ||
        thumbUrl.isEmpty ||
        !WebEhThumbnail.useSpriteSheet(widget.data)) {
      _releaseSpriteImage();
      setState(() {
        _loadError = null;
      });
      return;
    }
    _loadSpriteImage(thumbUrl);
  }

  double _cellW(BoxConstraints c, double? explicitW) {
    if (explicitW != null && explicitW.isFinite) {
      return explicitW;
    }
    if (c.maxWidth.isFinite) {
      return c.maxWidth;
    }
    return 100;
  }

  double _cellH(BoxConstraints c, double? explicitH) {
    if (explicitH != null && explicitH.isFinite) {
      return explicitH;
    }
    if (c.maxHeight.isFinite) {
      return c.maxHeight;
    }
    return 100;
  }

  @override
  Widget build(BuildContext context) {
    if (Get.isRegistered<WebSettingsController>()) {
      final controller = Get.find<WebSettingsController>();
      return Obx(() => _buildThumbnail(context, controller.noImageMode.value));
    }
    return _buildThumbnail(context, WebPreferenceSettings.noImageMode);
  }

  Widget _buildThumbnail(BuildContext context, bool noImageMode) {
    final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
    if (noImageMode) {
      final s = (widget.height ?? widget.width ?? 28).clamp(16.0, 56.0);
      return Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade600,
        size: s,
      );
    }
    if (thumbUrl.isEmpty) {
      final s = (widget.height ?? widget.width ?? 28).clamp(16.0, 56.0);
      return Icon(Icons.image, color: Colors.grey.shade600, size: s);
    }

    final off = WebEhThumbnail._num(widget.data, 'offSet');
    final tw = WebEhThumbnail._num(widget.data, 'thumbWidth');
    final th = WebEhThumbnail._num(widget.data, 'thumbHeight');
    final useSprite = WebEhThumbnail.useSpriteSheet(widget.data);
    if (useSprite &&
        _image == null &&
        _loadError == null &&
        _resolvedSourceUrl != thumbUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_noImageMode) {
          _loadSpriteImage(thumbUrl);
        }
      });
    }

    if (!useSprite) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cw = _cellW(constraints, widget.width);
          final ch = _cellH(constraints, widget.height);
          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: SizedBox(
              width: cw,
              height: ch,
              child: WebProxiedImage(
                sourceUrl: thumbUrl,
                fit: BoxFit.cover,
                width: cw,
                height: ch,
                errorIconSize: math.min(28, math.min(cw, ch)),
              ),
            ),
          );
        },
      );
    }

    if (_loadError != null) {
      return Icon(Icons.broken_image, color: Colors.grey.shade600, size: 24);
    }
    if (_image == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = _cellW(constraints, widget.width);
        final maxH = _cellH(constraints, widget.height);
        final o = off!;
        final twn = tw!;
        final thn = th!;
        final cropY = WebEhThumbnail.spriteCropY(widget.data);
        final src = cropY
            ? Rect.fromLTRB(0, o, twn, o + thn)
            : Rect.fromLTRB(o, 0, o + twn, thn);

        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: SizedBox(
            width: maxW,
            height: maxH,
            child: CustomPaint(
              painter: _SpriteThumbPainter(
                image: _image!,
                srcRect: src,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WebSpriteImageCacheEntry {
  _WebSpriteImageCacheEntry({required this.future, required this.owned});

  final Future<ui.Image> future;
  final bool owned;
  ui.Image? image;
  int refCount = 0;
  int lastUsed = DateTime.now().millisecondsSinceEpoch;
}

class _WebSpriteImageCache {
  static const int _maxEntries = 32;
  static final Map<String, _WebSpriteImageCacheEntry> _entries = {};

  static Future<ui.Image> acquire(BuildContext context, String thumbUrl) async {
    final entry = _entries.putIfAbsent(
      thumbUrl,
      () {
        final usePost = backendApiClient.shouldProxyImageUsePost(thumbUrl);
        late final _WebSpriteImageCacheEntry e;
        e = _WebSpriteImageCacheEntry(
          owned: usePost,
          future: usePost
              ? _loadPostSprite(thumbUrl)
              : _loadNetworkSprite(context, thumbUrl),
        );
        e.future.then((image) {
          e.image = image;
          _evictIdleEntries();
        }).catchError((_) {
          _entries.remove(thumbUrl);
        });
        return e;
      },
    );
    entry.refCount++;
    entry.lastUsed = DateTime.now().millisecondsSinceEpoch;
    try {
      return await entry.future;
    } catch (_) {
      entry.refCount = math.max(0, entry.refCount - 1);
      rethrow;
    }
  }

  static void release(String thumbUrl) {
    final entry = _entries[thumbUrl];
    if (entry == null) return;
    entry.refCount = math.max(0, entry.refCount - 1);
    entry.lastUsed = DateTime.now().millisecondsSinceEpoch;
    _evictIdleEntries();
  }

  static Future<ui.Image> _loadPostSprite(String thumbUrl) async {
    final bytes = await backendApiClient.fetchProxiedImageBytes(thumbUrl);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<ui.Image> _loadNetworkSprite(
    BuildContext context,
    String thumbUrl,
  ) {
    final completer = Completer<ui.Image>();
    final provider = NetworkImage(backendApiClient.proxyImageUrl(thumbUrl));
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (Object e, StackTrace? st) {
        stream.removeListener(listener);
        completer.completeError(e, st);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static void _evictIdleEntries() {
    if (_entries.length <= _maxEntries) return;
    final candidates = _entries.entries
        .where((entry) => entry.value.refCount <= 0)
        .toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final candidate in candidates) {
      if (_entries.length <= _maxEntries) break;
      final removed = _entries.remove(candidate.key);
      if (removed?.owned == true) {
        removed?.image?.dispose();
      }
    }
  }
}

/// Scales [srcRect] from the image to **cover** [size] (centered, clipped).
class _SpriteThumbPainter extends CustomPainter {
  _SpriteThumbPainter({required this.image, required this.srcRect});

  final ui.Image image;
  final Rect srcRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (srcRect.width <= 0 || srcRect.height <= 0) {
      return;
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final sx = size.width / srcRect.width;
    final sy = size.height / srcRect.height;
    final scale = math.max(sx, sy);
    final dw = srcRect.width * scale;
    final dh = srcRect.height * scale;
    final dx = (size.width - dw) / 2;
    final dy = (size.height - dh) / 2;
    final dst = Rect.fromLTWH(dx, dy, dw, dh);
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpriteThumbPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}
