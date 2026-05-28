import 'package:web/web.dart' as web;

enum WebSearchBehaviour { inheritAll, inheritPartially, none }

enum WebScrollToTopButtonMode { scrollUp, scrollDown, never, always }

class WebPreferenceSettings {
  static const showAllGalleryTitlesKey = 'jh_web_show_all_gallery_titles';
  static const showGalleryTagVoteStatusKey =
      'jh_web_show_gallery_tag_vote_status';
  static const showCommentsKey = 'jh_web_show_comments';
  static const showAllCommentsKey = 'jh_web_show_all_comments';
  static const showUtcTimeKey = 'jh_web_show_utc_time';
  static const searchBehaviourKey = 'jh_web_search_behaviour';
  static const enableDefaultFavoriteKey = 'jh_web_enable_default_favorite';
  static const enableDefaultTagSetKey = 'jh_web_enable_default_tag_set';
  static const defaultTagSetNoKey = 'jh_web_default_tag_set_no';
  static const scrollToTopButtonModeKey = 'jh_web_scroll_to_top_button_mode';

  const WebPreferenceSettings._();

  static bool get showAllGalleryTitles =>
      _readBool(showAllGalleryTitlesKey, false);

  static bool get showGalleryTagVoteStatus =>
      _readBool(showGalleryTagVoteStatusKey, false);

  static bool get showComments => _readBool(showCommentsKey, true);

  static bool get showAllComments => _readBool(showAllCommentsKey, false);

  static bool get showUtcTime => _readBool(showUtcTimeKey, false);

  static bool get enableDefaultFavorite =>
      _readBool(enableDefaultFavoriteKey, false);

  static bool get enableDefaultTagSet =>
      _readBool(enableDefaultTagSetKey, true);

  static int? get defaultTagSetNo {
    final raw = web.window.localStorage.getItem(defaultTagSetNoKey);
    final value = int.tryParse(raw ?? '');
    return value != null && value > 0 ? value : null;
  }

  static WebScrollToTopButtonMode get scrollToTopButtonMode {
    final raw = web.window.localStorage.getItem(scrollToTopButtonModeKey);
    return WebScrollToTopButtonMode.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WebScrollToTopButtonMode.scrollDown,
    );
  }

  static WebSearchBehaviour get searchBehaviour {
    final raw = web.window.localStorage.getItem(searchBehaviourKey);
    return WebSearchBehaviour.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WebSearchBehaviour.inheritAll,
    );
  }

  static void saveShowAllGalleryTitles(bool value) =>
      _writeBool(showAllGalleryTitlesKey, value);

  static void saveShowGalleryTagVoteStatus(bool value) =>
      _writeBool(showGalleryTagVoteStatusKey, value);

  static void saveShowComments(bool value) =>
      _writeBool(showCommentsKey, value);

  static void saveShowAllComments(bool value) =>
      _writeBool(showAllCommentsKey, value);

  static void saveShowUtcTime(bool value) => _writeBool(showUtcTimeKey, value);

  static void saveEnableDefaultFavorite(bool value) =>
      _writeBool(enableDefaultFavoriteKey, value);

  static void saveEnableDefaultTagSet(bool value) =>
      _writeBool(enableDefaultTagSetKey, value);

  static void saveDefaultTagSetNo(int? value) {
    if (value == null || value <= 0) {
      web.window.localStorage.removeItem(defaultTagSetNoKey);
    } else {
      web.window.localStorage.setItem(defaultTagSetNoKey, '$value');
    }
  }

  static void saveScrollToTopButtonMode(WebScrollToTopButtonMode value) {
    web.window.localStorage.setItem(scrollToTopButtonModeKey, value.name);
  }

  static void saveSearchBehaviour(WebSearchBehaviour value) {
    web.window.localStorage.setItem(searchBehaviourKey, value.name);
  }

  static bool _readBool(String key, bool fallback) {
    final raw = web.window.localStorage.getItem(key);
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }

  static void _writeBool(String key, bool value) {
    web.window.localStorage.setItem(key, value ? 'true' : 'false');
  }
}
