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
import '../utils/archive_util.dart';
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
    this.category = 'basic',
    this.defaultScale = 2,
  });

  final String id;
  final String label;
  final String kind;
  final String downloadUrl;
  final String binaryName;
  final String modelArgument;
  final String category;
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

class _ModelDownloadState {
  _ModelDownloadState({
    required this.model,
    required this.status,
    this.sourceUrl = '',
    this.progress = 0,
    String? startedAt,
    String? updatedAt,
  })  : startedAt = startedAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  final String model;
  String status;
  String sourceUrl;
  String stage = '';
  double progress;
  int receivedBytes = 0;
  int totalBytes = 0;
  String error = '';
  final String startedAt;
  String updatedAt;

  Map<String, dynamic> toJson() => {
        'model': model,
        'status': status,
        'stage': stage,
        'sourceUrl': sourceUrl,
        'progress': progress.clamp(0, 1).toDouble(),
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'error': error,
        'startedAt': startedAt,
        'updatedAt': updatedAt,
      };

  void update({
    String? status,
    String? stage,
    String? sourceUrl,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? error,
  }) {
    if (status != null) this.status = status;
    if (stage != null) this.stage = stage;
    if (sourceUrl != null) this.sourceUrl = sourceUrl;
    if (progress != null) this.progress = progress.clamp(0, 1).toDouble();
    if (receivedBytes != null) this.receivedBytes = receivedBytes;
    if (totalBytes != null) this.totalBytes = totalBytes;
    if (error != null) this.error = error;
    updatedAt = DateTime.now().toIso8601String();
  }
}

class SuperResolutionService {
  SuperResolutionService(this._config, this._eventBus);

