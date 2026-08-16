import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:jhentai_server/src/utils/archive_util.dart';

void main() {
  late Directory downloadDir;

  setUp(() {
    downloadDir = Directory.systemTemp.createTempSync('jhentai_archive_test_');
  });

  tearDown(() {
    if (downloadDir.existsSync()) {
      downloadDir.deleteSync(recursive: true);
    }
  });

  test('resolves Web archive directory from download root', () {
    final expected = Directory(
      p.join(downloadDir.path, 'Archive - 2310525 - Example'),
    )..createSync();

    expect(
      p.equals(resolveArchiveDir(downloadDir.path, 2310525)!, expected.path),
      isTrue,
    );
  });

  test('resolves legacy numeric archive directory', () {
    final expected = Directory(
      p.join(downloadDir.path, 'archive', '2310525'),
    )..createSync(recursive: true);

    expect(
      p.equals(resolveArchiveDir(downloadDir.path, 2310525)!, expected.path),
      isTrue,
    );
  });

  test('resolves iPad named archive directory nested under archive', () {
    final expected = Directory(
      p.join(
        downloadDir.path,
        'archive',
        'Archive - 2310525 - Example',
      ),
    )..createSync(recursive: true);

    expect(
      p.equals(resolveArchiveDir(downloadDir.path, 2310525)!, expected.path),
      isTrue,
    );
  });
}
