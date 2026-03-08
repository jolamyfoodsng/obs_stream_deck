import 'dart:convert';

import '../../core/constants/storage_keys.dart';
import '../../data/models/controller_page_model.dart';
import '../../data/models/macro_definition_model.dart';
import '../../data/models/obs_connection_config_model.dart';
import '../../domain/entities/layout_preset.dart';
import '../../domain/repositories/connection_repository.dart';
import '../../domain/repositories/controller_repository.dart';
import '../../domain/repositories/macro_repository.dart';
import 'local_storage_service.dart';

class LayoutPresetService {
  LayoutPresetService({
    required ControllerRepository controllerRepository,
    required MacroRepository macroRepository,
    required ConnectionRepository connectionRepository,
    required LocalStorageService localStorage,
  })  : _controllerRepository = controllerRepository,
        _macroRepository = macroRepository,
        _connectionRepository = connectionRepository,
        _localStorage = localStorage;

  final ControllerRepository _controllerRepository;
  final MacroRepository _macroRepository;
  final ConnectionRepository _connectionRepository;
  final LocalStorageService _localStorage;

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  Future<String> exportCurrentLayoutJson() async {
    final payload = await _buildExportPayload();
    return _jsonEncoder.convert(payload);
  }

  Future<List<LayoutPreset>> loadPresets() async {
    final list = _localStorage.getJsonList(StorageKeys.layoutPresets);
    return list
        .map(
          (item) => LayoutPreset(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? 'Untitled preset',
            createdAtIso: item['createdAt'] as String? ?? '',
          ),
        )
        .where((preset) => preset.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveCurrentAsPreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Preset name is required.');
    }

    final payload = await _buildExportPayload();
    final presets = _localStorage.getJsonList(StorageKeys.layoutPresets);
    final id = 'preset_${DateTime.now().microsecondsSinceEpoch}';
    final createdAt = DateTime.now().toIso8601String();

    presets.add(
      <String, dynamic>{
        'id': id,
        'name': trimmed,
        'createdAt': createdAt,
        'data': payload,
      },
    );

    await _localStorage.setJson(StorageKeys.layoutPresets, presets);
  }

  Future<void> deletePreset(String presetId) async {
    final presets = _localStorage.getJsonList(StorageKeys.layoutPresets);
    final filtered = presets.where((item) => item['id'] != presetId).toList();
    await _localStorage.setJson(StorageKeys.layoutPresets, filtered);
  }

  Future<void> applyPreset(String presetId) async {
    final presets = _localStorage.getJsonList(StorageKeys.layoutPresets);
    final selected = presets
        .where((item) => item['id'] == presetId)
        .cast<Map<String, dynamic>>()
        .firstOrNull;
    if (selected == null) {
      throw const FormatException('Preset not found.');
    }
    final data = selected['data'];
    if (data is! Map) {
      throw const FormatException('Preset data is invalid.');
    }
    await _applyPayload(data.cast<String, dynamic>());
  }

  Future<void> importLayoutJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid import JSON.');
    }
    await _applyPayload(decoded.cast<String, dynamic>());
  }

  Future<Map<String, dynamic>> _buildExportPayload() async {
    final pages = await _controllerRepository.loadPages();
    final macros = await _macroRepository.loadMacros();
    final connection = await _connectionRepository.loadConfig();
    final volunteerMode = _localStorage.getBool(StorageKeys.volunteerMode);
    final scenePreviewMode =
        _localStorage.getString(StorageKeys.scenePreviewMode);

    return <String, dynamic>{
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'pages': pages.map(ControllerPageModel.toJson).toList(),
      'macros': macros.map(MacroDefinitionModel.toJson).toList(),
      'settings': <String, dynamic>{
        'volunteerMode': volunteerMode ?? false,
        'scenePreviewMode': scenePreviewMode ?? 'off',
        'connection': connection == null
            ? null
            : ObsConnectionConfigModel.toJson(connection),
      },
    };
  }

  Future<void> _applyPayload(Map<String, dynamic> payload) async {
    final pagesRaw = payload['pages'];
    if (pagesRaw is! List) {
      throw const FormatException('Import JSON is missing pages.');
    }

    final macrosRaw = payload['macros'];
    if (macrosRaw is! List) {
      throw const FormatException('Import JSON is missing macros.');
    }

    final pages = pagesRaw
        .whereType<Map>()
        .map((item) =>
            ControllerPageModel.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
    final macros = macrosRaw
        .whereType<Map>()
        .map((item) =>
            MacroDefinitionModel.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);

    await _controllerRepository.savePages(pages);
    await _macroRepository.saveMacros(macros);

    final settings = payload['settings'];
    if (settings is Map) {
      final map = settings.cast<String, dynamic>();

      final volunteer = map['volunteerMode'];
      if (volunteer is bool) {
        await _localStorage.setBool(StorageKeys.volunteerMode, volunteer);
      }

      final previewMode = map['scenePreviewMode'];
      if (previewMode is String && previewMode.trim().isNotEmpty) {
        await _localStorage.setString(
          StorageKeys.scenePreviewMode,
          previewMode.trim(),
        );
      }

      final connectionRaw = map['connection'];
      if (connectionRaw is Map) {
        final config = ObsConnectionConfigModel.fromJson(
            connectionRaw.cast<String, dynamic>());
        await _connectionRepository.saveConfig(config);
      }
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
