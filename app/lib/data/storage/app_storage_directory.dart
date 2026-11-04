import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../platform/windows_native_services.dart';

Future<Directory> appStorageDirectory() async {
  if (!Platform.isWindows) return getApplicationDocumentsDirectory();
  // The host acquires an exclusive lock here before starting the Dart engine.
  final directory = Directory(await WindowsNativeServices.dataDirectory());
  await directory.create(recursive: true);
  return directory;
}
