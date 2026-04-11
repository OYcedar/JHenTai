import 'jh_service.dart';

PathService pathService = PathService();

/// Minimal stand-in for `dart:io` [Directory] on web (paths are unused by `main_web` graph).
class JhFsDirectory {
  const JhFsDirectory(this.path);
  final String path;
  bool existsSync() => false;
}

class PathService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  late JhFsDirectory tempDir = const JhFsDirectory('');
  JhFsDirectory? appDocDir;
  JhFsDirectory? appSupportDir;
  JhFsDirectory? externalStorageDir;
  JhFsDirectory? systemDownloadDir;

  @override
  List<JHLifeCircleBean> get initDependencies => [];

  @override
  Future<void> doInitBean() async {
    tempDir = const JhFsDirectory('');
  }

  @override
  Future<void> doAfterBeanReady() async {}

  JhFsDirectory getVisibleDir() {
    return appDocDir ?? appSupportDir ?? systemDownloadDir ?? const JhFsDirectory('');
  }
}
