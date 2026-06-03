import 'dart:convert';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../service/super_resolution_service.dart';

class SuperResolutionRoutes {
  SuperResolutionRoutes(this._service);

  final SuperResolutionService _service;

  Router get router {
    final router = Router();

    router.get('/capabilities', _capabilities);
    router.get('/settings', _settings);
    router.put('/settings', _updateSettings);
    router.get('/models', _models);
    router.post('/models/download', _downloadModel);
    router.get('/jobs', _listJobs);
    router.post('/jobs', _createJob);
    router.get('/jobs/<id>', _getJob);
    router.post('/jobs/<id>/pause', _pauseJob);
    router.post('/jobs/<id>/resume', _resumeJob);
    router.post('/jobs/<id>/cancel', _cancelJob);
    router.delete('/jobs/<id>', _deleteJob);
    router.get('/output/<sourceType>/<gid>/images', _outputImages);
    router.get('/image/<jobId>/<filename>', _image);

    return router;
  }

  Response _json(dynamic data, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _guard(Future<Response> Function() run) async {
    try {
      return await run();
    } catch (e) {
      return _json({'success': false, 'error': '$e'}, status: 400);
    }
  }

  Future<Response> _capabilities(Request request) async {
    return _json(_service.capabilities());
  }

  Future<Response> _models(Request request) async {
    return _json({'models': _service.listModels()});
  }

  Future<Response> _settings(Request request) async {
    return _json(_service.settings());
  }

  Future<Response> _updateSettings(Request request) {
    return _guard(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      _service.updateSettings(Map<String, dynamic>.from(body));
      return _json({'success': true, 'settings': _service.settings()});
    });
  }

  Future<Response> _downloadModel(Request request) {
    return _guard(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final model = body['model']?.toString() ?? 'realcugan';
      final result = await _service.downloadModel(model);
      return _json({'success': true, 'model': result});
    });
  }

  Future<Response> _listJobs(Request request) async {
    return _json({'jobs': _service.listJobs()});
  }

  Future<Response> _createJob(Request request) {
    return _guard(() async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final gid = (body['gid'] as num?)?.toInt();
      if (gid == null) {
        return _json({'success': false, 'error': 'Missing gid'}, status: 400);
      }
      final job = await _service.createJob(
        sourceType: body['sourceType']?.toString() ?? 'gallery',
        gid: gid,
        modelId: body['model']?.toString() ?? 'realcugan',
        gpuId: (body['gpuId'] as num?)?.toInt(),
        tileSize: (body['tileSize'] as num?)?.toInt() ?? 0,
        cpuOnly: body['cpuOnly'] == true,
        allowCpuOnly: body['allowCpuOnly'] == true,
      );
      return _json({'success': true, 'job': job});
    });
  }

  Future<Response> _getJob(Request request, String id) async {
    final job = _service.getJob(id);
    if (job == null) {
      return _json({'success': false, 'error': 'Job not found'}, status: 404);
    }
    return _json({'job': job});
  }

  Future<Response> _pauseJob(Request request, String id) {
    return _guard(() async {
      await _service.pause(id);
      return _json({'success': true});
    });
  }

  Future<Response> _resumeJob(Request request, String id) {
    return _guard(() async {
      await _service.resume(id);
      return _json({'success': true});
    });
  }

  Future<Response> _cancelJob(Request request, String id) {
    return _guard(() async {
      await _service.cancel(id);
      return _json({'success': true});
    });
  }

  Future<Response> _deleteJob(Request request, String id) {
    return _guard(() async {
      await _service.delete(
        id,
        deleteFiles: request.url.queryParameters['deleteFiles'] == 'true',
      );
      return _json({'success': true});
    });
  }

  Future<Response> _outputImages(
    Request request,
    String sourceType,
    String gid,
  ) async {
    final id = int.tryParse(gid);
    if (id == null) {
      return _json({'success': false, 'error': 'Invalid gid'}, status: 400);
    }
    return _json({'images': _service.outputImages(sourceType, id)});
  }

  Future<Response> _image(
    Request request,
    String jobId,
    String filename,
  ) async {
    final file = _service.outputFile(jobId, filename);
    if (file == null) {
      return Response.notFound('Not found');
    }
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': lookupMimeType(file.path) ?? 'application/octet-stream',
      },
    );
  }
}
