import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';

bool get isMacOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get isWindowsApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
bool get isDesktopApp => isMacOSApp || isWindowsApp;

FThemeData appTheme({required bool dark}) {
  final theme = dark ? FTheme.neutral.dark : FTheme.neutral.light;
  return isDesktopApp ? theme.desktop : theme.touch;
}
