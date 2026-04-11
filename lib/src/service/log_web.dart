import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/exception/eh_site_exception.dart';
import 'package:logger/logger.dart';

import '../exception/upload_exception.dart';
import 'jh_service.dart';
import 'path_service.dart';

LogService log = LogService();

/// Console-only logging for web (no `dart:io` / log files).
class LogService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  Logger? _consoleLogger;

  LogPrinter devPrinter = PrettyPrinter(stackTraceBeginIndex: 0, methodCount: 6, levelEmojis: {Level.trace: '✔ '});

  @override
  List<JHLifeCircleBean> get initDependencies => [pathService];

  @override
  Future<void> doInitBean() async {
    PlatformDispatcher.instance.onError = (error, stack) {
      if (error is NotUploadException) {
        return true;
      }
      log.error('Global Error', error, stack);
      return false;
    };

    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is NotUploadException) {
        return;
      }
      log.error('Global Error', details.exception, details.stack);
    };
  }

  @override
  Future<void> doAfterBeanReady() async {}

  void _ensureConsole() {
    _consoleLogger ??= Logger(printer: devPrinter);
  }

  void trace(Object msg, [bool withStack = false]) {
    _ensureConsole();
    _consoleLogger?.t(msg, stackTrace: withStack ? null : StackTrace.empty);
  }

  void debug(Object msg, [bool withStack = false]) {
    _ensureConsole();
    _consoleLogger?.d(msg, stackTrace: withStack ? null : StackTrace.empty);
  }

  void info(Object msg, [bool withStack = false]) {
    _ensureConsole();
    _consoleLogger?.i(msg, stackTrace: withStack ? null : StackTrace.empty);
  }

  void warning(Object msg, [Object? error, bool withStack = false]) {
    _ensureConsole();
    _consoleLogger?.w(msg, error: error, stackTrace: withStack ? null : StackTrace.empty);
  }

  void error(Object msg, [Object? error, StackTrace? stackTrace]) {
    _ensureConsole();
    _consoleLogger?.e(msg, error: error, stackTrace: stackTrace);
  }

  void download(Object msg) {
    _ensureConsole();
    _consoleLogger?.t(msg, stackTrace: StackTrace.empty);
  }

  Future<void> uploadError(dynamic throwable, {dynamic stackTrace, Map<String, dynamic>? extraInfos}) async {}

  Future<String> getSize() async => '0';

  Future<void> clear() async {}
}

T callWithParamsUploadIfErrorOccurs<T>(T Function() func, {dynamic params, T? defaultValue}) {
  try {
    return func.call();
  } on Exception catch (e) {
    if (e is DioException || e is EHSiteException) {
      rethrow;
    }
    log.error('operationFailed'.tr, e);
    log.uploadError(e, extraInfos: {'params': params});
    if (defaultValue == null) {
      throw NotUploadException(e);
    }
    return defaultValue;
  } on Error catch (e) {
    log.error('operationFailed'.tr, e);
    log.uploadError(e, extraInfos: {'params': params});
    if (defaultValue == null) {
      throw NotUploadException(e);
    }
    return defaultValue;
  }
}
