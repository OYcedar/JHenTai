class WebZhCN {
  static Map<String, String> keys() {
    return {
      // common
      'common.cancel': '取消',
      'common.ok': '确定',
      'common.error': '错误',
      'common.success': '成功',
      'common.failed': '失败',
      'common.retry': '重试',
      'common.delete': '删除',
      'common.reset': '重置',
      'common.unknown': '未知',
      'common.images': '@count 张图片',
      'common.pages': '@count 页',

      // setup
      'setup.title': 'JHenTai 服务器设置',
      'setup.description': '请输入服务器日志中显示的 API Token 以连接。',
      'setup.tokenLabel': 'API Token',
      'setup.connect': '连接',
      'setup.emptyToken': '请输入 Token',
      'setup.invalidToken': 'Token 无效，请查看服务器日志获取正确的 Token。',

      // home
      'home.title': 'JHenTai',
      'home.search': '搜索画廊...',
      'home.advancedSearch': '高级搜索',
      'home.downloads': '下载',
      'home.localGalleries': '本地画廊',
      'home.settings': '设置',
      'home.subtitle': 'E-Hentai 客户端',
      'home.home': '首页',
      'home.popular': '热门',
      'home.favorites': '收藏',
      'home.watched': '关注',
      'home.noGalleries': '未找到画廊',
      'home.previous': '上一页',
      'home.next': '下一页',
      'home.page': '第 @page 页',
      'home.loadFailed': '加载失败: @error',
      // advanced search
      'home.categoryFilter': '分类筛选',
      'home.minimumRating': '最低评分',
      'home.ratingAny': '不限',
      'home.searchIn': '搜索范围',
      'home.galleryName': '画廊名称',
      'home.tags': '标签',
      'home.description': '描述',
      'home.showExpunged': '显示已删除',
      'home.applySearch': '应用并搜索',
      // category names
      'category.doujinshi': '同人志',
      'category.manga': '漫画',
      'category.artistCg': '插画',
      'category.gameCg': '游戏CG',
      'category.western': '西方',
      'category.nonH': '非H',
      'category.imageSet': '图集',
      'category.cosplay': 'Cosplay',
      'category.asianPorn': '亚洲',
      'category.misc': '杂项',

      // gallery detail
      'detail.copyUrl': '复制画廊链接',
      'detail.copied': '已复制',
      'detail.removeFromFav': '从收藏中移除',
      'detail.addToFav': '添加到收藏',
      'detail.addToFavTitle': '添加到收藏',
      'detail.favRemoved': '已移除',
      'detail.favRemovedMsg': '已从收藏中移除',
      'detail.favAdded': '已添加',
      'detail.favAddedMsg': '已添加到 @name',
      'detail.favError': '收藏操作失败: @error',
      'detail.favSlot': '收藏夹 @n',
      'detail.rateTitle': '为画廊评分',
      'detail.rateSubmit': '提交',
      'detail.rated': '已评分',
      'detail.ratedMsg': '你的评分: @rating',
      'detail.rateFailed': '评分失败: @error',
      'detail.rateLoginRequired': '无法评分 — 需要登录',
      'detail.readOnline': '在线阅读',
      'detail.downloadGallery': '下载画廊',
      'detail.archiveResample': '归档（压缩）',
      'detail.archiveOriginal': '归档（原图）',
      'detail.downloadStarted': '下载已开始',
      'detail.galleryQueued': '画廊下载已加入队列',
      'detail.archiveQueued': '归档下载已加入队列',
      'detail.downloadFailed': '下载失败: @error',
      'detail.archiveFailed': '归档下载失败: @error',
      'detail.noArchive': '没有可用的归档',
      'detail.tags': '标签',
      'detail.comments': '评论 (@count)',
      'detail.anonymous': '匿名',
      'detail.loadFailed': '加载画廊详情失败: @error',

      // reader
      'reader.loading': '加载画廊中...',
      'reader.loadingImage': '加载图片中...',
      'reader.loadFailed': '加载画廊失败: @error',
      'reader.imageFailed': '图片加载失败',
      'reader.noImages': '没有提供图片',
      'reader.directionLabel': '阅读方向: @dir',
      'reader.ltr': '从左到右',
      'reader.rtl': '从右到左',
      'reader.vertical': '上下滚动',

      // downloads
      'downloads.title': '下载',
      'downloads.gallery': '画廊',
      'downloads.archive': '归档',
      'downloads.noGallery': '没有画廊下载',
      'downloads.noArchive': '没有归档下载',
      'downloads.read': '阅读',
      'downloads.pause': '暂停',
      'downloads.resume': '继续',
      'downloads.deleteTitle': '删除下载',
      'downloads.deleteConfirm': '删除此下载及其文件？',
      'downloads.loadFailed': '加载任务失败: @error',
      // gallery statuses
      'downloads.gStatus0': '无',
      'downloads.gStatus1': '下载中',
      'downloads.gStatus2': '已暂停',
      'downloads.gStatus3': '已完成',
      'downloads.gStatus4': '失败',
      // archive statuses
      'downloads.aStatus0': '无',
      'downloads.aStatus1': '解锁中',
      'downloads.aStatus2': '解析链接',
      'downloads.aStatus3': '下载中',
      'downloads.aStatus4': '已下载',
      'downloads.aStatus5': '解压中',
      'downloads.aStatus6': '已完成',
      'downloads.aStatus7': '已暂停',
      'downloads.aStatus8': '失败',

      // local
      'local.title': '本地画廊',
      'local.noGalleries': '未找到本地画廊',
      'local.helpText': '将目录挂载到 Docker 容器中\n或将画廊放入 local_gallery 文件夹',
      'local.scanNow': '立即扫描',
      'local.empty': '空',
      'local.noImages': '此画廊中没有图片',
      'local.loadFailed': '加载画廊图片失败: @error',
      'local.loadListFailed': '加载本地画廊失败: @error',

      // settings
      'settings.title': '设置',
      'settings.account': '账号',
      'settings.loggedIn': '已登录: @user',
      'settings.logout': '退出登录',
      'settings.logoutSuccess': '已退出登录',
      'settings.logoutFailed': '退出登录失败: @error',
      'settings.cookieLogin': '使用 Cookie 登录（推荐）',
      'settings.cookieHint': 'EH 论坛登录在服务器环境中被 Cloudflare 拦截。'
          '请在浏览器中登录后复制 Cookie 到此处。\n'
          '步骤: 登录 e-hentai.org → F12 → 应用 → Cookie → 复制以下值。',
      'settings.cookiePlaceholder': 'ipb_member_id=xxx; ipb_pass_hash=xxx; igneous=xxx',
      'settings.setCookies': '设置 Cookie',
      'settings.cookieSuccess': 'Cookie 设置成功',
      'settings.cookieFailed': '设置 Cookie 失败: @error',
      'settings.cookieEmpty': '请粘贴 Cookie',
      'settings.credentialLogin': '使用账号密码登录（可能因 Cloudflare 失败）',
      'settings.username': '用户名',
      'settings.password': '密码',
      'settings.login': '登录',
      'settings.loginSuccess': '登录成功',
      'settings.loginFailed': '登录失败',
      'settings.loginError': '登录失败: @error',
      'settings.emptyCredentials': '请输入用户名和密码',
      'settings.site': '站点',
      'settings.appearance': '外观',
      'settings.themeMode': '主题模式',
      'settings.system': '跟随系统',
      'settings.light': '浅色',
      'settings.dark': '深色',
      'settings.accentColor': '主题色',
      'settings.serverInfo': '服务器信息',
      'settings.dataDir': '数据目录',
      'settings.downloadDir': '下载目录',
      'settings.localGalleryDir': '本地画廊目录',
      'settings.extraScanPaths': '额外扫描路径',
      'settings.switchSiteFailed': '切换站点失败: @error',
      'settings.language': '语言',

      // history
      'history.title': '浏览记录',
      'history.empty': '暂无浏览记录',
      'history.clearAll': '清空全部',
      'history.clearTitle': '清空浏览记录',
      'history.clearConfirm': '确定要清空所有浏览记录吗？',
      'history.loadFailed': '加载浏览记录失败: @error',

      // search history
      'searchHistory.clearAll': '清除搜索记录',

      // comment
      'comment.placeholder': '写下评论...',
      'comment.send': '发送',
      'comment.posted': '评论已发送',
      'comment.postedMsg': '你的评论已发布',
      'comment.postFailed': '发送评论失败: @error',
      'comment.voteFailed': '投票失败: @error',

      // ranklist
      'ranklist.title': '排行榜',
      'ranklist.allTime': '历史总榜',
      'ranklist.year': '年度',
      'ranklist.month': '月度',
      'ranklist.yesterday': '昨日',

      // thumbnails
      'thumbnails.title': '缩略图 (@count)',
      'thumbnails.grid': '缩略图网格',
      'thumbnails.loadFailed': '加载缩略图失败: @error',

      // home additions
      'home.history': '浏览记录',
      'home.ranklist': '排行榜',

      // tag translation
      'tagTranslation.title': '标签翻译',
      'tagTranslation.loaded': '已加载 @count 个标签',
      'tagTranslation.notLoaded': '标签数据库未加载',
      'tagTranslation.lastUpdate': '最后更新: @time',
      'tagTranslation.refresh': '更新标签数据库',
      'tagTranslation.refreshSuccess': '已更新 @count 个标签',
      'tagTranslation.refreshFailed': '更新失败: @error',

      // list mode
      'listMode.toggle': '切换显示模式',
      'listMode.grid': '网格',
      'listMode.list': '列表',
      'listMode.listCompact': '紧凑列表',

      // quick search
      'quickSearch.title': '快速搜索',
      'quickSearch.empty': '没有已保存的搜索',
      'quickSearch.saveCurrent': '保存当前搜索',
      'quickSearch.saveTitle': '保存快速搜索',
      'quickSearch.nameLabel': '名称',

      // tag suggest
      'tagSuggest.tag': '标签',

      // common extras
      'common.save': '保存',

      // reader enhancements
      'reader.fitWidth': '适应宽度',
      'reader.doubleColumn': '双页模式',
      'reader.autoStart': '自动阅读',
      'reader.autoStop': '停止自动阅读',

      // block rules
      'blockRule.title': '屏蔽规则',
      'blockRule.empty': '没有配置屏蔽规则',
      'blockRule.add': '添加规则',
      'blockRule.edit': '编辑规则',
      'blockRule.manage': '管理屏蔽规则',
      'blockRule.ruleCount': '@count 条规则',
      'blockRule.ungrouped': '未分组',
      'blockRule.deleteGroup': '删除分组',
      'blockRule.target': '目标',
      'blockRule.attribute': '属性',
      'blockRule.pattern': '匹配模式',
      'blockRule.expression': '表达式',
      'blockRule.expressionHint': '要匹配的值',
      'blockRule.groupId': '分组 ID',
      'blockRule.groupIdHint': '可选的分组名称',
      'blockRule.blocked': '已屏蔽',
      'blockRule.tagBlocked': '标签 "@tag" 已被屏蔽',
      'blockRule.uploaderBlocked': '上传者 "@uploader" 已被屏蔽',
      'blockRule.blockTag': '屏蔽此标签',
      'blockRule.blockUploader': '屏蔽此上传者',

      // download enhancements
      'downloads.search': '搜索下载...',
      'downloads.allGroups': '所有分组',
      'downloads.group': '分组',

      // tag voting
      'tagVote.search': '搜索',
      'tagVote.searchUploader': '搜索上传者',
      'tagVote.voteUp': '投赞成票',
      'tagVote.voteDown': '投反对票',
      'tagVote.success': '已投票',
      'tagVote.votedUp': '已为 "@tag" 投赞成票',
      'tagVote.votedDown': '已为 "@tag" 投反对票',
      'tagVote.failed': '投票失败: @error',

      // responsive layout
      'home.selectGallery': '选择一个画廊查看详情',

      // gallery detail extras
      'detail.parentGallery': '父画廊',
      'detail.newerVersion': '有更新版本',

      // settings extras
      'settings.cookieStatusFull': 'Cookie 正常（包含 igneous — 可访问 EX）',
      'settings.cookieStatusNoIgneous': 'Cookie 已设置但缺少 igneous — EX 可能无法使用',
      'settings.cookieStatusNone': '未设置登录 Cookie',
      'settings.siteSwitched': '已切换到 @site',

      // download progress in detail
      'detail.completed': '已完成',
      'detail.retryDownload': '重试',
      'detail.readDownloaded': '阅读已下载',
      'detail.deleteDownload': '删除下载',
      'detail.deleteDownloadConfirm': '删除此下载及其文件？',
      'detail.archiveCompleted': '归档就绪',

      // detail enhancements
      'detail.share': '分享',
      'detail.jumpToPage': '跳转到页',
      'detail.similarSearch': '相似搜索',
      'detail.blockGallery': '屏蔽画廊',
      'detail.allComments': '全部评论',
      'detail.thumbnails': '缩略图 (@count)',
      'detail.viewAllThumbnails': '查看全部缩略图',
      'detail.galleryBlocked': '画廊已被屏蔽',
      'detail.jumpPageHint': '输入页码 (1-@max)',

      // reader enhancements
      'reader.saveImage': '保存图片',
      'reader.openInNewTab': '在新标签页打开',
      'reader.reloadImage': '重新加载',
      'reader.interval': '间隔',
      'reader.preload': '预加载',
      'reader.imageSpacing': '图片间距',
      'reader.autoInterval': '自动阅读间隔',
      'reader.startAutoMode': '开始',

      // settings reader
      'settings.readerSettings': '阅读器设置',
      'settings.defaultDirection': '默认方向',
      'settings.imageSpacing': '图片间距',
      'settings.preloadPages': '预加载页数',
      'settings.autoInterval': '自动阅读间隔',
      'settings.fitWidth': '适应宽度',

      // home enhancements
      'home.scrollToTop': '回到顶部',
    };
  }
}
