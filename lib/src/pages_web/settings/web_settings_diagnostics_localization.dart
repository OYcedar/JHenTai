import 'package:get/get.dart';

String localizeWebDiagnosticLabel(String value) {
  if (!_shouldUseChineseDiagnostics()) {
    return value;
  }
  final text = value.trim();
  final extraScanPath = RegExp(r'^Extra scan path (\d+)$').firstMatch(text);
  if (extraScanPath != null) {
    return '额外扫描路径 ${extraScanPath.group(1)}';
  }
  return switch (text) {
    'Data directory' => '数据目录',
    'Download directory' => '下载目录',
    'Local gallery directory' => '本地图库目录',
    'Log directory' => '日志目录',
    'Temp directory' => '临时目录',
    'Config directory' => '配置目录',
    'SQLite database' => 'SQLite 数据库',
    'Extra scan paths' => '额外扫描路径',
    'API token' => 'API token',
    'EH login cookies' => 'EH 登录 Cookie',
    'Docker image tag' => 'Docker 镜像标签',
    'SQLite backup' => 'SQLite 备份',
    'Proxy routing' => '代理路由',
    'Image super resolution' => '图片超分辨率',
    'Download failures' => '下载失败',
    _ => value,
  };
}

String localizeWebDiagnosticText(String value) {
  if (!_shouldUseChineseDiagnostics()) {
    return value;
  }
  final text = value.trim();
  if (text.isEmpty || text == '-') {
    return value;
  }

  final fixed = _fixedDiagnosticText[text];
  if (fixed != null) {
    return fixed;
  }

  String? match(
    String pattern,
    String Function(RegExpMatch match) builder,
  ) {
    final result = RegExp(pattern).firstMatch(text);
    return result == null ? null : builder(result);
  }

  return match(r'^(.+) exists and is writable$', (m) => '${m[1]} 存在且可写') ??
      match(r'^(.+) exists and is readable$', (m) => '${m[1]} 存在且可读') ??
      match(r'^(.+) exists but is not writable$', (m) => '${m[1]} 存在但不可写') ??
      match(r'^(.+) does not exist$', (m) => '${m[1]} 不存在') ??
      match(
          r'^(.+) cannot be accessed: (.+)$', (m) => '${m[1]} 无法访问：${m[2]}') ??
      match(
          r'^Check Docker volume mount, owner, and write permission for (.+)\.$',
          (m) => '请检查 ${m[1]} 的 Docker 卷挂载、所有者和写入权限。') ??
      match(r'^Check Docker volume mount and read permission for (.+)\.$',
          (m) => '请检查 ${m[1]} 的 Docker 卷挂载和读取权限。') ??
      match(r'^(.+) is readable \((\d+) config rows\)$',
          (m) => '${m[1]} 可读取（${m[2]} 条配置记录）') ??
      match(r'^Current tag: (.*), fork revision: (.*)$',
          (m) => '当前标签：${m[1]}，fork 版本：${m[2]}') ??
      match(r'^H@H route: (.*)$', (m) => 'H@H 路由：${m[1]}') ??
      match(r'^Runtime: (.*), installed models: (\d+)$',
          (m) => '运行状态：${m[1]}，已安装模型：${m[2]}') ??
      match(r'^(\d+) failed download tasks need attention\.$',
          (m) => '${m[1]} 个失败下载任务需要处理。') ??
      match(r'^(\d+) log files, (\d+) bytes$',
          (m) => '${m[1]} 个日志文件，${m[2]} 字节') ??
      value;
}

bool _shouldUseChineseDiagnostics() {
  return Get.locale?.languageCode.toLowerCase() == 'zh';
}

const _fixedDiagnosticText = {
  'API is responding': 'API 正常响应',
  'If the web UI cannot reach the API, check reverse proxy rules.':
      '如果 Web 界面无法访问 API，请检查反向代理规则。',
  'No extra scan paths configured': '未配置额外扫描路径',
  'Configure JH_EXTRA_SCAN_PATHS only when additional folders are mounted.':
      '仅在挂载了额外目录时配置 JH_EXTRA_SCAN_PATHS。',
  'No action needed.': '无需操作。',
  'Use the advanced settings log viewer when troubleshooting.':
      '排障时可使用高级设置中的日志查看器。',
  'No log files found': '未找到日志文件',
  'API token is configured for browser access.': 'API token 已配置，可用于浏览器访问。',
  'API token is not stored in the database yet.': '数据库中尚未保存 API token。',
  'Open the setup page with the token printed in Docker logs if this browser cannot access the API.':
      '如果当前浏览器无法访问 API，请使用 Docker 日志中打印的 token 打开初始化页面。',
  'EH cookies are stored.': 'EH Cookie 已保存。',
  'EH cookies are not configured.': 'EH Cookie 尚未配置。',
  'Set EH cookies in Account settings before browsing ExHentai or downloading protected galleries.':
      '浏览 ExHentai 或下载受保护画廊前，请先在账号设置中配置 EH Cookie。',
  'Use an explicit x.y.z-hhh tag in compose updates; avoid relying on latest for long-running NAS deployments.':
      '更新 compose 时请固定明确的 x.y.z-hhh 标签，长期运行的 NAS 部署不要依赖 latest。',
  'SQLite backup can be downloaded from the maintenance center before updates or restores.':
      '更新或恢复前，可在维护中心下载 SQLite 备份。',
  'Download a fresh SQLite backup before changing image versions, restoring data, or experimenting with imports.':
      '切换镜像版本、恢复数据或测试导入前，请先下载一份新的 SQLite 备份。',
  'If gallery pages work but H@H images fail, configure JH_HATH_PROXY or test H@H from the troubleshooting workbench.':
      '如果画廊页面正常但 H@H 图片失败，请配置 JH_HATH_PROXY，或在排障工作台测试 H@H。',
  'Pass /dev/dri into the container and install at least one model before enabling automatic super-resolution.':
      '启用自动超分前，请先把 /dev/dri 传入容器，并安装至少一个模型。',
  'No failed download tasks are currently reported.': '当前没有失败的下载任务。',
  'Open Downloads or the troubleshooting workbench to retry failed tasks and test H@H/proxy routing.':
      '打开下载页或排障工作台，重试失败任务并测试 H@H/代理路由。',
};
