import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

class ServerDatabase {
  late Database _db;

  Database get raw => _db;

  Future<void> init(String dbPath) async {
    _db = sqlite3.open(dbPath);
    _createTables();
    _migrateSchema();
    log.info('Database opened at $dbPath');
  }

  void _migrateSchema() {
    _addColumnIfMissing(
        'gallery_download', 'priority', 'INTEGER NOT NULL DEFAULT 0');
    _addColumnIfMissing('gallery_download', 'supersedes_gid', 'INTEGER');
    _addColumnIfMissing('gallery_download', 'superseded_by_gid', 'INTEGER');
    _addColumnIfMissing('gallery_download', 'download_original_image',
        'INTEGER NOT NULL DEFAULT 0');
    _addColumnIfMissing(
        'archive_download', 'priority', 'INTEGER NOT NULL DEFAULT 0');
    _addColumnIfMissing('tag_translation', 'links', "TEXT NOT NULL DEFAULT ''");
  }

  void _addColumnIfMissing(String table, String column, String columnDef) {
    final rows = _db.select('PRAGMA table_info($table)');
    if (rows.any((r) => r['name'] == column)) return;
    try {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $columnDef');
      log.info('Migration: added $table.$column');
    } catch (e) {
      log.warning('Migration skip $table.$column: $e');
    }
  }