  static const _autoEnabledKey = 'super_resolution_auto_enabled';
  static const _autoModelKey = 'super_resolution_auto_model';
  static const _autoGpuIdKey = 'super_resolution_auto_gpu_id';
  static const _autoTileSizeKey = 'super_resolution_auto_tile_size';
  static const _autoAllowCpuOnlyKey = 'super_resolution_auto_allow_cpu_only';

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
    'waifu2x': SuperResolutionModelSpec(
      id: 'waifu2x',
      label: 'waifu2x',
      kind: 'waifu2x',
      downloadUrl:
          'https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-ubuntu.zip',
      binaryName: 'waifu2x-ncnn-vulkan',
      modelArgument: 'models-cunet',
      defaultScale: 2,
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
  final Map<String, _ModelDownloadState> _modelDownloads = {};
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
    final devices = _gpuDevices();
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
        'devices': devices,
        'composeSnippet': _gpuComposeSnippet(devices),
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

  Map<String, dynamic> settings() => {
        'autoEnabled': _readBool(_autoEnabledKey, defaultValue: false),
        'model': _readString(_autoModelKey, fallback: 'realcugan'),
        'gpuId': _readNullableInt(_autoGpuIdKey),
        'tileSize': _readInt(_autoTileSizeKey, fallback: 0),
        'allowCpuOnly': _readBool(_autoAllowCpuOnlyKey, defaultValue: false),
      };

  void updateSettings(Map<String, dynamic> data) {
    if (data.containsKey('autoEnabled')) {
      db.writeConfig(
          _autoEnabledKey, data['autoEnabled'] == true ? 'true' : 'false');
    }
    if (data.containsKey('model')) {
      final model = data['model']?.toString() ?? 'realcugan';
      db.writeConfig(
          _autoModelKey, models.containsKey(model) ? model : 'realcugan');
    }
    if (data.containsKey('gpuId')) {
      final gpuId = (data['gpuId'] as num?)?.toInt();
      db.writeConfig(_autoGpuIdKey, gpuId?.toString() ?? '');
    }
    if (data.containsKey('tileSize')) {
      final tileSize =
          ((data['tileSize'] as num?)?.toInt() ?? 0).clamp(0, 8192);
      db.writeConfig(_autoTileSizeKey, '$tileSize');
    }
    if (data.containsKey('allowCpuOnly')) {
      db.writeConfig(_autoAllowCpuOnlyKey,
          data['allowCpuOnly'] == true ? 'true' : 'false');
    }
  }

  Future<Map<String, dynamic>?> createJobIfAutoEnabled({
    required String sourceType,
    required int gid,
  }) async {
    final s = settings();
    if (s['autoEnabled'] != true) return null;
    final active = db.selectSuperResolutionJobs().where((job) {
      if (job['source_type'] != sourceType || job['gid'] != gid) return false;
      return {
        SuperResolutionJobStatus.pending.name,
        SuperResolutionJobStatus.running.name,
        SuperResolutionJobStatus.paused.name,
        SuperResolutionJobStatus.completed.name,
      }.contains(job['status']);
    }).toList();
    if (active.isNotEmpty) {
      log.info(
          '[super_resolution:auto] skipped source=$sourceType gid=$gid reason=existing_job job=${active.first['id']} status=${active.first['status']}');
      return null;
    }
    final allowCpuOnly = s['allowCpuOnly'] == true;
    final caps = capabilities();
    final gpuAvailable = ((caps['gpu'] as Map)['available'] as bool?) == true;
    if (!gpuAvailable && !allowCpuOnly) {
      log.warning(
          '[super_resolution:auto] skipped source=$sourceType gid=$gid reason=no_gpu');
      return null;
    }
    final model = s['model']?.toString() ?? 'realcugan';
    final spec = models[model] ?? models['realcugan']!;
    if (!_binaryPath(spec).existsSync()) {
      log.warning(
          '[super_resolution:auto] skipped source=$sourceType gid=$gid reason=model_not_installed model=${spec.id}');
      return null;
    }
    try {
      return await createJob(
        sourceType: sourceType,
        gid: gid,
        modelId: spec.id,
        gpuId: s['gpuId'] as int?,
        tileSize: (s['tileSize'] as int?) ?? 0,
        cpuOnly: !gpuAvailable && allowCpuOnly,
        allowCpuOnly: allowCpuOnly,
      );
    } catch (e, stackTrace) {
      log.warning(
          '[super_resolution:auto] skipped source=$sourceType gid=$gid reason=create_failed error=$e\n$stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>> downloadModel(String modelId) async {
    final spec = models[modelId];
    if (spec == null) {
      throw ArgumentError('Unsupported model: $modelId');
    }
    final installed = _modelState(spec);
    if (installed['installed'] == true && installed['executable'] == true) {
      _modelDownloads[spec.id] = _ModelDownloadState(
        model: spec.id,
        status: 'installed',
        progress: 1,
      );
      return _modelState(spec);
    }
    final current = _modelDownloads[spec.id];
    if (current != null && current.status == 'downloading') {
      return _modelState(spec);
    }
    final state = _ModelDownloadState(
      model: spec.id,
      status: 'downloading',
      sourceUrl: _modelDownloadUrl(spec),
    );
    _modelDownloads[spec.id] = state;
    unawaited(_downloadModelArchive(spec, state));
    return _modelState(spec);
  }

  Future<Map<String, dynamic>> importModelBytes(
    String modelId,
    List<int> bytes, {
    String filename = '',
  }) async {
    final tempFile = File(p.join(
      _config.tempDir,
      'sr-import-$modelId-${DateTime.now().millisecondsSinceEpoch}.zip',
    ));
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsBytes(bytes);
    try {
      await _validateModelArchiveFile(
        tempFile,
        sourceUrl: filename.isEmpty ? 'manual import' : filename,
      );
      return await importModelFile(modelId, tempFile, filename: filename);
    } finally {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
  }

  Future<Map<String, dynamic>> importModelFile(
    String modelId,
    File file, {
    String filename = '',
  }) async {
    final spec = models[modelId];
    if (spec == null) {
      throw ArgumentError('Unsupported model: $modelId');
    }
    final state = _ModelDownloadState(model: spec.id, status: 'importing');
    _modelDownloads[spec.id] = state;
    try {
      state.update(stage: 'validating');
      await _installModelArchive(spec, file);
      await _chmodExecutable(_binaryPath(spec));
      final installed = _modelState(spec);
      if (installed['installed'] != true) {
        throw StateError(
            'Imported package does not contain ${spec.binaryName}.');
      }
      state.update(status: 'installed', progress: 1);
      log.info(
          '[super_resolution:model] imported model=${spec.id} filename=$filename');
      return _modelState(spec);
    } catch (e) {
      state.update(status: 'failed', error: '$e');
      rethrow;
    }
  }

  Future<void> _downloadModelArchive(
    SuperResolutionModelSpec spec,
    _ModelDownloadState state,
  ) async {
    final sourceUrl = _modelDownloadUrl(spec);
    state.update(sourceUrl: sourceUrl, stage: 'downloading');
    final tempFile = File(p.join(
      _config.tempDir,
      '${spec.id}-${DateTime.now().millisecondsSinceEpoch}.zip',
    ));
    try {
      final response = await _dio.download(
        sourceUrl,
        tempFile.path,
        onReceiveProgress: (received, total) {
          state.update(
            status: 'downloading',
            stage: 'downloading',
            receivedBytes: received,
            totalBytes: total > 0 ? total : 0,
            progress: total > 0 ? received / total : 0,
          );
        },
      );
      await _validateModelArchiveFile(
        tempFile,
        sourceUrl: sourceUrl,
        statusCode: response.statusCode,
        contentType: response.headers.value('content-type'),
      );
      state.update(stage: 'installing');
      await _installModelArchive(spec, tempFile);
      await _chmodExecutable(_binaryPath(spec));
      final installed = _modelState(spec);
      if (installed['installed'] != true) {
        throw StateError(
            'Downloaded package does not contain ${spec.binaryName}.');
      }
      state.update(status: 'installed', progress: 1);
      log.info('[super_resolution:model] downloaded model=${spec.id}');
    } catch (e, stackTrace) {
      state.update(status: 'failed', error: '$e');
      log.warning(
          '[super_resolution:model] download failed model=${spec.id} error=$e\n$stackTrace');
    } finally {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
  }

  Future<Map<String, dynamic>> repairModelPermission(String modelId) async {
    final spec = models[modelId];
    if (spec == null) {
      throw ArgumentError('Unsupported model: $modelId');
    }
    final binary = _binaryPath(spec);
    if (!binary.existsSync()) {
      throw StateError('Model binary is not installed: ${spec.binaryName}.');
    }
    await _chmodExecutable(binary);
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
    } else if (spec.kind == 'waifu2x') {
      args.addAll([
        '-n',
        '1',
        '-m',
        p.join(_modelDir(spec).path, spec.modelArgument),
      ]);
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
            String path;
            if (p.isAbsolute(raw)) {
              path = raw;
            } else {
              final resolvedDir = resolveGalleryDir(_config.downloadDir, gid);
              path = p.join(
                  resolvedDir ?? p.join(_config.downloadDir, 'gallery', '$gid'),
                  raw);
            }
            return SuperResolutionInputImage(
              serialNo: (row['serial_no'] as int?) ?? 0,
              path: path,
            );
          })
          .where((image) => File(image.path).existsSync())
          .toList();
    }
    final resolvedDir = resolveArchiveDir(_config.downloadDir, gid);
    if (resolvedDir == null) return [];
    final dir = Directory(resolvedDir);
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
    final download = _modelDownloads[spec.id];
    final installed = binary.existsSync();
    final executable = _isExecutable(binary);
    return {
      'id': spec.id,
      'label': spec.label,
      'kind': spec.kind,
      'category': spec.category,
      'defaultScale': spec.defaultScale,
      'installed': installed,
      'executable': executable,
      'downloadUrl': spec.downloadUrl,
      'resolvedDownloadUrl': _modelDownloadUrl(spec),
      'downloadSource': _modelDownloadSource(spec),
      'directory': dir.path,
      'binary': binary.path,
      'actions': [
        if (installed && !executable) 'repair_permission',
        if (!installed || !executable) 'download',
        'import',
      ],
      'downloadState': download?.toJson() ??
          {
            'model': spec.id,
            'status': installed ? 'installed' : 'idle',
            'stage': installed ? 'installed' : 'idle',
            'sourceUrl': _modelDownloadUrl(spec),
            'progress': installed ? 1 : 0,
            'receivedBytes': 0,
            'totalBytes': 0,
            'error': '',
          },
    };
  }

  Future<void> _installModelArchive(
    SuperResolutionModelSpec spec,
    File archiveFile,
  ) async {
    final target = _modelDir(spec);
    final staging = Directory(p.join(
      _config.tempDir,
      'sr-model-${spec.id}-${DateTime.now().millisecondsSinceEpoch}',
    ));
    final backup = Directory(p.join(
      _config.tempDir,
      'sr-model-${spec.id}-backup-${DateTime.now().millisecondsSinceEpoch}',
    ));
    await target.parent.create(recursive: true);
    await staging.create(recursive: true);
    try {
      await _validateModelArchiveFile(
        archiveFile,
        sourceUrl: archiveFile.path,
      );
      await _extractModelArchive(spec, archiveFile, staging);
      final binary = _binaryPathInDir(spec, staging);
      if (!binary.existsSync()) {
        throw StateError('Package does not contain ${spec.binaryName}.');
      }
      await _chmodExecutable(binary);
      if (target.existsSync()) {
        await target.rename(backup.path);
      }
      await staging.rename(target.path);
      if (backup.existsSync()) {
        await backup.delete(recursive: true);
      }
    } catch (_) {
      if (target.existsSync()) {
        // Target was never removed unless backup exists.
      } else if (backup.existsSync()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      if (backup.existsSync()) {
        await backup.delete(recursive: true);
      }
    }
  }

  Future<void> _extractModelArchive(
    SuperResolutionModelSpec spec,
    File archiveFile,
    Directory target,
  ) async {
    await target.create(recursive: true);
    final input = InputFileStream(archiveFile.path);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBuffer(input);
    } on FormatException catch (e) {
      throw FormatException(
        'Invalid or corrupted ZIP package for ${spec.label}: ${e.message}. '
        'The download may be incomplete, blocked, or replaced by an HTML/proxy error page. '
        'Try JH_SUPER_RESOLUTION_MODEL_MIRROR or manual ZIP import.',
      );
    } finally {
      await input.close();
    }
    var binaryFound = false;
    for (final file in archive.files) {
      final normalizedName = _safeArchiveName(file.name);
      if (normalizedName == null) continue;
      final outPath = p.join(target.path, normalizedName);
      if (!_isInside(outPath, target.path)) continue;
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final content = file.content;
        if (content is List<int>) {
          await outFile.writeAsBytes(content);
        } else {
          throw StateError('Unsupported archive entry: ${file.name}');
        }
        if (p.basename(outFile.path) == spec.binaryName) {
          binaryFound = true;
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    if (!binaryFound && !_binaryPathInDir(spec, target).existsSync()) {
      throw StateError('Package does not contain ${spec.binaryName}.');
    }
  }

  String? _safeArchiveName(String name) {
    final normalized = p.normalize(name.replaceAll('\\', '/'));
    if (normalized.startsWith('..') || p.isAbsolute(normalized)) {
      return null;
    }
    return normalized;
  }

  Directory _modelDir(SuperResolutionModelSpec spec) =>
      Directory(p.join(_config.superResolutionModelDir, spec.kind));

  String _modelDownloadUrl(SuperResolutionModelSpec spec) {
    final mirror = Platform.environment['JH_SUPER_RESOLUTION_MODEL_MIRROR']
            ?.trim()
            .replaceFirst(RegExp(r'/+$'), '') ??
        '';
    if (mirror.isEmpty) return spec.downloadUrl;
    final original = Uri.parse(spec.downloadUrl);
    final filename = p.basename(original.path);
    return '$mirror/$filename';
  }

  String _modelDownloadSource(SuperResolutionModelSpec spec) {
    return _modelDownloadUrl(spec) == spec.downloadUrl ? 'official' : 'mirror';
  }

  Future<void> _validateModelArchiveFile(
    File file, {
    required String sourceUrl,
    int? statusCode,
    String? contentType,
  }) async {
    if (!await file.exists()) {
      throw StateError('Model package was not downloaded: $sourceUrl');
    }
    final length = await file.length();
    if (length < 4) {
      throw StateError(
        'Model package is empty or truncated ($length bytes): $sourceUrl',
      );
    }

    final input = await file.open();
    try {
      final header = await input.read(4);
      final isZip = header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4b &&
          (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07) &&
          (header[3] == 0x04 || header[3] == 0x06 || header[3] == 0x08);
      if (!isZip) {
        final preview = await _fileTextPreview(file);
        throw FormatException(
          'Downloaded model package is not a ZIP file. '
          'status=${statusCode ?? 'unknown'} contentType=${contentType ?? 'unknown'} '
          'bytes=$length source=$sourceUrl preview=$preview',
        );
      }
    } finally {
      await input.close();
    }
  }

  Future<String> _fileTextPreview(File file) async {
    final input = await file.open();
    try {
      final bytes = await input.read(160);
      return utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } catch (_) {
      return '<binary>';
    } finally {
      await input.close();
    }
  }

  File _binaryPath(SuperResolutionModelSpec spec) {
    return _binaryPathInDir(spec, _modelDir(spec));
  }

  File _binaryPathInDir(SuperResolutionModelSpec spec, Directory dir) {
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

  List<Map<String, dynamic>> _gpuDevices() {
    final dir = Directory('/dev/dri');
    if (!dir.existsSync()) return const [];
    final files =
        dir.listSync(followLinks: false).whereType<File>().where((file) {
      final name = p.basename(file.path);
      return name.startsWith('render') || name.startsWith('card');
    }).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.map((file) {
      try {
        final stat = file.statSync();
        return {
          'path': file.path,
          'name': p.basename(file.path),
          'gid': _deviceGid(file),
          'mode': stat.mode.toRadixString(8),
          'readable': _canOpenDevice(file, read: true),
          'writable': _canOpenDevice(file, read: false),
        };
      } catch (e) {
        return {
          'path': file.path,
          'name': p.basename(file.path),
          'error': '$e',
          'readable': false,
          'writable': false,
        };
      }
    }).toList();
  }

  bool _canOpenDevice(File file, {required bool read}) {
    try {
      final raf = file.openSync(
        mode: read ? FileMode.read : FileMode.writeOnlyAppend,
      );
      raf.closeSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  int? _deviceGid(File file) {
    try {
      final result = Process.runSync('stat', ['-c', '%g', file.path]);
      if (result.exitCode != 0) return null;
      return int.tryParse(result.stdout.toString().trim());
    } catch (_) {
      return null;
    }
  }

  String _gpuComposeSnippet(List<Map<String, dynamic>> devices) {
    final gids = devices
        .map((item) => (item['gid'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final lines = <String>[
      'services:',
      '  jhentai:',
      '    devices:',
      '      - /dev/dri:/dev/dri',
    ];
    if (gids.isNotEmpty) {
      lines.add('    group_add:');
      for (final gid in gids) {
        lines.add('      - "$gid"');
      }
    }
    return lines.join('\n');
  }

  bool _isExecutable(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.statSync().mode & 0x49 != 0;
    } catch (_) {
      return false;
    }
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

  String _readString(String key, {required String fallback}) {
    final value = db.readConfig(key)?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  int _readInt(String key, {required int fallback}) {
    return int.tryParse(db.readConfig(key) ?? '') ?? fallback;
  }

  int? _readNullableInt(String key) {
    final value = db.readConfig(key)?.trim();
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value);
  }

  bool _readBool(String key, {required bool defaultValue}) {
    final value = db.readConfig(key)?.trim().toLowerCase();
    if (value == null || value.isEmpty) return defaultValue;
    if (value == 'true' || value == '1' || value == 'yes') return true;
    if (value == 'false' || value == '0' || value == 'no') return false;
    return defaultValue;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
