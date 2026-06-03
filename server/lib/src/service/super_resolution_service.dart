import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../config/server_config.dart';
import '../core/database.dart';
import '../core/log.dart';
import 'event_bus.dart';

enum SuperResolutionSourceType { gallery, archive }

enum SuperResolutionJobStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  canceled,
}

class SuperResolutionModelSpec {
  const SuperResolutionModelSpec({
    required this.id,
    required this.label,
    required this.kind,
    required this.downloadUrl,
    required this.binaryName,
    required this.modelArgument,
    this.defaultScale = 2,
  });

  final String id;
  final String label;
  final String kind;
  final String downloadUrl;
  final String binaryName;
  final String modelArgument;
  final int defaultScale;
}

class SuperResolutionInputImage {
  const SuperResolutionInputImage({
    required this.serialNo,
    required this.path,
  });

  final int serialNo;
  final String path;
}

class SuperResolutionService {
  SuperResolutionService(this._config, this._eventBus);

  static const models = <String, SuperResolutionModelSpec>{
    'realcugan': SuperResolutionModelSpec(
      id: 'realcugan',
      label: 'Real-CUGAN',
      kind: 'realcugan',
      downloadUrl:
          'https://github.com/nihui/realcugan-ncnn-vulkan/releases/download/20220728/realcugan-ncnn-vulkan-20220728-ubuntu.zip',
      binaryName: 'realcugan-ncnn-vulkan',
      modelArgument: 'models-se',
      defaultScale: 2,
    ),
    'realesrgan-x4plus': SuperResolutionModelSpec(
      id: 'realesrgan-x4plus',
      label: 'Real-ESRGAN x4plus',
      kind: 'realesrgan',
      downloadUrl:
          'https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/download/v0.2.0/realesrgan-ncnn-vulkan-v0.2.0-ubuntu.zip',
      binaryName: 'realesrgan-ncnn-vulkan',
      modelArgument: 'realesrgan-x4plus',
      defaultScale: 4,
    ),
    'realesrgan-x4plus-anime': SuperResolutionModelSpec(
      id: 'realesrgan-x4plus-anime',
      label: 'Real-ESRGAN anime',
      kind: 'realesrgan',
      downloadUrl:
          'https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/download/v0.2.0/realesrgan-ncnn-vulkan-v0.2.0-ubuntu.zip',
      binaryName: 'realesrgan-ncnn-vulkan',
      modelArgument: 'realesrgan-x4plus-anime',
      defaultScale: 4,
    ),
  };

