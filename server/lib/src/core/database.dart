import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

class ServerDatabase {
  late Database _db;

  Database get raw => _db;

  Future<void> init(String dbPath) async {
    _db = sqlite3.open(dbPath);
    _createTables();
    log.info('Database opened at $dbPath');
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
        group_name TEXT NOT NULL DEFAULT 'default'
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
        total_bytes INTEGER NOT NULL DEFAULT 0
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

    _db.execute('CREATE INDEX IF NOT EXISTS idx_cache_expire ON dio_cache(expire_date)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_cache_url ON dio_cache(url)');
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
    return _db.select('SELECT * FROM gallery_download ORDER BY insert_time DESC')
        .map(_rowToMap)
        .toList();
  }

  void insertGalleryDownload(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO gallery_download 
      (gid, token, title, category, page_count, gallery_url, cover_url, uploader, publish_time, download_status, insert_time, completed_count, group_name)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'], data['token'], data['title'], data['category'],
      data['page_count'], data['gallery_url'], data['cover_url'] ?? '',
      data['uploader'] ?? '', data['publish_time'], data['download_status'] ?? 0,
      data['insert_time'] ?? DateTime.now().toIso8601String(),
      data['completed_count'] ?? 0, data['group_name'] ?? 'default',
    ]);
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
    return _db.select('SELECT * FROM gallery_image WHERE gid = ? ORDER BY serial_no', [gid])
        .map(_rowToMap)
        .toList();
  }

  void upsertGalleryImage(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO gallery_image
      (gid, serial_no, url, image_url, image_hash, path, download_status, image_page_url)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'], data['serial_no'], data['url'] ?? '',
      data['image_url'] ?? '', data['image_hash'] ?? '',
      data['path'] ?? '', data['download_status'] ?? 0,
      data['image_page_url'] ?? '',
    ]);
  }

  // --- Archive download operations ---

  List<Map<String, dynamic>> selectAllArchiveDownloads() {
    return _db.select('SELECT * FROM archive_download ORDER BY insert_time DESC')
        .map(_rowToMap)
        .toList();
  }

  void insertArchiveDownload(Map<String, dynamic> data) {
    _db.execute('''
      INSERT OR REPLACE INTO archive_download
      (gid, token, title, category, page_count, gallery_url, cover_url, uploader, size,
       publish_time, archive_status, archive_page_url, download_page_url, download_url,
       is_original, insert_time, group_name, downloaded_bytes, total_bytes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      data['gid'], data['token'], data['title'], data['category'],
      data['page_count'], data['gallery_url'], data['cover_url'] ?? '',
      data['uploader'] ?? '', data['size'] ?? '', data['publish_time'],
      data['archive_status'] ?? 0, data['archive_page_url'] ?? '',
      data['download_page_url'] ?? '', data['download_url'] ?? '',
      data['is_original'] ?? 0, data['insert_time'] ?? DateTime.now().toIso8601String(),
      data['group_name'] ?? 'default', data['downloaded_bytes'] ?? 0,
      data['total_bytes'] ?? 0,
    ]);
  }

  void updateArchiveDownloadStatus(int gid, int status, {int? downloadedBytes, int? totalBytes}) {
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
    _db.execute('UPDATE archive_download SET ${updates.join(', ')} WHERE gid = ?', params);
  }

  void updateArchiveDownloadUrls(int gid, {String? downloadPageUrl, String? downloadUrl}) {
    if (downloadPageUrl != null) {
      _db.execute('UPDATE archive_download SET download_page_url = ? WHERE gid = ?', [downloadPageUrl, gid]);
    }
    if (downloadUrl != null) {
      _db.execute('UPDATE archive_download SET download_url = ? WHERE gid = ?', [downloadUrl, gid]);
    }
  }

  void deleteArchiveDownload(int gid) {
    _db.execute('DELETE FROM archive_download WHERE gid = ?', [gid]);
  }

  // --- Cache operations ---

  void cleanExpiredCache() {
    _db.execute('DELETE FROM dio_cache WHERE expire_date < ?', [DateTime.now().toIso8601String()]);
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
