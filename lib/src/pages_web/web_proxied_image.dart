import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

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
    this.readerErrorChild,
    /// Gallery cards: themed surface + spinner while loading (GET and POST paths).
    this.surfaceLoadingPlaceholder = false,
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
  final Widget? readerErrorChild;
  final bool surfaceLoadingPlaceholder;

  @override
  State<WebProxiedImage> createState() => _WebProxiedImageState();
}

class _WebProxiedImageState extends State<WebProxiedImage> {
  Future<Uint8List>? _postFuture;

  @override
  void initState() {
    super.initState();
    _syncPostFuture();
  }

  @override
  void didUpdateWidget(WebProxiedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceUrl != widget.sourceUrl) {
      _syncPostFuture();
    }
  }

  void _syncPostFuture() {
    if (backendApiClient.shouldProxyImageUsePost(widget.sourceUrl)) {
      _postFuture = backendApiClient.fetchProxiedImageBytes(widget.sourceUrl);
    } else {
      _postFuture = null;
    }
  }

  Widget _defaultError() {
    final s = widget.errorIconSize;
    return Icon(Icons.broken_image, color: Colors.grey.shade600, size: s);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.sourceUrl;
    if (u.isEmpty) {
      return widget.readerErrorChild ?? _defaultError();
    }

    // Downloaded / archive / local reader uses `/api/image/...` on this app — not the EH CDN proxy allowlist.
    final base = backendApiClient.baseUrl;
    if (base.isNotEmpty && u.startsWith(base) && u.contains('/api/image/')) {
      return Image.network(
        u,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        loadingBuilder: widget.readerStyle
            ? (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                final total = loadingProgress.expectedTotalBytes;
                final progress = total != null ? loadingProgress.cumulativeBytesLoaded / total : null;
                return SizedBox(
                  height: widget.readerTallLoading ? MediaQuery.sizeOf(context).height * 0.8 : null,
                  child: Center(child: CircularProgressIndicator(value: progress, color: Colors.white54)),
                );
              }
            : null,
        errorBuilder: (_, __, ___) => widget.readerErrorChild ?? _defaultError(),
      );
    }

    if (_postFuture != null) {
      return FutureBuilder<Uint8List>(
        future: _postFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting ||
              snap.connectionState == ConnectionState.active) {
            if (widget.readerStyle) {
              return SizedBox(
                height: widget.readerTallLoading ? MediaQuery.sizeOf(context).height * 0.8 : null,
                child: const Center(child: CircularProgressIndicator(color: Colors.white54)),
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
            return widget.readerErrorChild ?? _defaultError();
          }
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            return widget.readerErrorChild ?? _defaultError();
          }
          return Image.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            alignment: widget.alignment,
            errorBuilder: (_, __, ___) => widget.readerErrorChild ?? _defaultError(),
          );
        },
      );
    }

    return Image.network(
      backendApiClient.proxyImageUrl(u),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      loadingBuilder: widget.readerStyle
          ? (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              final total = loadingProgress.expectedTotalBytes;
              final progress = total != null ? loadingProgress.cumulativeBytesLoaded / total : null;
              return SizedBox(
                height: widget.readerTallLoading ? MediaQuery.sizeOf(context).height * 0.8 : null,
                child: Center(child: CircularProgressIndicator(value: progress, color: Colors.white54)),
              );
            }
          : widget.surfaceLoadingPlaceholder
              ? (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
              : null,
      errorBuilder: (_, __, ___) => widget.readerErrorChild ?? _defaultError(),
    );
  }
}
