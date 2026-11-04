import 'dart:io';

import '../platform/windows_native_services.dart';

Future<void> replaceFile(File source, String destination) async {
  if (Platform.isWindows) {
    await WindowsNativeServices.replaceFile(source.path, destination);
  } else {
    await source.rename(destination);
  }
}
