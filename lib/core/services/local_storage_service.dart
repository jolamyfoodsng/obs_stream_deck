import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService(this._preferences);

  final SharedPreferences _preferences;

  String? getString(String key) => _preferences.getString(key);

  bool? getBool(String key) => _preferences.getBool(key);

  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }

  Future<bool> setBool(String key, bool value) {
    return _preferences.setBool(key, value);
  }

  Future<bool> setJson(String key, Object value) {
    return _preferences.setString(key, jsonEncode(value));
  }

  Future<bool> remove(String key) {
    return _preferences.remove(key);
  }

  Map<String, dynamic>? getJsonMap(String key) {
    final raw = _preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  List<Map<String, dynamic>> getJsonList(String key) {
    final raw = _preferences.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
  }
}
