import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

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

  @override
  State<WebEhThumbnail> createState() => _WebEhThumbnailState();
}

class _WebEhThumbnailState extends State<WebEhThumbnail> {
  ui.Image? _image;
  String? _loadError;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  String? _resolvedUrl;

  @override
  void dispose() {
    _cancelStream();
    super.dispose();
  }

  void _cancelStream() {
    if (_imageStream != null && _listener != null) {
      _imageStream!.removeListener(_listener!);
    }
    _imageStream = null;
    _listener = null;
  }

  void _resolveImage(String proxyUrl) {
    if (_resolvedUrl == proxyUrl && _image != null) {
      return;
    }
    _cancelStream();
    _resolvedUrl = proxyUrl;
    _image = null;
    _loadError = null;

    final provider = NetworkImage(proxyUrl);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _imageStream = stream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!mounted) {
          return;
        }
        setState(() {
          _image = info.image;
          _loadError = null;
        });
      },
      onError: (Object e, StackTrace? _) {
        if (!mounted) {
          return;
        }
        setState(() {
          _image = null;
          _loadError = '$e';
        });
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
    if (thumbUrl.isEmpty) {
      return;
    }
    _resolveImage(backendApiClient.proxyImageUrl(thumbUrl));
  }

  @override
  void didUpdateWidget(WebEhThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldU = oldWidget.data['thumbUrl'] as String? ?? '';
    final newU = widget.data['thumbUrl'] as String? ?? '';
    if (oldU != newU) {
      final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
      if (thumbUrl.isEmpty) {
        _cancelStream();
        setState(() {
          _image = null;
          _resolvedUrl = null;
        });
      } else {
        _resolveImage(backendApiClient.proxyImageUrl(thumbUrl));
      }
    }
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
    final thumbUrl = widget.data['thumbUrl'] as String? ?? '';
    if (thumbUrl.isEmpty) {
      final s = (widget.height ?? widget.width ?? 28).clamp(16.0, 56.0);
      return Icon(Icons.image, color: Colors.grey.shade600, size: s);
    }

    final proxy = backendApiClient.proxyImageUrl(thumbUrl);
    final large = WebEhThumbnail._isLarge(widget.data);
    final off = WebEhThumbnail._num(widget.data, 'offSet');
    final tw = WebEhThumbnail._num(widget.data, 'thumbWidth');
    final th = WebEhThumbnail._num(widget.data, 'thumbHeight');
    final useSprite = !large && off != null && tw != null && tw > 0 && th != null && th > 0;

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
              child: Image.network(
                proxy,
                fit: BoxFit.cover,
                width: cw,
                height: ch,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.broken_image, color: Colors.grey.shade600, size: math.min(28, math.min(cw, ch))),
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
        final o = off;
        final twn = tw;
        final thn = th;
        final src = Rect.fromLTRB(o, 0, o + twn, thn);

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
