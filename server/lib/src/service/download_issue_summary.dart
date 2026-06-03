class DownloadIssueSummary {
  static const galleryFailedStatus = 4;
  static const archiveFailedStatus = 8;

  static Map<String, dynamic> build({
    required Iterable<Map<String, dynamic>> galleryTasks,
    required Iterable<Map<String, dynamic>> archiveTasks,
  }) {
    final failedTasks = <Map<String, dynamic>>[];
    for (final task in galleryTasks) {
      if (task['status'] == galleryFailedStatus) {
        failedTasks.add(_taskIssue('gallery', task));
      }
    }
    for (final task in archiveTasks) {
      if (task['status'] == archiveFailedStatus) {
        failedTasks.add(_taskIssue('archive', task));
      }
    }

    final groupsByCategory = <String, List<Map<String, dynamic>>>{};
    for (final task in failedTasks) {
      groupsByCategory
          .putIfAbsent(task['category'] as String, () => [])
          .add(task);
    }
    final groups = groupsByCategory.entries.map((entry) {
      final actions = _actionsForCategory(entry.key);
      return {
        'category': entry.key,
        'titleKey': 'downloads.issue_${entry.key}',
        'detailKey': 'downloads.issue_${entry.key}_hint',
        'count': entry.value.length,
        'sampleTasks': entry.value.take(5).toList(),
        'actions': actions,
      };
    }).toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    final galleryFailed =
        failedTasks.where((task) => task['type'] == 'gallery').length;
    final archiveFailed =
        failedTasks.where((task) => task['type'] == 'archive').length;
    return {
      'status': failedTasks.isEmpty ? 'ok' : 'warn',
      'summary': {
        'failedTotal': failedTasks.length,
        'galleryFailed': galleryFailed,
        'archiveFailed': archiveFailed,
        'groupCount': groups.length,
      },
      'groups': groups,
      'tasks': failedTasks.take(50).toList(),
      'actions': [
        if (galleryFailed > 0) 'retry_failed_gallery',
        if (archiveFailed > 0) 'retry_failed_archive',
        if (archiveFailed > 0) 'reunlock_failed_archive',
        if (failedTasks.isNotEmpty) 'open_troubleshooting',
        if (failedTasks.isNotEmpty) 'open_network',
      ],
    };
  }

  static Map<String, dynamic> _taskIssue(
    String type,
    Map<String, dynamic> task,
  ) {
    final category = _classify(type, task);
    return {
      'type': type,
      'gid': task['gid'],
      'title': task['title']?.toString() ?? '',
      'category': category,
      'categoryKey': 'downloads.issue_$category',
      'error': task['lastError']?.toString() ?? '',
      'action': type == 'gallery' ? 'retry_gallery' : 'retry_archive',
    };
  }

  static String _classify(String type, Map<String, dynamic> task) {
    final text = [
      task['lastError'],
      task['errorCategory'],
      task['title'],
      task['galleryUrl'],
      task['archivePageUrl'],
      task['downloadPageUrl'],
      task['downloadUrl'],
    ].whereType<Object>().join('\n').toLowerCase();
    if (text.contains('509') || text.contains('image limit')) {
      return 'quota';
    }
    if (text.contains('hath.network') ||
        text.contains('proxy') ||
        text.contains('handshake') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timed out') ||
        text.contains('timeout')) {
      return 'hath';
    }
    if (type == 'gallery' &&
        (text.contains('image page') ||
            text.contains('download image') ||
            text.contains('no image pages') ||
            text.contains('failed to download image'))) {
      return 'imagePage';
    }
    if (type == 'archive' &&
        (text.contains('unlock') || text.contains('509'))) {
      return 'archiveUnlock';
    }
    if (type == 'archive' &&
        (text.contains('archive') ||
            text.contains('parse archive') ||
            text.contains('extract') ||
            text.contains('zip'))) {
      return 'archiveDownload';
    }
    if (text.contains('no such file') ||
        text.contains('file') ||
        text.contains('directory')) {
      return 'localFile';
    }
    return 'unknown';
  }

  static List<String> _actionsForCategory(String category) {
    return switch (category) {
      'hath' => ['probe_hath', 'open_network', 'retry_failed'],
      'quota' => ['open_eh_status', 'retry_failed'],
      'archiveUnlock' => ['reunlock_failed_archive', 'open_network'],
      'archiveDownload' => ['retry_failed_archive', 'reunlock_failed_archive'],
      'imagePage' => ['retry_failed_gallery', 'open_troubleshooting'],
      'localFile' => ['retry_failed', 'open_logs'],
      _ => ['retry_failed', 'open_troubleshooting'],
    };
  }
}
