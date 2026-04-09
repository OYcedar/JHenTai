import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';

class BlockRuleRoutes {
  Router get router {
    final router = Router();

    router.get('/list', _list);
    router.post('/save', _save);
    router.delete('/<id>', _delete);
    router.delete('/group/<groupId>', _deleteGroup);

    return router;
  }

  Future<Response> _list(Request request) async {
    final rules = db.selectAllBlockRules();
    return Response.ok(
      jsonEncode({'rules': rules}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _save(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
    }

    final id = body['id'] as int?;
    if (id != null && id > 0) {
      db.updateBlockRule(id, body);
      return Response.ok(jsonEncode({'success': true, 'id': id}),
          headers: {'Content-Type': 'application/json'});
    } else {
      final newId = db.insertBlockRule(body);
      return Response.ok(jsonEncode({'success': true, 'id': newId}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _delete(Request request, String id) async {
    final ruleId = int.tryParse(id);
    if (ruleId == null) {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid id'}));
    }
    db.deleteBlockRule(ruleId);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deleteGroup(Request request, String groupId) async {
    db.deleteBlockRulesByGroupId(groupId);
    return Response.ok(jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'});
  }
}

bool matchesBlockRule(Map<String, dynamic> rule, Map<String, dynamic> gallery) {
  final target = rule['target'] as String? ?? 'gallery';
  if (target != 'gallery') return false;

  final attribute = rule['attribute'] as String? ?? 'title';
  final pattern = rule['pattern'] as String? ?? 'like';
  final expression = rule['expression'] as String? ?? '';

  String value;
  switch (attribute) {
    case 'title':
      value = (gallery['title'] as String?) ?? '';
    case 'uploader':
      value = (gallery['uploader'] as String?) ?? '';
    case 'category':
      value = (gallery['category'] as String?) ?? '';
    case 'tag':
      final tags = gallery['tags'];
      if (tags is Map) {
        final allTags = <String>[];
        (tags as Map<String, dynamic>).forEach((ns, tagList) {
          if (tagList is List) {
            for (final t in tagList) {
              allTags.add('$ns:$t');
              allTags.add(t.toString());
            }
          }
        });
        value = allTags.join('\n');
      } else {
        value = '';
      }
    case 'gid':
      value = (gallery['gid'] ?? '').toString();
    default:
      value = '';
  }

  switch (pattern) {
    case 'equal':
      return value == expression;
    case 'like':
      return value.toLowerCase().contains(expression.toLowerCase());
    case 'notContain':
      return !value.toLowerCase().contains(expression.toLowerCase());
    case 'regex':
      try {
        return RegExp(expression).hasMatch(value);
      } catch (_) {
        return false;
      }
    case 'gt':
      return (double.tryParse(value) ?? 0) > (double.tryParse(expression) ?? 0);
    case 'gte':
      return (double.tryParse(value) ?? 0) >= (double.tryParse(expression) ?? 0);
    case 'st':
      return (double.tryParse(value) ?? 0) < (double.tryParse(expression) ?? 0);
    case 'ste':
      return (double.tryParse(value) ?? 0) <= (double.tryParse(expression) ?? 0);
    default:
      return false;
  }
}
