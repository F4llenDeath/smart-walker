import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/trial.dart';

class CsvExportService {
  Future<void> share(Trial trial, Rect origin) async {
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
  }
}
