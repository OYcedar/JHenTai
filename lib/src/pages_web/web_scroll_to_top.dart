import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';

Widget buildWebScrollToTopFab({
  required bool visible,
  required VoidCallback onPressed,
  String? heroTag,
}) {
  return visible
      ? FloatingActionButton.small(
          heroTag: heroTag,
          tooltip: 'home.scrollToTop'.tr,
          onPressed: onPressed,
          child: const Icon(Icons.vertical_align_top),
        )
      : const SizedBox.shrink();
}

bool shouldShowWebScrollToTop({
  required double offset,
  required double lastOffset,
  double threshold = 300,
}) {
  if (offset <= threshold) {
    return false;
  }
  final isScrollingDown = offset > lastOffset;
  return switch (WebPreferenceSettings.scrollToTopButtonMode) {
    WebScrollToTopButtonMode.scrollUp => !isScrollingDown,
    WebScrollToTopButtonMode.scrollDown => isScrollingDown,
    WebScrollToTopButtonMode.never => false,
    WebScrollToTopButtonMode.always => true,
  };
}

mixin WebScrollToTopState<T extends StatefulWidget> on State<T> {
  final scrollController = ScrollController();
  bool _showScrollToTop = false;
  double _lastScrollOffset = 0;

  bool get shouldShowScrollToTop => _showScrollToTop;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  Widget? buildScrollToTopFab({String? heroTag}) {
    return _showScrollToTop
        ? buildWebScrollToTopFab(
            visible: true,
            heroTag: heroTag,
            onPressed: scrollToTop,
          )
        : null;
  }

  Future<void> scrollToTop() async {
    if (!scrollController.hasClients) {
      return;
    }
    await scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void resetScrollToTopState() {
    _lastScrollOffset = 0;
    _setShowScrollToTop(false);
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
  }

  void _setShowScrollToTop(bool value) {
    if (!mounted || _showScrollToTop == value) {
      return;
    }
    setState(() => _showScrollToTop = value);
  }

  void _onScroll() {
    if (!scrollController.hasClients) {
      _setShowScrollToTop(false);
      return;
    }
    final offset = scrollController.offset;
    final previousOffset = _lastScrollOffset;
    _lastScrollOffset = offset;
    _setShowScrollToTop(
      shouldShowWebScrollToTop(offset: offset, lastOffset: previousOffset),
    );
  }
}

mixin WebScrollToTopControllerMixin on GetxController {
  final scrollController = ScrollController();
  final showScrollToTop = false.obs;
  double _lastScrollOffset = 0;

  void bindScrollToTop() {
    scrollController.addListener(_onScroll);
  }

  void unbindScrollToTop() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
  }

  void resetScrollToTopState() {
    _lastScrollOffset = 0;
    showScrollToTop.value = false;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
  }

  Future<void> scrollToTop() async {
    if (!scrollController.hasClients) {
      return;
    }
    await scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _onScroll() {
    if (!scrollController.hasClients) {
      showScrollToTop.value = false;
      return;
    }
    final offset = scrollController.offset;
    final previousOffset = _lastScrollOffset;
    _lastScrollOffset = offset;
    showScrollToTop.value =
        shouldShowWebScrollToTop(offset: offset, lastOffset: previousOffset);
  }
}
