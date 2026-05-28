import 'package:web/web.dart' as web;

class WebPreferenceSettings {
  static const showAllGalleryTitlesKey = 'jh_web_show_all_gallery_titles';
  static const showGalleryTagVoteStatusKey =
      'jh_web_show_gallery_tag_vote_status';
  static const showCommentsKey = 'jh_web_show_comments';
  static const showAllCommentsKey = 'jh_web_show_all_comments';

  const WebPreferenceSettings._();

  static bool get showAllGalleryTitles =>
      _readBool(showAllGalleryTitlesKey, false);

  static bool get showGalleryTagVoteStatus =>
      _readBool(showGalleryTagVoteStatusKey, false);

  static bool get showComments => _readBool(showCommentsKey, true);

  static bool get showAllComments => _readBool(showAllCommentsKey, false);

  static void saveShowAllGalleryTitles(bool value) =>
      _writeBool(showAllGalleryTitlesKey, value);

  static void saveShowGalleryTagVoteStatus(bool value) =>
      _writeBool(showGalleryTagVoteStatusKey, value);

  static void saveShowComments(bool value) =>
      _writeBool(showCommentsKey, value);

  static void saveShowAllComments(bool value) =>
      _writeBool(showAllCommentsKey, value);

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
