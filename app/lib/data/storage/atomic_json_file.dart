import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Serializes writes and replaces a file only after its new contents are flushed.
class AtomicJsonFile {
  AtomicJsonFile(this.file);

  final File file;
  Future<void> _pending = Future.value();

  Future<T> serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> write(Object value, {bool backup = false}) =>
      serialize(() async {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          const JsonEncoder.withIndent('  ').convert(value),
          flush: true,
        );
        if (backup && await file.exists()) {
          final backupTemporary = File('${file.path}.bak.tmp');
          await file.copy(backupTemporary.path);
          await backupTemporary.rename('${file.path}.bak');
        }
        await temporary.rename(file.path);
      });

  Future<void> delete() => serialize(() async {
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  });
}
