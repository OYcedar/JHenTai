import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

Future<bool> extractZipArchive(String archivePath, String extractPath) async {
  return Isolate.run(() {
    InputFileStream? inputStream;
    try {
      inputStream = InputFileStream(archivePath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      final canonicalBase = p.canonicalize(extractPath);

      for (final file in archive.files) {
        final filePath = p.join(extractPath, file.name);
        final canonicalPath = p.canonicalize(filePath);

        if (!canonicalPath.startsWith('$canonicalBase/') &&
            canonicalPath != canonicalBase) {
          continue;
        }

        if (file.isFile) {
          final outFile = File(canonicalPath);
          outFile.parent.createSync(recursive: true);
          final out = outFile.openSync(mode: FileMode.write);
          out.writeFromSync(file.content as List<int>);
          out.closeSync();
        } else {
          Directory(canonicalPath).createSync(recursive: true);
        }
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      inputStream?.close();
    }
  });
}

Future<bool> extractGZipArchive(String archivePath, String extractPath) async {
  return Isolate.run(() {
    try {
      final inputStream = InputFileStream(archivePath);
      final bytes = GZipDecoder().decodeBuffer(inputStream);
      final outputStream = OutputFileStream(
          '$extractPath/${_fileNameWithoutExtension(archivePath)}');
      outputStream.writeBytes(Uint8List.fromList(bytes.toList()));
      outputStream.close();
      inputStream.close();
      return true;
    } catch (e) {
      return false;
    }
  });
}

bool isImageFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}
      .contains(ext);
}

/// 归档文件夹标题最大长度，与旧版移动端一致。
const int archiveMaxTitleLength = 80;

/// 画廊文件夹标题最大长度，与旧版移动端一致。
const int galleryMaxTitleLength = 85;

/// 把原始标题清洗成可安全用作文件夹名的形式：
/// 替换路径非法字符为空格，超过 [maxLength] 时截断。
String sanitizeFolderTitle(String rawTitle,
    {int maxLength = archiveMaxTitleLength}) {
  var title = rawTitle.replaceAll(RegExp(r'[/|?,:*"<>\\.]'), ' ').trim();
  if (title.length > maxLength) {
    title = title.substring(0, maxLength).trim();
  }
  return title;
}

/// 归档解压后的文件夹名，格式与旧版一致：`Archive - <gid> - <标题>`。
String computeArchiveDirName(int gid, String title) =>
    'Archive - $gid - ${sanitizeFolderTitle(title)}';

/// 归档解压后的完整目录路径。
String archiveDirPath(String downloadDir, int gid, String title) =>
    p.join(downloadDir, computeArchiveDirName(gid, title));

/// 按 gid 查找已解压的归档目录：
/// 依次匹配 Web 根目录、旧版数字目录和 iPad 导出的嵌套命名目录。
String? resolveArchiveDir(String downloadDir, int gid) {
  final root = Directory(downloadDir);
  final prefix = 'Archive - $gid - ';
  if (root.existsSync()) {
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path).startsWith(prefix)) {
          return entity.path;
        }
      }
    } catch (_) {
      // 目录扫描失败时按未找到处理，回退旧格式。
    }
  }
  final legacy = p.join(downloadDir, 'archive', '$gid');
  if (Directory(legacy).existsSync()) return legacy;

  final appArchiveRoot = Directory(p.join(downloadDir, 'archive'));
  if (appArchiveRoot.existsSync()) {
    try {
      for (final entity in appArchiveRoot.listSync(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path).startsWith(prefix)) {
          return entity.path;
        }
      }
    } catch (_) {
      // 目录扫描失败时按未找到处理。
    }
  }
  return null;
}

/// 从 `Archive - <gid> - <标题>` 形式的目录名中解析 gid。
int? gidFromArchiveDirName(String dirPath) {
  final name = p.basename(dirPath);
  final match = RegExp(r'^Archive - (\d+) - ').firstMatch(name);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// 画廊下载文件夹名，格式与旧版一致：`<gid> - <标题>`。
String computeGalleryDirName(int gid, String title) =>
    '$gid - ${sanitizeFolderTitle(title, maxLength: galleryMaxTitleLength)}';

/// 画廊下载的完整目录路径。
String galleryDirPath(String downloadDir, int gid, String title) =>
    p.join(downloadDir, computeGalleryDirName(gid, title));

/// 按 gid 查找画廊下载目录：
/// 优先匹配新格式 `<gid> - <标题>`，回退旧格式 `gallery/<gid>`。
String? resolveGalleryDir(String downloadDir, int gid) {
  final root = Directory(downloadDir);
  if (root.existsSync()) {
    final prefix = '$gid - ';
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path).startsWith(prefix)) {
          return entity.path;
        }
      }
    } catch (_) {
      // 目录扫描失败时按未找到处理，回退旧格式。
    }
  }
  final legacy = p.join(downloadDir, 'gallery', '$gid');
  return Directory(legacy).existsSync() ? legacy : null;
}

int naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)|(\D+)');
  final aMatches = regExp.allMatches(a).toList();
  final bMatches = regExp.allMatches(b).toList();
  for (int i = 0; i < aMatches.length && i < bMatches.length; i++) {
    final aStr = aMatches[i].group(0)!;
    final bStr = bMatches[i].group(0)!;
    final aNum = int.tryParse(aStr);
    final bNum = int.tryParse(bStr);
    int cmp;
    if (aNum != null && bNum != null) {
      cmp = aNum.compareTo(bNum);
    } else {
      cmp = aStr.compareTo(bStr);
    }
    if (cmp != 0) return cmp;
  }
  return a.length.compareTo(b.length);
}

String _fileNameWithoutExtension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dotIndex = name.lastIndexOf('.');
  return dotIndex > 0 ? name.substring(0, dotIndex) : name;
}
