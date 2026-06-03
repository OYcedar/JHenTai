import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_image_client_log.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';
import 'package:web/web.dart' as web;

/// Loads an EH/EX CDN image through the API proxy. Uses POST with body when the GET URL would be too long
/// for reverse proxies (Unraid + Nginx, etc.).
class WebProxiedImage extends StatefulWidget {
  const WebProxiedImage({
    super.key,
    required this.sourceUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.errorIconSize = 28,
    this.readerStyle = false,
    this.readerTallLoading = false,

    /// Horizontal reader: give network/POST loading states a minimum height (avoids black sliver).
    this.readerFillMinLoadingHeight = false,
    this.readerErrorChild,

    /// Gallery cards: themed surface + spinner while loading (GET and POST paths).
    this.surfaceLoadingPlaceholder = false,
    this.maxBytes,
    this.onImageSize,
  });

  /// Raw image URL (e-hentai CDN / ehgt), not pre-encoded proxy URL.
  final String sourceUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final double errorIconSize;

  /// White progress / reader layout hints.
  final bool readerStyle;
  final bool readerTallLoading;
  final bool readerFillMinLoadingHeight;
  final Widget? readerErrorChild;
  final bool surfaceLoadingPlaceholder;
  final int? maxBytes;
  final ValueChanged<Size>? onImageSize;

  @override
  State<WebProxiedImage> createState() => _WebProxiedImageState();
}

class _WebProxiedImageState extends State<WebProxiedImage> {
  Future<String>? _postObjectUrlFuture;
  String? _postObjectUrl;
  int _postGeneration = 0;

