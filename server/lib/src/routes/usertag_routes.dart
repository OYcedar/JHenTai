import 'dart:convert';

import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../network/eh_client.dart';
import '../utils/usertag_page_parser.dart';

class UsertagRoutes {
  final EHClient _client;

  UsertagRoutes(this._client);

  Router get router {
    final r = Router();
    r.get('/list', _list);
    r.post('/add', _add);
    r.post('/delete', _delete);
    return r;
  }

  Future<Response> _list(Request request) async {
    final tagset = int.tryParse(request.url.queryParameters['tagset'] ?? '1') ?? 1;
    try {
      final html = await _client.fetchMyTagsHtml(tagset);
      final data = parseMyTagsPage(html);
      return Response.ok(jsonEncode(data), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to load my tags: $e'}),
      );
    }
  }

  Future<Response> _add(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }
    final tagSetNo = (body['tagSetNo'] as num?)?.toInt() ?? 1;
    final tag = body['tag'] as String? ?? '';
    if (tag.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing tag'}));
    }
    final watch = body['watch'] as bool? ?? false;
    final hidden = body['hidden'] as bool? ?? false;
    final weight = (body['weight'] as num?)?.toInt() ?? 10;
    final tagColor = body['tagColor'] as String? ?? '';

    final data = <String, dynamic>{
      'usertag_action': 'add',
      'tagname_new': tag,
      'tagcolor_new': tagColor,
      'usertag_target': 0,
      'tagweight_new': weight,
    };
    if (hidden) data['taghide_new'] = 'on';
    if (watch) data['tagwatch_new'] = 'on';

    try {
      try {
        await _client.postMyTagsForm(tagSetNo, data);
      } on DioException catch (e) {
        if (e.response?.statusCode != 302) rethrow;
      }
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to add tag: $e'}),
      );
    }
  }

  Future<Response> _delete(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }
    final tagSetNo = (body['tagSetNo'] as num?)?.toInt() ?? 1;
    final watchedTagId = (body['watchedTagId'] as num?)?.toInt();
    if (watchedTagId == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing watchedTagId'}));
    }

    final data = <String, dynamic>{
      'usertag_action': 'mass',
      'tagname_new': '',
      'tagcolor_new': '',
      'usertag_target': 0,
      'tagweight_new': 10,
      'modify_usertags[]': watchedTagId,
    };

    try {
      try {
        await _client.postMyTagsForm(tagSetNo, data);
      } on DioException catch (e) {
        if (e.response?.statusCode != 302) rethrow;
      }
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete tag: $e'}),
      );
    }
  }
}
