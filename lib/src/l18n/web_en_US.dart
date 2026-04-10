class WebEnUS {
  static Map<String, String> keys() {
    return {
      // common
      'common.cancel': 'Cancel',
      'common.ok': 'OK',
      'common.error': 'Error',
      'common.success': 'Success',
      'common.failed': 'Failed',
      'common.retry': 'Retry',
      'common.delete': 'Delete',
      'common.reset': 'Reset',
      'common.unknown': 'Unknown',
      'common.images': '@count images',
      'common.pages': '@count pages',

      // setup
      'setup.title': 'JHenTai Server Setup',
      'setup.description': 'Enter the API token shown in the server logs to connect.',
      'setup.tokenLabel': 'API Token',
      'setup.connect': 'Connect',
      'setup.emptyToken': 'Please enter a token',
      'setup.invalidToken': 'Invalid token. Check your server logs for the correct token.',

      // home
      'home.title': 'JHenTai',
      'home.search': 'Search galleries...',
      'home.advancedSearch': 'Advanced search',
      'home.downloads': 'Downloads',
      'home.localGalleries': 'Local Galleries',
      'home.settings': 'Settings',
      'home.subtitle': 'E-Hentai Client',
      'home.home': 'Home',
      'home.popular': 'Popular',
      'home.favorites': 'Favorites',
      'home.watched': 'Watched',
      'home.noGalleries': 'No galleries found',
      'home.previous': 'Previous',
      'home.next': 'Next',
      'home.page': 'Page @page',
      'home.loadFailed': 'Failed to load: @error',
      // advanced search
      'home.categoryFilter': 'Category Filter',
      'home.minimumRating': 'Minimum Rating',
      'home.ratingAny': 'Any',
      'home.searchIn': 'Search In',
      'home.galleryName': 'Gallery Name',
      'home.tags': 'Tags',
      'home.description': 'Description',
      'home.showExpunged': 'Show Expunged',
      'home.applySearch': 'Apply & Search',
      // category names
      'category.doujinshi': 'Doujinshi',
      'category.manga': 'Manga',
      'category.artistCg': 'Artist CG',
      'category.gameCg': 'Game CG',
      'category.western': 'Western',
      'category.nonH': 'Non-H',
      'category.imageSet': 'Image Set',
      'category.cosplay': 'Cosplay',
      'category.asianPorn': 'Asian Porn',
      'category.misc': 'Misc',

      // gallery detail
      'detail.copyUrl': 'Copy gallery URL',
      'detail.copied': 'Copied',
      'detail.removeFromFav': 'Remove from favorites',
      'detail.addToFav': 'Add to favorites',
      'detail.addToFavTitle': 'Add to favorites',
      'detail.favRemoved': 'Removed',
      'detail.favRemovedMsg': 'Removed from favorites',
      'detail.favAdded': 'Added',
      'detail.favAddedMsg': 'Added to @name',
      'detail.favError': 'Favorite operation failed: @error',
      'detail.favSlot': 'Favorites @n',
      'detail.rateTitle': 'Rate this gallery',
      'detail.rateSubmit': 'Submit',
      'detail.rated': 'Rated',
      'detail.ratedMsg': 'Your rating: @rating',
      'detail.rateFailed': 'Rating failed: @error',
      'detail.rateLoginRequired': 'Cannot rate — login required',
      'detail.readOnline': 'Read Online',
      'detail.downloadGallery': 'Download Gallery',
      'detail.archiveResample': 'Archive (Resample)',
      'detail.archiveOriginal': 'Archive (Original)',
      'detail.downloadStarted': 'Download Started',
      'detail.galleryQueued': 'Gallery download has been queued',
      'detail.archiveQueued': 'Archive download has been queued',
      'detail.downloadFailed': 'Failed to start download: @error',
      'detail.archiveFailed': 'Failed to start archive download: @error',
      'detail.noArchive': 'No archive available',
      'detail.tags': 'Tags',
      'detail.comments': 'Comments (@count)',
      'detail.anonymous': 'Anonymous',
      'detail.loadFailed': 'Failed to load gallery detail: @error',

      // reader
      'reader.loading': 'Loading gallery...',
      'reader.loadingImage': 'Loading image...',
      'reader.loadFailed': 'Failed to load gallery: @error',
      'reader.imageFailed': 'Failed to load image',
      'reader.noImages': 'No images provided',
      'reader.directionLabel': 'Reading direction: @dir',
      'reader.ltr': 'LTR',
      'reader.rtl': 'RTL',
      'reader.vertical': 'Vertical',

      // downloads
      'downloads.title': 'Downloads',
      'downloads.gallery': 'Gallery',
      'downloads.archive': 'Archive',
      'downloads.noGallery': 'No gallery downloads',
      'downloads.noArchive': 'No archive downloads',
      'downloads.read': 'Read',
      'downloads.pause': 'Pause',
      'downloads.resume': 'Resume',
      'downloads.deleteTitle': 'Delete Download',
      'downloads.deleteConfirm': 'Delete this download and its files?',
      'downloads.loadFailed': 'Failed to load tasks: @error',
      // gallery statuses
      'downloads.gStatus0': 'None',
      'downloads.gStatus1': 'Downloading',
      'downloads.gStatus2': 'Paused',
      'downloads.gStatus3': 'Completed',
      'downloads.gStatus4': 'Failed',
      // archive statuses
      'downloads.aStatus0': 'None',
      'downloads.aStatus1': 'Unlocking',
      'downloads.aStatus2': 'Parsing URL',
      'downloads.aStatus3': 'Downloading',
      'downloads.aStatus4': 'Downloaded',
      'downloads.aStatus5': 'Unpacking',
      'downloads.aStatus6': 'Completed',
      'downloads.aStatus7': 'Paused',
      'downloads.aStatus8': 'Failed',

      // local
      'local.title': 'Local Galleries',
      'local.noGalleries': 'No local galleries found',
      'local.helpText': 'Mount directories into the Docker container\nor place galleries in the local_gallery folder',
      'local.scanNow': 'Scan Now',
      'local.empty': 'Empty',
      'local.noImages': 'No images found in this gallery',
      'local.loadFailed': 'Failed to load gallery images: @error',
      'local.loadListFailed': 'Failed to load local galleries: @error',

      // settings
      'settings.title': 'Settings',
      'settings.account': 'Account',
      'settings.loggedIn': 'Logged in as: @user',
      'settings.logout': 'Logout',
      'settings.logoutSuccess': 'Logged out',
      'settings.logoutFailed': 'Logout failed: @error',
      'settings.cookieLogin': 'Login with cookies (recommended)',
      'settings.cookieHint': 'EH forum login is blocked by Cloudflare in server environments. '
          'Please login via browser, then copy cookies here.\n'
          'Steps: Login at e-hentai.org → F12 → Application → Cookies → copy values below.',
      'settings.cookiePlaceholder': 'ipb_member_id=xxx; ipb_pass_hash=xxx; igneous=xxx',
      'settings.setCookies': 'Set Cookies',
      'settings.cookieSuccess': 'Cookies set successfully',
      'settings.cookieFailed': 'Failed to set cookies: @error',
      'settings.cookieEmpty': 'Please paste cookies',
      'settings.credentialLogin': 'Login with credentials (may fail due to Cloudflare)',
      'settings.username': 'Username',
      'settings.password': 'Password',
      'settings.login': 'Login',
      'settings.loginSuccess': 'Login successful',
      'settings.loginFailed': 'Login failed',
      'settings.loginError': 'Login failed: @error',
      'settings.emptyCredentials': 'Please enter username and password',
      'settings.site': 'Site',
      'settings.appearance': 'Appearance',
      'settings.themeMode': 'Theme Mode',
      'settings.system': 'System',
      'settings.light': 'Light',
      'settings.dark': 'Dark',
      'settings.accentColor': 'Accent Color',
      'settings.serverInfo': 'Server Info',
      'settings.dataDir': 'Data Directory',
      'settings.downloadDir': 'Download Directory',
      'settings.localGalleryDir': 'Local Gallery Dir',
      'settings.extraScanPaths': 'Extra Scan Paths',
      'settings.switchSiteFailed': 'Failed to switch site: @error',
      'settings.language': 'Language',

      // history
      'history.title': 'History',
      'history.empty': 'No browsing history',
      'history.clearAll': 'Clear All',
      'history.clearTitle': 'Clear History',
      'history.clearConfirm': 'Are you sure you want to clear all browsing history?',
      'history.loadFailed': 'Failed to load history: @error',

      // search history
      'searchHistory.clearAll': 'Clear search history',

      // comment
      'comment.placeholder': 'Write a comment...',
      'comment.send': 'Send',
      'comment.posted': 'Comment Posted',
      'comment.postedMsg': 'Your comment has been posted',
      'comment.postFailed': 'Failed to post comment: @error',
      'comment.voteFailed': 'Failed to vote: @error',

      // ranklist
      'ranklist.title': 'Ranklist',
      'ranklist.allTime': 'All Time',
      'ranklist.year': 'Past Year',
      'ranklist.month': 'Past Month',
      'ranklist.yesterday': 'Yesterday',

      // thumbnails
      'thumbnails.title': 'Thumbnails (@count)',
      'thumbnails.grid': 'Thumbnail Grid',
      'thumbnails.loadFailed': 'Failed to load thumbnails: @error',

      // home additions
      'home.history': 'History',
      'home.ranklist': 'Ranklist',

      // tag translation
      'tagTranslation.title': 'Tag Translation',
      'tagTranslation.loaded': '@count tags loaded',
      'tagTranslation.notLoaded': 'Tag database not loaded',
      'tagTranslation.lastUpdate': 'Last update: @time',
      'tagTranslation.refresh': 'Refresh Tag Database',
      'tagTranslation.refreshSuccess': '@count tags updated',
      'tagTranslation.refreshFailed': 'Failed to refresh: @error',

      // list mode
      'listMode.toggle': 'Toggle view mode',
      'listMode.grid': 'Grid',
      'listMode.list': 'List',
      'listMode.listCompact': 'Compact List',

      // quick search
      'quickSearch.title': 'Quick Search',
      'quickSearch.empty': 'No saved searches',
      'quickSearch.saveCurrent': 'Save current search',
      'quickSearch.saveTitle': 'Save Quick Search',
      'quickSearch.nameLabel': 'Name',

      // tag suggest
      'tagSuggest.tag': 'Tag',

      // common extras
      'common.save': 'Save',

      // reader enhancements
      'reader.fitWidth': 'Fit Width',
      'reader.doubleColumn': 'Double Column',
      'reader.autoStart': 'Auto Read',
      'reader.autoStop': 'Stop Auto Read',

      // block rules
      'blockRule.title': 'Block Rules',
      'blockRule.empty': 'No block rules configured',
      'blockRule.add': 'Add Rule',
      'blockRule.edit': 'Edit Rule',
      'blockRule.manage': 'Manage Block Rules',
      'blockRule.ruleCount': '@count rules',
      'blockRule.ungrouped': 'Ungrouped',
      'blockRule.deleteGroup': 'Delete Group',
      'blockRule.target': 'Target',
      'blockRule.attribute': 'Attribute',
      'blockRule.pattern': 'Pattern',
      'blockRule.expression': 'Expression',
      'blockRule.expressionHint': 'Value to match against',
      'blockRule.groupId': 'Group ID',
      'blockRule.groupIdHint': 'Optional group name',
      'blockRule.blocked': 'Blocked',
      'blockRule.tagBlocked': 'Tag "@tag" has been blocked',
      'blockRule.uploaderBlocked': 'Uploader "@uploader" has been blocked',
      'blockRule.blockTag': 'Block this tag',
      'blockRule.blockUploader': 'Block this uploader',

      // download enhancements
      'downloads.search': 'Search downloads...',
      'downloads.allGroups': 'All Groups',
      'downloads.group': 'Group',

      // tag voting
      'tagVote.search': 'Search',
      'tagVote.searchUploader': 'Search uploader',
      'tagVote.voteUp': 'Vote Up',
      'tagVote.voteDown': 'Vote Down',
      'tagVote.success': 'Voted',
      'tagVote.votedUp': 'Voted up for "@tag"',
      'tagVote.votedDown': 'Voted down for "@tag"',
      'tagVote.failed': 'Vote failed: @error',

      // responsive layout
      'home.selectGallery': 'Select a gallery to view details',

      // gallery detail extras
      'detail.parentGallery': 'Parent Gallery',
      'detail.newerVersion': 'Newer Version Available',

      // settings extras
      'settings.cookieStatusFull': 'Cookies OK (includes igneous — EX ready)',
      'settings.cookieStatusNoIgneous': 'Cookies set but missing igneous — EX may not work',
      'settings.cookieStatusNone': 'No login cookies set',
      'settings.siteSwitched': 'Switched to @site',

      // download progress in detail
      'detail.completed': 'Completed',
      'detail.retryDownload': 'Retry',
      'detail.readDownloaded': 'Read Downloaded',
      'detail.deleteDownload': 'Delete Download',
      'detail.deleteDownloadConfirm': 'Delete this download and its files?',
      'detail.archiveCompleted': 'Archive Ready',
    };
  }
}
