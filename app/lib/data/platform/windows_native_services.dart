import 'package:flutter/services.dart';

/// Only called on Windows. Other platforms retain their existing integrations.
abstract final class WindowsNativeServices {
  static const _channel = MethodChannel('com.xichengyang.smart_walker/windows');

  static Future<String> dataDirectory() async {
    final path = await _channel.invokeMethod<String>('dataDirectory');
    if (path == null || path.isEmpty) {
      throw StateError(
        'Windows did not provide an application data directory.',
      );
    }
    return path;
  }

  /// A null result is normal user cancellation, not an export failure.
  static Future<String?> chooseCsvPath(String filename) =>
      _channel.invokeMethod<String>('chooseCsvPath', {'filename': filename});

  /// Source and destination must be on the same volume. Never deletes first.
  static Future<void> replaceFile(String source, String destination) =>
      _channel.invokeMethod<void>('replaceFile', {
        'source': source,
        'destination': destination,
      });
}
