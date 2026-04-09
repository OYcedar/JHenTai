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
      final outputStream = OutputFileStream('$extractPath/${_fileNameWithoutExtension(archivePath)}');
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
  return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}.contains(ext);
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
