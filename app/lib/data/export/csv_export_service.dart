import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/trial.dart';
import '../platform/windows_native_services.dart';
import '../storage/replace_file.dart';

class CsvExportService {
  /// Returns the saved Windows path, or null for cancellation/platform sharing.
  Future<String?> export(Trial trial, {Rect? origin}) async {
    if (Platform.isWindows) {
      final destination = await WindowsNativeServices.chooseCsvPath(
        trial.csvFilename,
      );
      if (destination == null) return null;
      // Stage alongside the destination so replacement stays on one volume and
      // an existing CSV remains intact if writing the new data fails.
      final temporary = File(
        '${File(destination).parent.path}/.smart-walker-${const Uuid().v4()}.tmp',
      );
      try {
        await temporary.writeAsString(trial.toCsv(), flush: true);
        await replaceFile(temporary, destination);
      } finally {
        try {
          if (await temporary.exists()) {
            await temporary.delete();
          }
        } on FileSystemException {
          // Do not mask the export result with a best-effort cleanup failure.
        }
      }
      return destination;
    }
    if (origin == null) throw ArgumentError.notNull('origin');
    final temporary = await getTemporaryDirectory();
    final directory = Directory('${temporary.path}/trial_exports');
    await directory.create(recursive: true);
    // Never remove a just-shared file before the receiving application reads it.
    await for (final entry in directory.list()) {
      if (entry is Directory &&
          DateTime.now().difference((await entry.stat()).modified).inDays > 7) {
        await entry.delete(recursive: true);
      }
    }
    final exportDirectory = Directory(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}',
    );
    await exportDirectory.create();
    final file = File('${exportDirectory.path}/${trial.csvFilename}');
    await file.writeAsString(trial.toCsv(), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Smart Walker Trial Data',
        sharePositionOrigin: origin,
      ),
    );
    return null;
  }
}
