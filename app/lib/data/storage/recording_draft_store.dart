import 'dart:convert';
import 'dart:io';

import '../../domain/models/active_recording.dart';
import '../../domain/models/json_values.dart';
import 'atomic_json_file.dart';

class RecordingDraftStore {
  RecordingDraftStore(Directory documents)
    : _storage = AtomicJsonFile(
        File('${documents.path}/smart_walker_recording.json'),
      );

  final AtomicJsonFile _storage;

  Future<RecordingDraft?> load() async {
    if (!await _storage.file.exists()) return null;
    return RecordingDraft.fromJson(
      jsonObject(jsonDecode(await _storage.file.readAsString())),
    );
  }

  Future<void> save(RecordingDraft draft) => _storage.write(draft.toJson());
  Future<void> clear() => _storage.delete();
}
