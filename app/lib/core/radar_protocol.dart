import 'dart:math';
import 'dart:typed_data';

import '../domain/models/radar_frame.dart';

/// SW v2, ordered <=20-byte notifications; see AGENTS.md for the wire layout.
/// One bounded in-flight frame, no partial/replayed frame can refresh telemetry.
class RadarFrameDecoder {
  static const maxPoints = 128;
  static const maxBytes = 24 + 16 * maxPoints;
  static const assemblyTimeoutMilliseconds = 750;
  Uint8List? _body;
  int _sequence = -1;
  int _nextChunk = 0;
  int _started = 0;
  int? _session;
  int? _lastNumber;
  int? _lastAcquired;
  int? _minimumClockOffset;

  void reset() {
    _body = null;
    _sequence = -1;
    _nextChunk = 0;
    _session = null;
    _lastNumber = null;
    _lastAcquired = null;
    _minimumClockOffset = null;
  }

  RadarFrame? add(List<int> bytes, int nowMilliseconds) {
    if (bytes.length < 9 ||
        bytes.length > 20 ||
        bytes.any((byte) => byte < 0 || byte > 255) ||
        bytes[0] != 0x53 ||
        bytes[1] != 0x57 ||
        bytes[2] != 2) {
      _body = null;
      return null;
    }
    final chunk = ByteData.sublistView(Uint8List.fromList(bytes));
    final index = bytes[3];
    final sequence = chunk.getUint16(4, Endian.little);
    final length = chunk.getUint16(6, Endian.little);
    final offset = index * 12;
    if (length < 24 ||
        length > maxBytes ||
        offset >= length ||
        bytes.length != 8 + min(12, length - offset)) {
      _body = null;
      return null;
    }
    if (index == 0) {
      if (_body != null && sequence == _sequence) {
        _body = null;
        return null;
      }
      _body = Uint8List(length);
      _sequence = sequence;
      _nextChunk = 0;
      _started = nowMilliseconds;
    }
    final body = _body;
    if (body == null ||
        sequence != _sequence ||
        length != body.length ||
        index != _nextChunk ||
        nowMilliseconds - _started > assemblyTimeoutMilliseconds) {
      _body = null;
      return null;
    }
    body.setRange(offset, offset + bytes.length - 8, bytes, 8);
    _nextChunk++;
    if (offset + bytes.length - 8 != length) return null;
    _body = null;
    final data = ByteData.sublistView(body);
    final session = data.getUint32(0, Endian.little);
    final number = data.getUint32(4, Endian.little);
    final cycles = data.getUint32(8, Endian.little);
    final acquired = data.getUint64(12, Endian.little);
    final count = data.getUint16(20, Endian.little);
    final flags = data.getUint16(22, Endian.little);
    if (count > maxPoints ||
        acquired < 0 ||
        acquired > 0x1fffffffffffff ||
        length != 24 + count * 16 ||
        flags > 1 ||
        (flags == 1 && count != 0)) {
      return null;
    }
    final points = <RadarPoint>[];
    for (var index = 0; index < count; index++) {
      final values = [
        for (var field = 0; field < 4; field++)
          data.getFloat32(24 + index * 16 + field * 4, Endian.little),
      ];
      if (values.any((value) => !value.isFinite || value.abs() > 1000)) {
        return null;
      }
      points.add(RadarPoint(values[0], values[1], values[2], values[3]));
    }
    if (_session == session && _lastNumber != null) {
      final advance = (number - _lastNumber!) & 0xffffffff;
      if (advance == 0) return null;
      if (advance >= 0x80000000 || acquired < _lastAcquired!) {
        throw const FormatException('Radar frame counter/clock restarted.');
      }
    }
    if (_session != session) _minimumClockOffset = null;
    final clockOffset = nowMilliseconds - acquired;
    final minimum = min(_minimumClockOffset ?? clockOffset, clockOffset);
    // Relative clocks need no wall-clock synchronization. Do not replay a backlog.
    // Initial transport latency is unknowable; subsequent excess delay is bounded.
    if (clockOffset - minimum > 500) return null;
    _minimumClockOffset = minimum;
    _session = session;
    _lastNumber = number;
    _lastAcquired = acquired;
    return RadarFrame(
      session: session,
      number: number,
      cpuCycles: cycles,
      acquiredMilliseconds: acquired,
      receivedMilliseconds: nowMilliseconds,
      points: points,
      overflow: flags == 1,
    );
  }
}