  void _createTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS config (
        key TEXT NOT NULL,
        sub_key TEXT NOT NULL DEFAULT '',
        value TEXT NOT NULL,
        utime TEXT NOT NULL,
        PRIMARY KEY (key, sub_key)
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS gallery_download (
        gid INTEGER PRIMARY KEY,
        token TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        gallery_url TEXT NOT NULL,
        cover_url TEXT NOT NULL DEFAULT '',
        uploader TEXT DEFAULT '',
        publish_time TEXT NOT NULL,
        download_status INTEGER NOT NULL DEFAULT 0,
        insert_time TEXT NOT NULL,
        completed_count INTEGER NOT NULL DEFAULT 0,
        group_name TEXT NOT NULL DEFAULT 'default',
        priority INTEGER NOT NULL DEFAULT 0,
        download_original_image INTEGER NOT NULL DEFAULT 0,
        supersedes_gid INTEGER,
        superseded_by_gid INTEGER
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS gallery_image (
        gid INTEGER NOT NULL,
        serial_no INTEGER NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        image_url TEXT NOT NULL DEFAULT '',
        image_hash TEXT NOT NULL DEFAULT '',
        path TEXT NOT NULL DEFAULT '',
        download_status INTEGER NOT NULL DEFAULT 0,
        image_page_url TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (gid, serial_no)
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS archive_download (
        gid INTEGER PRIMARY KEY,
        token TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        gallery_url TEXT NOT NULL,
        cover_url TEXT NOT NULL DEFAULT '',
        uploader TEXT DEFAULT '',
        size TEXT NOT NULL DEFAULT '',
        publish_time TEXT NOT NULL,
        archive_status INTEGER NOT NULL DEFAULT 0,
        archive_page_url TEXT NOT NULL DEFAULT '',
        download_page_url TEXT NOT NULL DEFAULT '',
        download_url TEXT NOT NULL DEFAULT '',
        is_original INTEGER NOT NULL DEFAULT 0,
        insert_time TEXT NOT NULL,
        group_name TEXT NOT NULL DEFAULT 'default',
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS dio_cache (
        cache_key TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        content BLOB,
        headers BLOB,
        expire_date TEXT NOT NULL
      )
    ''');

    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cache_expire ON dio_cache(expire_date)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_cache_url ON dio_cache(url)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        gid INTEGER PRIMARY KEY,
        token TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        visit_time TEXT NOT NULL
      )
    ''');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_history_visit ON history(visit_time DESC)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        keyword TEXT PRIMARY KEY,
        use_count INTEGER NOT NULL DEFAULT 1,
        last_used TEXT NOT NULL
      )
    ''');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_search_last ON search_history(last_used DESC)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS tag_translation (
        namespace TEXT NOT NULL,
        key TEXT NOT NULL,
        tag_name TEXT NOT NULL DEFAULT '',
        full_tag_name TEXT NOT NULL DEFAULT '',
        intro TEXT NOT NULL DEFAULT '',
        links TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (namespace, key)
      )
    ''');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_name ON tag_translation(tag_name)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS quick_search (
        name TEXT PRIMARY KEY,
        config TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS block_rule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id TEXT NOT NULL DEFAULT '',
        target TEXT NOT NULL,
        attribute TEXT NOT NULL,
        pattern TEXT NOT NULL,
        expression TEXT NOT NULL
      )
    ''');
  }

  // --- Config operations ---

  String? readConfig(String key, [String subKey = '']) {
    final result = _db.select(
      'SELECT value FROM config WHERE key = ? AND sub_key = ?',
      [key, subKey],
    );
    return result.isEmpty ? null : result.first['value'] as String;
  }

  void writeConfig(String key, String value, [String subKey = '']) {
    _db.execute(
      'INSERT OR REPLACE INTO config (key, sub_key, value, utime) VALUES (?, ?, ?, ?)',
      [key, subKey, value, DateTime.now().toIso8601String()],
    );
  }

  bool deleteConfig(String key, [String subKey = '']) {
    _db.execute(
      'DELETE FROM config WHERE key = ? AND sub_key = ?',
      [key, subKey],
    );
    return _db.updatedRows > 0;
  }

  // --- Gallery download operations ---

  List<Map<String, dynamic>> selectAllGalleryDownloads() {
    return _db
        .select('SELECT * FROM gallery_download ORDER BY insert_time DESC')
        .map(_rowToMap)
        .toList();
  }

  void insertGalleryDownload(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO gallery_download 
      (gid, token, title, category, page_count, gallery_url, cover_url, uploader, publish_time, download_status, insert_time, completed_count, group_name, priority, download_original_image, supersedes_gid, superseded_by_gid)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'],
      data['token'],
      data['title'],
      data['category'],
      data['page_count'],
      data['gallery_url'],
      data['cover_url'] ?? '',
      data['uploader'] ?? '',
      data['publish_time'],
      data['download_status'] ?? 0,
      data['insert_time'] ?? DateTime.now().toIso8601String(),
      data['completed_count'] ?? 0,
      data['group_name'] ?? 'default',
      data['priority'] ?? 0,
      data['download_original_image'] ?? 0,
      data['supersedes_gid'],
      data['superseded_by_gid'],
    ]);
  }

  void updateGalleryDownloadMeta(int gid,
      {int? priority, String? groupName, int? supersededByGid}) {
    if (priority != null) {
      _db.execute('UPDATE gallery_download SET priority = ? WHERE gid = ?',
          [priority, gid]);
    }
    if (groupName != null) {
      _db.execute('UPDATE gallery_download SET group_name = ? WHERE gid = ?',
          [groupName, gid]);
    }
    if (supersededByGid != null) {
      _db.execute(
          'UPDATE gallery_download SET superseded_by_gid = ? WHERE gid = ?',
          [supersededByGid, gid]);
    }
  }

  void updateGalleryDownloadStatus(int gid, int status, {int? completedCount}) {
    if (completedCount != null) {
      _db.execute(
        'UPDATE gallery_download SET download_status = ?, completed_count = ? WHERE gid = ?',
        [status, completedCount, gid],
      );
    } else {
      _db.execute(
        'UPDATE gallery_download SET download_status = ? WHERE gid = ?',
        [status, gid],
      );
    }
  }

  void deleteGalleryDownload(int gid) {
    _db.execute('DELETE FROM gallery_download WHERE gid = ?', [gid]);
    _db.execute('DELETE FROM gallery_image WHERE gid = ?', [gid]);
  }

  // --- Gallery image operations ---

  List<Map<String, dynamic>> selectGalleryImages(int gid) {
    return _db
        .select('SELECT * FROM gallery_image WHERE gid = ? ORDER BY serial_no',
            [gid])
        .map(_rowToMap)
        .toList();
  }

  void upsertGalleryImage(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO gallery_image
      (gid, serial_no, url, image_url, image_hash, path, download_status, image_page_url)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'],
      data['serial_no'],
      data['url'] ?? '',
      data['image_url'] ?? '',
      data['image_hash'] ?? '',
      data['path'] ?? '',
      data['download_status'] ?? 0,
      data['image_page_url'] ?? '',
    ]);
  }

  // --- Archive download operations ---

  List<Map<String, dynamic>> selectAllArchiveDownloads() {
    return _db
        .select('SELECT * FROM archive_download ORDER BY insert_time DESC')
        .map(_rowToMap)
        .toList();
  }

  void insertArchiveDownload(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO archive_download
      (gid, token, title, category, page_count, gallery_url, cover_url, uploader, size,
       publish_time, archive_status, archive_page_url, download_page_url, download_url,
       is_original, insert_time, group_name, downloaded_bytes, total_bytes, priority)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'],
      data['token'],
      data['title'],
      data['category'],
      data['page_count'],
      data['gallery_url'],
      data['cover_url'] ?? '',
      data['uploader'] ?? '',
      data['size'] ?? '',
      data['publish_time'],
      data['archive_status'] ?? 0,
      data['archive_page_url'] ?? '',
      data['download_page_url'] ?? '',
      data['download_url'] ?? '',
      data['is_original'] ?? 0,
      data['insert_time'] ?? DateTime.now().toIso8601String(),
      data['group_name'] ?? 'default',
      data['downloaded_bytes'] ?? 0,
      data['total_bytes'] ?? 0,
      data['priority'] ?? 0,
    ]);
  }

  void updateArchiveDownloadMeta(int gid, {int? priority, String? groupName}) {
    if (priority != null) {
      _db.execute('UPDATE archive_download SET priority = ? WHERE gid = ?',
          [priority, gid]);
    }
    if (groupName != null) {
      _db.execute('UPDATE archive_download SET group_name = ? WHERE gid = ?',
          [groupName, gid]);
    }
  }

  void updateArchiveDownloadStatus(int gid, int status,
      {int? downloadedBytes, int? totalBytes}) {
    final updates = <String>['archive_status = ?'];
    final params = <dynamic>[status];
    if (downloadedBytes != null) {
      updates.add('downloaded_bytes = ?');
      params.add(downloadedBytes);
    }
    if (totalBytes != null) {
      updates.add('total_bytes = ?');
      params.add(totalBytes);
    }
    params.add(gid);
    _db.execute(
        'UPDATE archive_download SET ${updates.join(', ')} WHERE gid = ?',
        params);
  }

  void updateArchiveDownloadUrls(int gid,
      {String? downloadPageUrl, String? downloadUrl}) {
    if (downloadPageUrl != null) {
      _db.execute(
          'UPDATE archive_download SET download_page_url = ? WHERE gid = ?',
          [downloadPageUrl, gid]);
    }
    if (downloadUrl != null) {
      _db.execute('UPDATE archive_download SET download_url = ? WHERE gid = ?',
          [downloadUrl, gid]);
    }
  }

  void deleteArchiveDownload(int gid) {
    _db.execute('DELETE FROM archive_download WHERE gid = ?', [gid]);
  }

  // --- History operations ---

  void upsertHistory(
      int gid, String token, String title, String coverUrl, String category) {
    _db.execute('''
      INSERT OR REPLACE INTO history (gid, token, title, cover_url, category, visit_time)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [
      gid,
      token,
      title,
      coverUrl,
      category,
      DateTime.now().toIso8601String()
    ]);
  }

  List<Map<String, dynamic>> selectHistory({int limit = 50, int offset = 0}) {
    return _db
        .select(
          'SELECT * FROM history ORDER BY visit_time DESC LIMIT ? OFFSET ?',
          [limit, offset],
        )
        .map(_rowToMap)
        .toList();
  }

  void deleteHistory(int gid) {
    _db.execute('DELETE FROM history WHERE gid = ?', [gid]);
  }

  void clearHistory() {
    _db.execute('DELETE FROM history');
  }

  // --- Search history operations ---

  void recordSearch(String keyword) {
    _db.execute('''
      INSERT INTO search_history (keyword, use_count, last_used) VALUES (?, 1, ?)
      ON CONFLICT(keyword) DO UPDATE SET use_count = use_count + 1, last_used = ?
    ''', [
      keyword,
      DateTime.now().toIso8601String(),
      DateTime.now().toIso8601String()
    ]);
  }

  List<Map<String, dynamic>> selectSearchHistory({int limit = 20}) {
    return _db
        .select(
          'SELECT * FROM search_history ORDER BY last_used DESC LIMIT ?',
          [limit],
        )
        .map(_rowToMap)
        .toList();
  }

  void deleteSearchHistory(String keyword) {
    _db.execute('DELETE FROM search_history WHERE keyword = ?', [keyword]);
  }

  void clearSearchHistory() {
    _db.execute('DELETE FROM search_history');
  }

  // --- Tag translation operations ---

  void clearTagTranslations() {
    _db.execute('DELETE FROM tag_translation');
  }

  void insertTagTranslation(String namespace, String key, String tagName,
      String fullTagName, String intro,
      {String links = ''}) {
    _db.execute(
      'INSERT OR REPLACE INTO tag_translation (namespace, key, tag_name, full_tag_name, intro, links) VALUES (?, ?, ?, ?, ?, ?)',
      [namespace, key, tagName, fullTagName, intro, links],
    );
  }

  void batchInsertTagTranslations(List<List<String>> rows) {
    _db.execute('BEGIN TRANSACTION');
    try {
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO tag_translation (namespace, key, tag_name, full_tag_name, intro, links) VALUES (?, ?, ?, ?, ?, ?)',
      );
      for (final row in rows) {
        stmt.execute(row);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, dynamic>? getTagTranslation(String namespace, String key) {
    final result = _db.select(
      'SELECT * FROM tag_translation WHERE namespace = ? AND key = ?',
      [namespace, key],
    );
    return result.isEmpty ? null : _rowToMap(result.first);
  }

  List<Map<String, dynamic>> batchGetTagTranslations(
      List<Map<String, String>> tags) {
    final results = <Map<String, dynamic>>[];
    for (final tag in tags) {
      final r = getTagTranslation(tag['namespace'] ?? '', tag['key'] ?? '');
      if (r != null) results.add(r);
    }
    return results;
  }

  static const Map<String, String> _namespaceAliases = {
    'rows': 'rows',
    '分类': 'rows',
    'language': 'language',
    'l': 'language',
    '语言': 'language',
    'artist': 'artist',
    'a': 'artist',
    '作者': 'artist',
    'character': 'character',
    'c': 'character',
    '角色': 'character',
    'female': 'female',
    'f': 'female',
    '女性': 'female',
    'male': 'male',
    'm': 'male',
    '男性': 'male',
    'parody': 'parody',
    'p': 'parody',
    '原作': 'parody',
    'group': 'group',
    'g': 'group',
    '团队': 'group',
    'mixed': 'mixed',
    'x': 'mixed',
    '混合': 'mixed',
    'cosplayer': 'cosplayer',
    'cos': 'cosplayer',
    '角色扮演者': 'cosplayer',
    'reclass': 'reclass',
    'r': 'reclass',
    '重新分类': 'reclass',
    'temp': 'temp',
    '临时': 'temp',
    'other': 'other',
    'o': 'other',
    '其他': 'other',
    'location': 'location',
    'loc': 'location',
    '地点': 'location',
  };

  static const Map<String, double> _namespaceScores = {
    'other': 10,
    'female': 9,
    'male': 8.5,
    'mixed': 8,
    'parody': 3.3,
    'character': 2.8,
    'artist': 2.5,
    'cosplayer': 2.4,
    'group': 2.2,
    'language': 2,
    'location': 1.5,
    'reclass': 1,
    'temp': 0.1,
    'rows': 0,
  };

  List<Map<String, dynamic>> searchTagTranslations(String query,
      {int limit = 20}) {
    final searchList = _parseTagSearchQuery(query);
    if (searchList.isEmpty) {
      return [];
    }

    final results = <String, Map<String, dynamic>>{};
    for (var i = 0; i < searchList.length && results.length < limit; i++) {
      final suffix = searchList.sublist(i);
      final merged = suffix
          .map((e) => e.namespace == null ? e.key : '${e.namespace}:${e.key}')
          .join(' ');
      final colonIndex = merged.indexOf(':');
      final rawNamespace =
          colonIndex == -1 ? null : merged.substring(0, colonIndex);
      final namespace = _normalizeNamespace(rawNamespace);
      final key = colonIndex == -1 ? merged : merged.substring(colonIndex + 1);
      final trimmedKey = key.trim().toLowerCase();
      if (trimmedKey.isEmpty ||
          (trimmedKey.length <= 1 && RegExp(r'^\w+$').hasMatch(trimmedKey))) {
        continue;
      }

      final candidates = _selectTagTranslationCandidates(
        namespace: namespace,
        key: trimmedKey,
        limit: limit * 8,
      );
      candidates.sort((a, b) => _scoreTagTranslation(b, trimmedKey)
          .compareTo(_scoreTagTranslation(a, trimmedKey)));

      for (final row in candidates) {
        final id = '${row['namespace']}:${row['key']}';
        results.putIfAbsent(id, () => row);
        if (results.length >= limit) {
          break;
        }
      }
    }

    return results.values.take(limit).toList();
  }

  List<({String? namespace, String key})> _parseTagSearchQuery(String query) {
    final matches = RegExp(
      r'[-~]?(\S+?):"([^"]+)"?|[-~]?"([^"]+)"?|[-~]?(\S+?):(\S+)|[-~]?(\S+)',
    ).allMatches(query.toLowerCase());
    return matches
        .map((match) => (
              namespace: match.group(1) ?? match.group(4),
              key: match.group(2) ??
                  match.group(3) ??
                  match.group(5) ??
                  match.group(0) ??
                  '',
            ))
        .where((item) => item.key.trim().isNotEmpty)
        .toList();
  }

  String? _normalizeNamespace(String? namespace) {
    if (namespace == null || namespace.isEmpty) {
      return null;
    }
    return _namespaceAliases[namespace.toLowerCase()];
  }

  List<Map<String, dynamic>> _selectTagTranslationCandidates({
    required String? namespace,
    required String key,
    required int limit,
  }) {
    final like = '%$key%';
    final params = <Object>[like, like, like, like];
    var where =
        '(key LIKE ? OR tag_name LIKE ? OR full_tag_name LIKE ? OR intro LIKE ?)';
    if (namespace != null) {
      where = 'namespace = ? AND $where';
      params.insert(0, namespace);
    }
    params.add(limit);
    return _db
        .select(
          'SELECT * FROM tag_translation WHERE $where LIMIT ?',
          params,
        )
        .map(_rowToMap)
        .toList();
  }

  double _scoreTagTranslation(Map<String, dynamic> row, String key) {
    final namespace = row['namespace']?.toString() ?? '';
    final namespaceScore = _namespaceScores[namespace] ?? 1;
    final rawKey = row['key']?.toString().toLowerCase() ?? '';
    final tagName = row['tag_name']?.toString().toLowerCase() ?? '';
    final intro = row['intro']?.toString().toLowerCase() ?? '';
    var score = 0.0;

    final keyIndex = rawKey.indexOf(key);
    if (keyIndex != -1 && rawKey.isNotEmpty) {
      score += namespaceScore *
          (key.length + 1) /
          rawKey.length *
          (keyIndex == 0 ? 2 : 1);
    }

    final tagNameIndex = tagName.indexOf(key);
    if (tagNameIndex != -1 && tagName.isNotEmpty) {
      score += namespaceScore *
          (key.length + 1) /
          tagName.length *
          (tagNameIndex == 0 ? 2 : 1);
    }

    if (intro.contains(key) && intro.isNotEmpty) {
      score += namespaceScore * (key.length + 1) / intro.length * 0.5;
    }

    return score;
  }

  int tagTranslationCount() {
    final result = _db.select('SELECT COUNT(*) as cnt FROM tag_translation');
    return result.first['cnt'] as int;
  }

  int tagTranslationLinksCount() {
    final result = _db.select(
        "SELECT COUNT(*) as cnt FROM tag_translation WHERE links <> ''");
    return result.first['cnt'] as int;
  }

  // --- Quick search operations ---

  List<Map<String, dynamic>> selectAllQuickSearches() {
    return _db
        .select('SELECT * FROM quick_search ORDER BY sort_order ASC, name ASC')
        .map(_rowToMap)
        .toList();
  }

  void upsertQuickSearch(String name, String config, {int sortOrder = 0}) {
    _db.execute(
      'INSERT OR REPLACE INTO quick_search (name, config, sort_order) VALUES (?, ?, ?)',
      [name, config, sortOrder],
    );
  }

  void deleteQuickSearch(String name) {
    _db.execute('DELETE FROM quick_search WHERE name = ?', [name]);
  }

  // --- Block rule operations ---

  List<Map<String, dynamic>> selectAllBlockRules() {
    return _db
        .select('SELECT * FROM block_rule ORDER BY id ASC')
        .map(_rowToMap)
        .toList();
  }

  int insertBlockRule(Map<String, dynamic> data) {
    _db.execute('''
      INSERT INTO block_rule (group_id, target, attribute, pattern, expression)
      VALUES (?, ?, ?, ?, ?)
    ''', [
      data['group_id'] ?? '',
      data['target'] ?? 'gallery',
      data['attribute'] ?? 'title',
      data['pattern'] ?? 'like',
      data['expression'] ?? '',
    ]);
    return _db.lastInsertRowId;
  }

  void updateBlockRule(int id, Map<String, dynamic> data) {
    _db.execute('''
      UPDATE block_rule SET group_id = ?, target = ?, attribute = ?, pattern = ?, expression = ?
      WHERE id = ?
    ''', [
      data['group_id'] ?? '',
      data['target'] ?? 'gallery',
      data['attribute'] ?? 'title',
      data['pattern'] ?? 'like',
      data['expression'] ?? '',
      id,
    ]);
  }

  void deleteBlockRule(int id) {
    _db.execute('DELETE FROM block_rule WHERE id = ?', [id]);
  }

  void deleteBlockRulesByGroupId(String groupId) {
    _db.execute('DELETE FROM block_rule WHERE group_id = ?', [groupId]);
  }

  // --- Cache operations ---

  void cleanExpiredCache() {
    _db.execute('DELETE FROM dio_cache WHERE expire_date < ?',
        [DateTime.now().toIso8601String()]);
  }

  Map<String, dynamic> _rowToMap(Row row) {
    final map = <String, dynamic>{};
    for (final col in row.keys) {
      map[col] = row[col];
    }
    return map;
  }

  void dispose() {
    _db.dispose();
  }
}

final ServerDatabase db = ServerDatabase();
