import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService(this._preferences);

  final SharedPreferences _preferences;

  String? getString(String key) {
    final value = _preferences.get(key);
    if (value is String) return value;
    if (value == null) return null;
    return '$value';
  }

  List<String>? getStringListOrNull(String key) {
    final value = _preferences.get(key);
    if (value is List<String>) return List<String>.from(value);
    if (value is List) return value.whereType<String>().toList(growable: false);
    return null;
  }

  int? getInt(String key) {
    final value = _preferences.get(key);
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? getBool(String key) {
    final value = _preferences.get(key);
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }

  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }

  Future<bool> setStringList(String key, List<String> value) {
    return _preferences.setStringList(key, value);
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
