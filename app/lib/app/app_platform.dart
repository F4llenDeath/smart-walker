import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';

bool get isMacOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

FThemeData appTheme({required bool dark}) {
  final theme = dark ? FTheme.neutral.dark : FTheme.neutral.light;
  return isMacOSApp ? theme.desktop : theme.touch;
}
