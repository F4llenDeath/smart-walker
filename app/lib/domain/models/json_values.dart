Map<String, dynamic> jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

String jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid $key.');
  }
  return value;
}

double jsonNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Missing or invalid $key.');
  }
  return value.toDouble();
}

DateTime jsonDate(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(jsonString(json, key));
  if (value == null) throw FormatException('Invalid $key timestamp.');
  return value.toUtc();
}

List<dynamic> jsonList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List<dynamic>) throw FormatException('Invalid $key list.');
  return value;
}
