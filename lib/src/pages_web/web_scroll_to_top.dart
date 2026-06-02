import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_preference_settings.dart';

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
        ? FloatingActionButton.small(
            heroTag: heroTag,
            tooltip: 'home.scrollToTop'.tr,
            onPressed: scrollToTop,
            child: const Icon(Icons.arrow_upward),
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
    final isScrollingDown = offset > _lastScrollOffset;
    _lastScrollOffset = offset;
    if (offset <= 300) {
      _setShowScrollToTop(false);
      return;
    }
    final show = switch (WebPreferenceSettings.scrollToTopButtonMode) {
      WebScrollToTopButtonMode.scrollUp => !isScrollingDown,
      WebScrollToTopButtonMode.scrollDown => isScrollingDown,
      WebScrollToTopButtonMode.never => false,
      WebScrollToTopButtonMode.always => true,
    };
    _setShowScrollToTop(show);
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
    final isScrollingDown = offset > _lastScrollOffset;
    _lastScrollOffset = offset;
    if (offset <= 300) {
      showScrollToTop.value = false;
      return;
    }
    showScrollToTop.value =
        switch (WebPreferenceSettings.scrollToTopButtonMode) {
      WebScrollToTopButtonMode.scrollUp => !isScrollingDown,
      WebScrollToTopButtonMode.scrollDown => isScrollingDown,
      WebScrollToTopButtonMode.never => false,
      WebScrollToTopButtonMode.always => true,
    };
  }
}
