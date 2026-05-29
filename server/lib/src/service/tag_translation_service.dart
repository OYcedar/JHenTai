import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../core/database.dart';
import '../core/log.dart';

class TagTranslationService {
  static const String downloadUrl =
      'https://fastly.jsdelivr.net/gh/EhTagTranslation/DatabaseReleases/db.html.json';
  static const String tagCountReleaseUrl =
      'https://github.com/mokurin000/e-hentai-tag-count/releases/latest';
  static const String _timestampKey = 'tag_translation_timestamp';
  static const String _tagCountVersionKey = 'tag_count_version';

  final _nameRegex = RegExp(r'.*>(.+)<.*');
  bool _loading = false;
  bool _tagCountLoading = false;

  bool get isLoading => _loading;
  bool get isTagCountLoading => _tagCountLoading;

  String? get timestamp => db.readConfig(_timestampKey);
  String? get tagCountVersion => db.readConfig(_tagCountVersionKey);

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
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;

      final head = data['head'] as Map?;
      final committer = head?['committer'] as Map?;
      final newTimestamp = committer?['when']?.toString() ?? '';

      final existingTs = db.readConfig(_timestampKey);
      if (existingTs == newTimestamp &&
          newTimestamp.isNotEmpty &&
          db.tagTranslationCount() > 0 &&
          db.tagTranslationLinksCount() > 0) {
        log.info('Tag translation: already up to date ($newTimestamp)');
        _loading = false;
        return {
          'success': true,
          'message': 'Already up to date',
          'count': db.tagTranslationCount()
        };
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
          final links = value['links']?.toString() ?? '';
          rows.add(
              [namespace, key.toString(), tagName, fullTagName, intro, links]);
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

  Map<String, dynamic> getTagCountStatus() {
    return {
      'loaded': db.tagCountRows() > 0,
      'count': db.tagCountRows(),
      'version': tagCountVersion,
      'loading': _tagCountLoading,
    };
  }

  Future<Map<String, dynamic>> refreshTagCounts() async {
    if (_tagCountLoading) {
      return {'success': false, 'message': 'Already loading'};
    }
    _tagCountLoading = true;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
      ));
      final latest = await dio.get(
        tagCountReleaseUrl,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final tag = latest.realUri.pathSegments.isEmpty
          ? ''
          : latest.realUri.pathSegments.last;
      if (tag.isEmpty) {
        throw StateError('Failed to resolve latest tag-count release');
      }

      if (tag == tagCountVersion && db.tagCountRows() > 0) {
        _tagCountLoading = false;
        return {
          'success': true,
          'message': 'Already up to date',
          'count': db.tagCountRows(),
          'version': tag,
        };
      }

      final response = await dio.get<List<int>>(
        'https://github.com/mokurin000/e-hentai-tag-count/releases/download/$tag/tid_count_tag.csv.gz',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Empty tag-count download');
      }

      final csv = utf8.decode(GZipDecoder().decodeBytes(bytes));
      final rows = <List<Object>>[];
      for (final line in const LineSplitter().convert(csv)) {
        final columns = _parseCsvLine(line);
        if (columns.length < 3) continue;
        final count = int.tryParse(columns[1]);
        final namespaceKey = columns[2].replaceAll('"', '').trim();
        if (count == null || count < 5 || namespaceKey.isEmpty) {
          continue;
        }
        rows.add([namespaceKey, count]);
      }

      if (rows.isEmpty) {
        throw StateError('No valid tag-count rows found');
      }

      db.clearTagCounts();
      db.batchInsertTagCounts(rows);
      db.writeConfig(_tagCountVersionKey, tag);
      _tagCountLoading = false;
      return {'success': true, 'count': rows.length, 'version': tag};
    } catch (e) {
      log.warning('Tag count: failed to refresh: $e');
      _tagCountLoading = false;
      return {'success': false, 'message': '$e'};
    }
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }
}