  static final _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.avif',
  };

  final ServerConfig _config;
  final EventBus _eventBus;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 20),
  ));
  final Set<String> _cancelRequested = {};
  Process? _runningProcess;
  bool _processing = false;

  Future<void> init() async {
    db.pauseActiveSuperResolutionJobsOnStartup();
  }

  Map<String, dynamic> capabilities() {
    final arch = _runSimple('uname', ['-m']).trim();
    final vulkanInfo = _runSimple('vulkaninfo', ['--summary'], timeout: 3);
    final hasDevDri = Directory('/dev/dri').existsSync();
    final nvidiaVisible = Directory('/proc/driver/nvidia').existsSync() ||
        Platform.environment.keys.any((key) => key.startsWith('NVIDIA_'));
    final gpuAvailable = hasDevDri || nvidiaVisible;
    final supportedArch = arch == 'x86_64' || arch == 'amd64';
    final disk = _df(_config.superResolutionDir);
    final modelStates = {
      for (final spec in models.values) spec.id: _modelState(spec),
    };
    final status = supportedArch && gpuAvailable ? 'ok' : 'warn';
    return {
      'status': status,
      'generatedAt': DateTime.now().toIso8601String(),
      'runtime': {
        'os': Platform.operatingSystem,
        'arch': arch.isEmpty ? Platform.version : arch,
        'supportedPrebuiltBinary': supportedArch,
      },
      'gpu': {
        'available': gpuAvailable,
        'hasDevDri': hasDevDri,
        'nvidiaVisible': nvidiaVisible,
        'vulkanSummary': _trimLines(vulkanInfo, 12),
      },
      'paths': {
        'root': _config.superResolutionDir,
        'models': _config.superResolutionModelDir,
        'output': _config.superResolutionOutputDir,
      },
      'storage': disk,
      'models': modelStates,
      'warnings': [
        if (!supportedArch)
          'Current official Ubuntu packages are treated as amd64-only here. Provide a custom binary for this architecture.',
        if (!gpuAvailable)
          'No Vulkan/GPU device was detected. CPU-only mode is experimental and disabled by default.',
      ],
    };
  }

  List<Map<String, dynamic>> listModels() =>
      models.values.map((spec) => _modelState(spec)).toList();

  Future<Map<String, dynamic>> downloadModel(String modelId) async {
    final spec = models[modelId];
    if (spec == null) {
      throw ArgumentError('Unsupported model: $modelId');
    }
    final target = _modelDir(spec);
    await target.create(recursive: true);
    final tempFile = File(p.join(
      _config.tempDir,
      '${spec.id}-${DateTime.now().millisecondsSinceEpoch}.zip',
    ));
    await _dio.download(spec.downloadUrl, tempFile.path);
    try {
      final archive = ZipDecoder().decodeBytes(await tempFile.readAsBytes());
      for (final file in archive.files) {
        final normalizedName = p.normalize(file.name);
        if (normalizedName.startsWith('..')) continue;
        final outPath = p.join(target.path, normalizedName);
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      await _chmodExecutable(_binaryPath(spec));
    } finally {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
    return _modelState(spec);
  }

  List<Map<String, dynamic>> listJobs() =>
      db.selectSuperResolutionJobs().map(_jobJson).toList();

  Map<String, dynamic>? getJob(String id) {
    final row = db.selectSuperResolutionJob(id);
    return row == null ? null : _jobJson(row, includeImages: true);
  }

  Map<String, dynamic>? latestJob(String sourceType, int gid) {
    final row = db.selectLatestSuperResolutionJob(sourceType, gid);
    return row == null ? null : _jobJson(row);
  }

  Future<Map<String, dynamic>> createJob({
    required String sourceType,
    required int gid,
    required String modelId,
    int? gpuId,
    int tileSize = 0,
    bool cpuOnly = false,
    bool allowCpuOnly = false,
  }) async {
    final type = _parseSource(sourceType);
    final spec = models[modelId] ?? models['realcugan']!;
    final caps = capabilities();
    final gpuAvailable = ((caps['gpu'] as Map)['available'] as bool?) == true;
    if (!gpuAvailable && (!cpuOnly || !allowCpuOnly)) {
      throw StateError(
          'No GPU/Vulkan device detected. Enable experimental CPU-only mode to continue.');
    }
    if (!_binaryPath(spec).existsSync()) {
      throw StateError('Model package is not installed: ${spec.label}');
    }

    final images = _inputImages(type, gid);
    if (images.isEmpty) {
      throw StateError('No downloaded images found for $sourceType/$gid');
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final outputDir =
        p.join(_config.superResolutionOutputDir, sourceType, '$gid', id);
    await Directory(outputDir).create(recursive: true);
    final title = _sourceTitle(type, gid);
    db.insertSuperResolutionJob({
      'id': id,
      'source_type': sourceType,
      'gid': gid,
      'title': title,
      'model': spec.id,
      'scale': spec.defaultScale,
      'gpu_id': cpuOnly ? -1 : gpuId,
      'tile_size': tileSize,
      'cpu_only': cpuOnly ? 1 : 0,
      'status': SuperResolutionJobStatus.pending.name,
      'total_count': images.length,
      'success_count': 0,
      'failed_count': 0,
      'output_dir': outputDir,
      'created_at': now,
      'updated_at': now,
    });
    db.insertSuperResolutionImages(images.map((image) {
      final ext = p.extension(image.path).toLowerCase();
      final outExt = ext == '.gif' ? '.gif' : '.png';
      return {
        'job_id': id,
        'serial_no': image.serialNo,
        'input_path': image.path,
        'output_path': p.join(
            outputDir, '${image.serialNo.toString().padLeft(5, '0')}$outExt'),
        'status': 'pending',
        'updated_at': now,
      };
    }).toList());
    final job = getJob(id)!;
    _eventBus.fire('super_resolution_progress', job);
    unawaited(_processQueue());
    return job;
  }

  Future<void> resume(String id) async {
    final row = db.selectSuperResolutionJob(id);
    if (row == null) throw StateError('Job not found');
    db.updateSuperResolutionJob(id,
        status: SuperResolutionJobStatus.pending.name);
    _eventBus.fire('super_resolution_progress', getJob(id));
    unawaited(_processQueue());
  }

  Future<void> pause(String id) async {
    _cancelRequested.add(id);
    _runningProcess?.kill(ProcessSignal.sigterm);
    db.updateSuperResolutionJob(id,
        status: SuperResolutionJobStatus.paused.name);
    _eventBus.fire('super_resolution_progress', getJob(id));
  }

  Future<void> cancel(String id) async {
    _cancelRequested.add(id);
    _runningProcess?.kill(ProcessSignal.sigterm);
    db.updateSuperResolutionJob(id,
        status: SuperResolutionJobStatus.canceled.name);
    _eventBus.fire('super_resolution_progress', getJob(id));
  }

  Future<void> delete(String id, {bool deleteFiles = false}) async {
    final row = db.selectSuperResolutionJob(id);
    if (row == null) return;
    if (row['status'] == SuperResolutionJobStatus.running.name) {
      await cancel(id);
    }
    if (deleteFiles) {
      final outputDir = row['output_dir']?.toString() ?? '';
      if (outputDir.isNotEmpty) {
        final dir = Directory(outputDir);
        if (_isInside(dir.path, _config.superResolutionOutputDir) &&
            dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
    }
    db.deleteSuperResolutionJob(id);
    _eventBus.fire('super_resolution_removed', {'id': id});
  }

  List<Map<String, dynamic>> outputImages(String sourceType, int gid) {
    final job = db.selectLatestSuperResolutionJob(sourceType, gid);
    if (job == null) return [];
    final rows = db.selectSuperResolutionImages(job['id'].toString());
    return rows
        .where((row) =>
            row['status'] == SuperResolutionJobStatus.completed.name &&
            File(row['output_path'].toString()).existsSync())
        .map((row) => {
              'jobId': row['job_id'],
              'serialNo': row['serial_no'],
              'filename': p.basename(row['output_path'].toString()),
              'path': row['output_path'],
            })
        .toList();
  }

  File? outputFile(String jobId, String filename) {
    final job = db.selectSuperResolutionJob(jobId);
    if (job == null) return null;
    final outputDir = job['output_dir']?.toString() ?? '';
    final file = File(p.join(outputDir, filename));
    if (!_isInside(file.path, outputDir) || !file.existsSync()) return null;
    return file;
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final next = db
            .selectSuperResolutionJobs()
            .where(
                (job) => job['status'] == SuperResolutionJobStatus.pending.name)
            .toList();
        if (next.isEmpty) break;
        await _runJob(next.first);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _runJob(Map<String, dynamic> job) async {
    final id = job['id'].toString();
    _cancelRequested.remove(id);
    db.updateSuperResolutionJob(id,
        status: SuperResolutionJobStatus.running.name);
    _eventBus.fire('super_resolution_progress', getJob(id));
    var success = 0;
    var failed = 0;
    final images = db.selectSuperResolutionImages(id);
    for (final image in images) {
      if (_cancelRequested.contains(id)) break;
      if (image['status'] == SuperResolutionJobStatus.completed.name) {
        success++;
        continue;
      }
      final started = DateTime.now();
      final input = image['input_path'].toString();
      final output = image['output_path'].toString();
      db.updateSuperResolutionImage(
        id,
        image['serial_no'] as int,
        status: SuperResolutionJobStatus.running.name,
      );
      try {
        await _runImage(job, input, output);
        success++;
        db.updateSuperResolutionImage(
          id,
          image['serial_no'] as int,
          status: SuperResolutionJobStatus.completed.name,
          durationMs: DateTime.now().difference(started).inMilliseconds,
        );
      } catch (e) {
        failed++;
        db.updateSuperResolutionImage(
          id,
          image['serial_no'] as int,
          status: SuperResolutionJobStatus.failed.name,
          error: '$e',
          durationMs: DateTime.now().difference(started).inMilliseconds,
        );
        log.warning('Super resolution image failed job=$id input=$input: $e');
      }
      db.updateSuperResolutionJob(id,
          successCount: success, failedCount: failed);
      _eventBus.fire('super_resolution_progress', getJob(id));
    }
    if (_cancelRequested.remove(id)) {
      final current = db.selectSuperResolutionJob(id);
      if (current?['status'] == SuperResolutionJobStatus.canceled.name) {
        return;
      }
      db.updateSuperResolutionJob(id,
          status: SuperResolutionJobStatus.paused.name);
    } else {
      db.updateSuperResolutionJob(
        id,
        status: failed == 0
            ? SuperResolutionJobStatus.completed.name
            : SuperResolutionJobStatus.failed.name,
        error: failed == 0 ? '' : '$failed images failed',
      );
    }
    _eventBus.fire('super_resolution_progress', getJob(id));
  }

  Future<void> _runImage(
    Map<String, dynamic> job,
    String input,
    String output,
  ) async {
    await File(output).parent.create(recursive: true);
    if (p.extension(input).toLowerCase() == '.gif') {
      await File(input).copy(output);
      return;
    }
    final spec = models[job['model']] ?? models['realcugan']!;
    final args = <String>['-i', input, '-o', output, '-s', '${job['scale']}'];
    final tileSize = (job['tile_size'] as int?) ?? 0;
    if (tileSize > 0) {
      args.addAll(['-t', '$tileSize']);
    }
    final gpuId = job['gpu_id'];
    if (gpuId != null) {
      args.addAll(['-g', '$gpuId']);
    }
    args.addAll(['-j', '1:1:1']);
    if (spec.kind == 'realesrgan') {
      args.addAll(['-n', spec.modelArgument]);
    } else {
      args.addAll(['-m', p.join(_modelDir(spec).path, spec.modelArgument)]);
    }
    final envOverride = Platform.environment['JH_SUPER_RESOLUTION_BINARY'];
    final executable = envOverride != null && envOverride.isNotEmpty
        ? envOverride
        : _binaryPath(spec).path;
    final process = await Process.start(executable, args);
    _runningProcess = process;
    final stderr = StringBuffer();
    process.stderr
        .transform(utf8.decoder)
        .listen((chunk) => stderr.write(chunk));
    await process.stdout.drain<void>();
    final code = await process.exitCode;
    _runningProcess = null;
    if (code != 0) {
      throw StateError(
          stderr.isEmpty ? 'process exited with $code' : stderr.toString());
    }
  }

  List<SuperResolutionInputImage> _inputImages(
      SuperResolutionSourceType type, int gid) {
    if (type == SuperResolutionSourceType.gallery) {
      return db
          .selectGalleryImages(gid)
          .map((row) {
            final raw = row['path']?.toString() ?? '';
            final path = p.isAbsolute(raw)
                ? raw
                : p.join(_config.downloadDir, 'gallery', '$gid', raw);
            return SuperResolutionInputImage(
              serialNo: (row['serial_no'] as int?) ?? 0,
              path: path,
            );
          })
          .where((image) => File(image.path).existsSync())
          .toList();
    }
    final dir = Directory(p.join(_config.downloadDir, 'archive', '$gid'));
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) =>
            _imageExtensions.contains(p.extension(file.path).toLowerCase()))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return [
      for (var i = 0; i < files.length; i++)
        SuperResolutionInputImage(serialNo: i, path: files[i].path),
    ];
  }

  String _sourceTitle(SuperResolutionSourceType type, int gid) {
    if (type == SuperResolutionSourceType.gallery) {
      return db
              .selectAllGalleryDownloads()
              .where((row) => row['gid'] == gid)
              .firstOrNull?['title']
              ?.toString() ??
          '';
    }
    return db
            .selectAllArchiveDownloads()
            .where((row) => row['gid'] == gid)
            .firstOrNull?['title']
            ?.toString() ??
        '';
  }

  SuperResolutionSourceType _parseSource(String value) {
    return value == 'archive'
        ? SuperResolutionSourceType.archive
        : SuperResolutionSourceType.gallery;
  }

  Map<String, dynamic> _jobJson(
    Map<String, dynamic> row, {
    bool includeImages = false,
  }) {
    final total = (row['total_count'] as int?) ?? 0;
    final success = (row['success_count'] as int?) ?? 0;
    final failed = (row['failed_count'] as int?) ?? 0;
    return {
      'id': row['id'],
      'sourceType': row['source_type'],
      'gid': row['gid'],
      'title': row['title'],
      'model': row['model'],
      'scale': row['scale'],
      'gpuId': row['gpu_id'],
      'tileSize': row['tile_size'],
      'cpuOnly': row['cpu_only'] == 1,
      'status': row['status'],
      'totalCount': total,
      'successCount': success,
      'failedCount': failed,
      'progress': total == 0 ? 0 : success / total,
      'outputDir': row['output_dir'],
      'error': row['error'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      if (includeImages)
        'images': db.selectSuperResolutionImages(row['id'].toString()),
    };
  }

  Map<String, dynamic> _modelState(SuperResolutionModelSpec spec) {
    final binary = _binaryPath(spec);
    final dir = _modelDir(spec);
    return {
      'id': spec.id,
      'label': spec.label,
      'kind': spec.kind,
      'defaultScale': spec.defaultScale,
      'installed': binary.existsSync(),
      'downloadUrl': spec.downloadUrl,
      'directory': dir.path,
      'binary': binary.path,
    };
  }

  Directory _modelDir(SuperResolutionModelSpec spec) =>
      Directory(p.join(_config.superResolutionModelDir, spec.kind));

  File _binaryPath(SuperResolutionModelSpec spec) {
    final dir = _modelDir(spec);
    final candidates = dir.existsSync()
        ? dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.basename(file.path) == spec.binaryName)
            .toList()
        : <File>[];
    return candidates.isNotEmpty
        ? candidates.first
        : File(p.join(dir.path, spec.binaryName));
  }

  Future<void> _chmodExecutable(File file) async {
    if (!file.existsSync()) return;
    await Process.run('chmod', ['+x', file.path]);
  }

  String _runSimple(String command, List<String> args, {int timeout = 5}) {
    try {
      final result = Process.runSync(command, args).stdout?.toString();
      return result ?? '';
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> _df(String path) {
    try {
      final result = Process.runSync('df', ['-k', path]);
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return {};
      final parts = lines.last.split(RegExp(r'\s+'));
      if (parts.length < 5) return {};
      return {
        'totalBytes': int.parse(parts[1]) * 1024,
        'availableBytes': int.parse(parts[3]) * 1024,
        'usedPercent': parts[4],
      };
    } catch (_) {
      return {};
    }
  }

  String _trimLines(String value, int maxLines) {
    final lines = value.trim().split('\n');
    return lines.take(maxLines).join('\n');
  }

  bool _isInside(String child, String parent) {
    final c = p.normalize(p.absolute(child));
    final pth = p.normalize(p.absolute(parent));
    return c == pth || c.startsWith('$pth${p.separator}');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
