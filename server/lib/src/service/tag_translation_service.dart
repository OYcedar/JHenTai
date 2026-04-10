import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/database.dart';
import '../core/log.dart';

class TagTranslationService {
  static const String downloadUrl =
      'https://fastly.jsdelivr.net/gh/EhTagTranslation/DatabaseReleases/db.html.json';
  static const String _timestampKey = 'tag_translation_timestamp';

  final _nameRegex = RegExp(r'.*>(.+)<.*');
  bool _loading = false;

  bool get isLoading => _loading;

  String? get timestamp => db.readConfig(_timestampKey);

  int get tagCount => db.tagTranslationCount();

  Future<Map<String, dynamic>> refresh() async {
    if (_loading) {
      return {'success': false, 'message': 'Already loading'};
    }
    _loading = true;
    try {
      log.info('Tag translation: downloading DB...');
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ));
      final response = await dio.get(downloadUrl);
      final data = response.data is String ? jsonDecode(response.data) : response.data;

      final head = data['head'] as Map?;
      final committer = head?['committer'] as Map?;
      final newTimestamp = committer?['when']?.toString() ?? '';

      final existingTs = db.readConfig(_timestampKey);
      if (existingTs == newTimestamp && newTimestamp.isNotEmpty && db.tagTranslationCount() > 0) {
        log.info('Tag translation: already up to date ($newTimestamp)');
        _loading = false;
        return {'success': true, 'message': 'Already up to date', 'count': db.tagTranslationCount()};
      }

      final dataList = data['data'] as List? ?? [];
      final rows = <List<String>>[];

      for (final entry in dataList) {
        final namespace = entry['namespace']?.toString() ?? '';
        if (namespace.isEmpty) continue;
        final tags = entry['data'] as Map? ?? {};
        tags.forEach((key, value) {
          final rawName = value['name']?.toString() ?? '';
          final match = _nameRegex.firstMatch(rawName);
          final tagName = match?.group(1) ?? rawName;
          final fullTagName = rawName;
          final intro = value['intro']?.toString() ?? '';
          rows.add([namespace, key.toString(), tagName, fullTagName, intro]);
        });
      }

      log.info('Tag translation: parsed ${rows.length} tags, writing to DB...');
      db.clearTagTranslations();
      db.batchInsertTagTranslations(rows);
      db.writeConfig(_timestampKey, newTimestamp);
      log.info('Tag translation: done. ${rows.length} tags loaded.');
      _loading = false;
      return {'success': true, 'count': rows.length};
    } catch (e) {
      log.warning('Tag translation: failed to download: $e');
      _loading = false;
      return {'success': false, 'message': '$e'};
    }
  }

  Map<String, dynamic> getStatus() {
    return {
      'loaded': db.tagTranslationCount() > 0,
      'count': db.tagTranslationCount(),
      'timestamp': timestamp,
      'loading': _loading,
    };
  }
}
