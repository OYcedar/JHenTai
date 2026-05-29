import 'dart:io';

import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class Log {
  late Logger _console;
  late Logger _file;
  late String _logDir;

  static const int _maxLogFiles = 10;
  static const int _maxLogSizeBytes = 10 * 1024 * 1024; // 10MB

  Log();

  Future<void> init(String logDir) async {
    _logDir = logDir;
    await Directory(logDir).create(recursive: true);

    await _cleanOldLogs();

    // AOT release (`dart compile exe`) defaults Logger to ProductionFilter, which drops `info`.
    // Use DevelopmentFilter for stdout so Docker logs show startup + JH_IMAGE_PROXY_DEBUG lines.
    _console = Logger(
      filter: DevelopmentFilter(),
      printer: PrettyPrinter(methodCount: 0, colors: false),
    );

    final fileName = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    _file = Logger(
      printer: PrettyPrinter(methodCount: 0, colors: false),
      filter: ProductionFilter(),
      output: FileOutput(file: File('$logDir/$fileName.log')),
    );

    await _console.init;
    await _file.init;
  }

  Future<void> _cleanOldLogs() async {
    try {
      final dir = Directory(_logDir);
      if (!dir.existsSync()) return;

      final logFiles = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // Delete files exceeding max count
      if (logFiles.length >= _maxLogFiles) {
        for (int i = _maxLogFiles - 1; i < logFiles.length; i++) {
          try {
            logFiles[i].deleteSync();
          } catch (_) {}
        }
      }

      // Delete files exceeding max size
      for (final file in logFiles) {
        try {
          if (file.lengthSync() > _maxLogSizeBytes) {
            file.deleteSync();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void trace(Object msg) {
    _console.t(msg, stackTrace: StackTrace.empty);
    _file.t(msg, stackTrace: StackTrace.empty);
  }

  void debug(Object msg) {
    _console.d(msg, stackTrace: StackTrace.empty);
    _file.d(msg, stackTrace: StackTrace.empty);
  }

  void info(Object msg) {
    _console.i(msg, stackTrace: StackTrace.empty);
    _file.i(msg, stackTrace: StackTrace.empty);
  }

  void warning(Object msg, [Object? error]) {
    _console.w(msg, error: error, stackTrace: StackTrace.empty);
    _file.w(msg, error: error, stackTrace: StackTrace.empty);
  }

  void error(Object msg, [Object? error, StackTrace? stackTrace]) {
    _console.e(msg, error: error, stackTrace: stackTrace);
    _file.e(msg, error: error, stackTrace: stackTrace);
  }
}

final Log log = Log();
