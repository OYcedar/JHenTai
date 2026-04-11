import 'dart:io';

/// Write one line to stderr and flush so Docker / Unraid capture matches `docker logs`
/// (same idea as printing the API token at startup).
void jhStderrLine(String line) {
  stderr.writeln(line);
  try {
    stderr.flush();
  } catch (_) {}
}