  @override
  void didUpdateWidget(WebProxiedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceUrl != widget.sourceUrl ||
        oldWidget.maxBytes != widget.maxBytes) {
      _resetPostFuture();
    }
  }

  void _resetPostFuture() {
    _postGeneration++;
    _postObjectUrlFuture = null;
    _revokePostObjectUrl();
  }

  Future<String>? _ensurePostFuture() {
    if (backendApiClient.shouldProxyImageUsePost(widget.sourceUrl)) {
      if (_postObjectUrlFuture != null) {
        return _postObjectUrlFuture;
      }
      final generation = ++_postGeneration;
      webImageClientLogVerbose(
          'WebProxiedImage POST path urlLen=${widget.sourceUrl.length}');
      _postObjectUrlFuture = _fetchPostObjectUrl(
        widget.sourceUrl,
        maxBytes: widget.maxBytes,
        generation: generation,
      );
      return _postObjectUrlFuture;
    }
    return null;
  }

  Future<String> _fetchPostObjectUrl(
    String sourceUrl, {
    int? maxBytes,
    required int generation,
  }) async {
    final bytes = await backendApiClient.fetchProxiedImageBytes(
      sourceUrl,
      maxBytes: maxBytes,
    );
    if (bytes.isEmpty) return '';
    final parts = [bytes.toJS].toJS;
    final blob = web.Blob(parts);
    final objectUrl = web.URL.createObjectURL(blob);
    if (!mounted || generation != _postGeneration) {
      web.URL.revokeObjectURL(objectUrl);
      return '';
    }
    if (_postObjectUrl != null && _postObjectUrl != objectUrl) {
      web.URL.revokeObjectURL(_postObjectUrl!);
    }
    _postObjectUrl = objectUrl;
    return objectUrl;
  }

  void _revokePostObjectUrl() {
    final objectUrl = _postObjectUrl;
    if (objectUrl != null) {
      web.URL.revokeObjectURL(objectUrl);
      _postObjectUrl = null;
    }
  }

  @override
  void dispose() {
    _revokePostObjectUrl();
    super.dispose();
  }

  double? _readerLoadingBoxHeight(BuildContext context) {
    if (!widget.readerStyle) {
      return null;
    }
    final h = MediaQuery.sizeOf(context).height;
    if (widget.readerTallLoading) {
      return h * 0.8;
    }
    if (widget.readerFillMinLoadingHeight) {
      return h * 0.55;
    }
    return null;
  }

  Widget _defaultError() {
    final s = widget.errorIconSize;
    return Icon(Icons.broken_image, color: Colors.grey.shade600, size: s);
  }

  @override
  Widget build(BuildContext context) {
    if (Get.isRegistered<WebSettingsController>()) {
      final controller = Get.find<WebSettingsController>();
      return Obx(() => _buildImage(context, controller.noImageMode.value));
    }
    return _buildImage(context, WebPreferenceSettings.noImageMode);
  }

  Widget _buildImage(BuildContext context, bool noImageMode) {
    final u = widget.sourceUrl;
    if (u.isEmpty) {
      webImageClientLogError('WebProxiedImage empty sourceUrl');
      return widget.readerErrorChild ?? _defaultError();
    }
    if (noImageMode) {
      return _noImagePlaceholder(context);
    }

    // Downloaded / archive / local reader uses `/api/image/...` on this app — not the EH CDN proxy allowlist.
    final base = backendApiClient.baseUrl;
    if (base.isNotEmpty && u.startsWith(base) && u.contains('/api/image/')) {
      webImageClientLogVerbose(
          'WebProxiedImage direct Image.network api/image');
      final provider = NetworkImage(_withMaxBytes(u, widget.maxBytes));
      return _ImageWithSizeCallback(
        provider: provider,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        onImageSize: widget.onImageSize,
        loadingBuilder: widget.readerStyle
            ? (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                final total = loadingProgress.expectedTotalBytes;
                final progress = total != null
                    ? loadingProgress.cumulativeBytesLoaded / total
                    : null;
                return SizedBox(
                  height: _readerLoadingBoxHeight(context),
                  width: double.infinity,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            value: progress, color: Colors.white54),
                        const SizedBox(height: 10),
                        Text(
                          'reader.loadingImage'.tr,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
            : null,
        errorBuilder: (c, err, st) {
          webImageClientLogError('api/image load failed $u — $err');
          return widget.readerErrorChild ?? _defaultError();
        },
      );
    }

    final postObjectUrlFuture = _ensurePostFuture();
    if (postObjectUrlFuture != null) {
      return FutureBuilder<String>(
        future: postObjectUrlFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting ||
              snap.connectionState == ConnectionState.active) {
            if (widget.readerStyle) {
              return SizedBox(
                height: _readerLoadingBoxHeight(context),
                width: double.infinity,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white54),
                      const SizedBox(height: 10),
                      Text(
                        'reader.loadingImage'.tr,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            if (widget.surfaceLoadingPlaceholder) {
              return Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snap.hasError) {
            webImageClientLogError(
              'WebProxiedImage POST future error ${_urlPreview(widget.sourceUrl)} — ${snap.error}',
            );
            return widget.readerErrorChild ?? _defaultError();
          }
          final objectUrl = snap.data;
          if (objectUrl == null || objectUrl.isEmpty) {
            webImageClientLogError(
              'WebProxiedImage POST empty objectUrl ${_urlPreview(widget.sourceUrl)}',
            );
            return widget.readerErrorChild ?? _defaultError();
          }
          return _ImageWithSizeCallback(
            provider: NetworkImage(objectUrl),
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            alignment: widget.alignment,
            onImageSize: widget.onImageSize,
            errorBuilder: (_, __, ___) =>
                widget.readerErrorChild ?? _defaultError(),
          );
        },
      );
    }

    final proxied =
        backendApiClient.proxyImageUrl(u, maxBytes: widget.maxBytes);
    webImageClientLogVerbose(
        'WebProxiedImage Image.network GET ${_urlPreview(proxied, max: 160)}');
    return _ImageWithSizeCallback(
      provider: NetworkImage(proxied),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      onImageSize: widget.onImageSize,
      loadingBuilder: widget.readerStyle
          ? (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              final total = loadingProgress.expectedTotalBytes;
              final progress = total != null
                  ? loadingProgress.cumulativeBytesLoaded / total
                  : null;
              return SizedBox(
                height: _readerLoadingBoxHeight(context),
                width: double.infinity,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          value: progress, color: Colors.white54),
                      const SizedBox(height: 10),
                      Text(
                        'reader.loadingImage'.tr,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
          : widget.surfaceLoadingPlaceholder
              ? (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
              : null,
      errorBuilder: (c, err, st) {
        webImageClientLogError(
          'WebProxiedImage GET proxy load failed ${_urlPreview(u)} — $err',
        );
        return widget.readerErrorChild ?? _defaultError();
      },
    );
  }

  Widget _noImagePlaceholder(BuildContext context) {
    final child = Icon(
      Icons.image_not_supported_outlined,
      color: widget.readerStyle ? Colors.white54 : Colors.grey.shade600,
      size: widget.errorIconSize,
    );
    if (widget.width == null && widget.height == null) {
      return Center(child: child);
    }
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      color: widget.readerStyle
          ? Colors.transparent
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: child,
    );
  }
}

class _ImageWithSizeCallback extends StatefulWidget {
  const _ImageWithSizeCallback({
    required this.provider,
    required this.fit,
    required this.alignment,
    this.width,
    this.height,
    this.loadingBuilder,
    this.errorBuilder,
    this.onImageSize,
  });

  final ImageProvider provider;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ValueChanged<Size>? onImageSize;

  @override
  State<_ImageWithSizeCallback> createState() => _ImageWithSizeCallbackState();
}

class _ImageWithSizeCallbackState extends State<_ImageWithSizeCallback> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_ImageWithSizeCallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _removeListener();
      _resolve();
    }
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  void _resolve() {
    if (widget.onImageSize == null || _stream != null) {
      return;
    }
    final stream =
        widget.provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        widget.onImageSize?.call(Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ));
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    _listener = listener;
    stream.addListener(listener);
  }

  void _removeListener() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
    );
  }
}

String _withMaxBytes(String url, int? maxBytes) {
  if (maxBytes == null) {
    return url;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}maxBytes=$maxBytes';
  }
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'maxBytes': '$maxBytes',
  }).toString();
}

String _urlPreview(String url, {int max = 120}) {
  if (url.length <= max) {
    return url;
  }
  return '${url.substring(0, max)}…(len=${url.length})';
}
