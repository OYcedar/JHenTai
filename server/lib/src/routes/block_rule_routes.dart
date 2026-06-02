import 'dart:convert';

import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/database.dart';
import '../core/log.dart';

const webUseBuiltInBlockedUsersKey = 'webUseBuiltInBlockedUsers';
const _builtInBlockedUsersCacheKey = 'webBuiltInBlockedUsersCache';
const _builtInBlockedUsersUrl =
    'https://raw.githubusercontent.com/jiangtian616/JHenTai/refs/heads/master/built_in_blocked_user.json';

List<Map<String, dynamic>> _builtInBlockedUsers = [];
DateTime? _builtInBlockedUsersLoadedAt;

bool useBuiltInBlockedUsers() {
  final raw = db.readConfig(webUseBuiltInBlockedUsersKey);
  if (raw == null || raw.trim().isEmpty) return true;
  final normalized = raw.trim().toLowerCase();
  return normalized != 'false' && normalized != '0' && normalized != 'no';
}

Future<List<Map<String, dynamic>>> builtInBlockedUserRules() async {
  if (!useBuiltInBlockedUsers()) return [];
  final users = await _loadBuiltInBlockedUsers();
  return [
    for (final user in users) ...[
      {
        'target': 'comment',
        'attribute': 'userId',
        'pattern': 'equal',
        'expression': (user['userId'] ?? '').toString(),
      },
      {
        'target': 'comment',
        'attribute': 'userName',
        'pattern': 'equal',
        'expression': (user['name'] ?? '').toString(),
      },
    ],
  ];
}

Future<List<Map<String, dynamic>>> _loadBuiltInBlockedUsers() async {
  final loadedAt = _builtInBlockedUsersLoadedAt;
  if (loadedAt != null &&
      DateTime.now().difference(loadedAt) < const Duration(hours: 24)) {
    return _builtInBlockedUsers;
  }

  final cached = _readCachedBuiltInBlockedUsers();
  if (cached.isNotEmpty) {
    _builtInBlockedUsers = cached;
    _builtInBlockedUsersLoadedAt ??= DateTime.now();
  }

  try {
    final response = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    )).get<Map<String, dynamic>>(_builtInBlockedUsersUrl);
    final root = response.data;
    final rawUsers = root?['blockedUsers'];
    if (rawUsers is! List) return _builtInBlockedUsers;
    final users = rawUsers
        .whereType<Map>()
        .map((item) => {
              'userId': item['userId'],
              'name': item['name']?.toString() ?? '',
            })
        .where((item) =>
            item['userId'] != null && (item['name'] as String).isNotEmpty)
        .toList();
    if (users.isEmpty) return _builtInBlockedUsers;
    _builtInBlockedUsers = users;
    _builtInBlockedUsersLoadedAt = DateTime.now();
    db.writeConfig(_builtInBlockedUsersCacheKey, jsonEncode(users));
  } catch (e) {
    log.warning('Failed to refresh built-in blocked users: $e');
  }
  return _builtInBlockedUsers;
}

List<Map<String, dynamic>> _readCachedBuiltInBlockedUsers() {
  final raw = db.readConfig(_builtInBlockedUsersCacheKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => {
              'userId': item['userId'],
              'name': item['name']?.toString() ?? '',
            })
        .where((item) =>
            item['userId'] != null && (item['name'] as String).isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

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
      return (double.tryParse(value) ?? 0) >=
          (double.tryParse(expression) ?? 0);
    case 'st':
      return (double.tryParse(value) ?? 0) < (double.tryParse(expression) ?? 0);
    case 'ste':
      return (double.tryParse(value) ?? 0) <=
          (double.tryParse(expression) ?? 0);
    default:
      return false;
  }
}

bool matchesBlockRuleSet(
  List<Map<String, dynamic>> rules,
  Map<String, dynamic> gallery,
) {
  return _matchesGroupedRules(
    rules,
    (rule) => matchesBlockRule(rule, gallery),
  );
}

bool matchesCommentBlockRule(
    Map<String, dynamic> rule, Map<String, dynamic> comment) {
  final target = rule['target'] as String? ?? 'gallery';
  if (target != 'comment') return false;

  final attribute = rule['attribute'] as String? ?? 'userName';
  final pattern = rule['pattern'] as String? ?? 'equal';
  final expression = rule['expression'] as String? ?? '';

  final value = switch (attribute) {
    'userName' => (comment['author'] as String?) ?? '',
    'userId' => (comment['userId'] ?? '').toString(),
    'commentText' ||
    'comment' ||
    'body' =>
      (comment['body'] as String? ?? '').replaceAll(RegExp(r'<[^>]+>'), ' '),
    'score' => (comment['score'] ?? '').toString(),
    _ => '',
  };

  return _matchesPattern(value, pattern, expression);
}

bool matchesCommentBlockRuleSet(
  List<Map<String, dynamic>> rules,
  Map<String, dynamic> comment,
) {
  return _matchesGroupedRules(
    rules,
    (rule) => matchesCommentBlockRule(rule, comment),
  );
}

bool _matchesGroupedRules(
  List<Map<String, dynamic>> rules,
  bool Function(Map<String, dynamic> rule) matches,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final rule in rules) {
    final groupId = rule['group_id']?.toString() ?? '';
    if (groupId.isEmpty) {
      if (matches(rule)) return true;
      continue;
    }
    grouped.putIfAbsent(groupId, () => []).add(rule);
  }

  for (final groupRules in grouped.values) {
    if (groupRules.isNotEmpty && groupRules.every(matches)) {
      return true;
    }
  }
  return false;
}

bool _matchesPattern(String value, String pattern, String expression) {
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
      return (double.tryParse(value) ?? 0) >=
          (double.tryParse(expression) ?? 0);
    case 'st':
      return (double.tryParse(value) ?? 0) < (double.tryParse(expression) ?? 0);
    case 'ste':
      return (double.tryParse(value) ?? 0) <=
          (double.tryParse(expression) ?? 0);
    default:
      return false;
  }
}
