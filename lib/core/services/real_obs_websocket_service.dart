import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/audio_source.dart';
import '../../domain/entities/button_action.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/entities/recording_status.dart';
import '../../domain/entities/scene_item.dart';
import '../../domain/entities/source_item.dart';
import '../../domain/entities/stream_status.dart';
import 'obs_stats_service.dart';
import 'obs_websocket_service.dart';

class RealObsWebSocketService implements ObsWebSocketService {
  RealObsWebSocketService() {
    _statsService = ObsStatsService(
      request: _requestStatsPayload,
      onSnapshot: _applyStatsSnapshot,
    );
  }

  static const int _eventSubscriptions = 1 | // General
      4 | // Scenes
      8 | // Inputs
      64 | // Outputs
      128 | // Scene items
      1024 | // UI
      65536; // Input volume meters
  static const double _meterFloorDb = -60;
  static const double _microphoneSilenceThresholdDb = -55;
  static const Duration _microphoneSilenceWindow = Duration(seconds: 5);

  final _connectionController = StreamController<ConnectionStatus>.broadcast();
  final _streamController = StreamController<StreamStatus>.broadcast();
  final _recordingController = StreamController<RecordingStatus>.broadcast();
  final _sceneController = StreamController<String?>.broadcast();
  final _scenesController = StreamController<List<SceneItem>>.broadcast();
  final _audioController = StreamController<List<AudioSource>>.broadcast();
  final _sourcesController = StreamController<List<SourceItem>>.broadcast();
  final _stateController = StreamController<ObsRuntimeState>.broadcast();

  ObsRuntimeState _state = ObsRuntimeState.initial();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  ObsConnectionConfig? _lastConfig;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};

  Completer<void>? _identifyCompleter;
  bool _identified = false;
  bool _manualDisconnect = false;
  bool _disposed = false;
  bool _audioMetersAvailable = false;
  int _requestCounter = 0;
  late final ObsStatsService _statsService;
  final Map<String, DateTime> _lastAudibleAtByInput = <String, DateTime>{};

  @override
  Stream<ConnectionStatus> get connectionStatusStream =>
      _connectionController.stream;

  @override
  Stream<StreamStatus> get streamStatusStream => _streamController.stream;

  @override
  Stream<RecordingStatus> get recordingStatusStream =>
      _recordingController.stream;

  @override
  Stream<String?> get currentSceneStream => _sceneController.stream;

  @override
  Stream<List<SceneItem>> get scenesStream => _scenesController.stream;

  @override
  Stream<List<AudioSource>> get audioSourcesStream => _audioController.stream;

  @override
  Stream<List<SourceItem>> get sourcesStream => _sourcesController.stream;

  @override
  Stream<ObsRuntimeState> get stateStream => _stateController.stream;

  @override
  ObsRuntimeState get currentState => _state;

  @override
  Future<void> connect(ObsConnectionConfig config) async {
    if (_disposed) return;

    _manualDisconnect = false;
    _lastConfig = config;

    await _tearDownConnection(emitDisconnected: false);
    _resetAudioMonitoring();

    _emitState(_state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      audioMetersAvailable: false,
      microphoneSilent: false,
      silentMicrophoneName: null,
      clearLastError: true,
    ));

    try {
      final uri = Uri.parse('ws://${config.host}:${config.port}');
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 8));
      _channel = IOWebSocketChannel(socket);

      _identifyCompleter = Completer<void>();
      _subscription = _channel!.stream.listen(
        _handleIncoming,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );

      await _identifyCompleter!.future.timeout(const Duration(seconds: 12));

      _statsService.setConnected(true);
      await refreshState();

      _emitState(_state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        clearLastError: true,
      ));
    } on TimeoutException {
      await _failConnection(
        ConnectionStatus.error,
        'Timed out while waiting for OBS authentication.',
      );
    } catch (error) {
      final (status, message) = _classifyConnectionError(error);
      await _failConnection(status, message);
    }
  }

  @override
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _statsService.setConnected(false);
    await _tearDownConnection(emitDisconnected: true);
  }

  @override
  Future<Map<String, dynamic>> sendRequest(
    String requestType, {
    Map<String, dynamic> requestData = const <String, dynamic>{},
  }) async {
    if (!_identified || _channel == null) {
      throw const AppException(
        'Not connected to OBS.',
        code: 'not_connected',
      );
    }

    final requestId = _nextRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    _send(
      <String, dynamic>{
        'op': 6,
        'd': <String, dynamic>{
          'requestType': requestType,
          'requestId': requestId,
          'requestData': requestData,
        },
      },
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const AppException(
        'OBS request timed out.',
        code: 'request_timeout',
      );
    } finally {
      _pendingRequests.remove(requestId);
    }
  }

  @override
  Future<void> refreshState() async {
    if (!_identified) return;

    await _refreshScenesAndSources();
    await _refreshInputs();
    await _refreshVirtualCameraStatus();
    await _refreshStudioMode();
    await _statsService.refreshNow();
  }

  @override
  Future<List<SceneItem>> fetchScenes() => _refreshScenesAndSources();

  @override
  Future<List<AudioSource>> fetchAudioSources() => _refreshInputs();

  @override
  Future<List<SourceItem>> fetchSources() async {
    await _refreshScenesAndSources();
    return _state.sources;
  }

  @override
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  }) async {
    if (!_identified || sceneName.trim().isEmpty) return null;

    try {
      final response = await sendRequest(
        'GetSourceScreenshot',
        requestData: <String, dynamic>{
          'sourceName': sceneName,
          'imageFormat': 'jpg',
          'imageWidth': width,
          'imageHeight': height,
          'imageCompressionQuality': quality.clamp(0, 100),
        },
      );
      final data = _responseData(response);
      return data['imageData'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  void setAppInForeground(bool isForeground) {
    _statsService.setAppInForeground(isForeground);
  }

  @override
  Future<void> executeAction(ButtonAction action) async {
    if (!_identified) {
      throw const AppException(
        'Connect to OBS before executing actions.',
        code: 'not_connected',
      );
    }

    final mutatesOutputState = switch (action.type) {
      ButtonActionType.startStream ||
      ButtonActionType.stopStream ||
      ButtonActionType.toggleStream ||
      ButtonActionType.startRecording ||
      ButtonActionType.stopRecording ||
      ButtonActionType.pauseRecording ||
      ButtonActionType.resumeRecording ||
      ButtonActionType.toggleRecording =>
        true,
      _ => false,
    };
    final mutatesVirtualCameraState = switch (action.type) {
      ButtonActionType.startVirtualCamera ||
      ButtonActionType.stopVirtualCamera ||
      ButtonActionType.toggleVirtualCamera =>
        true,
      _ => false,
    };
    final mutatesStudioModeState = switch (action.type) {
      ButtonActionType.enableStudioMode ||
      ButtonActionType.disableStudioMode ||
      ButtonActionType.toggleStudioMode =>
        true,
      _ => false,
    };

    try {
      switch (action.type) {
        case ButtonActionType.switchScene:
          final target = action.targetId ?? action.targetName;
          if (target == null || target.isEmpty) return;
          final sceneName = _resolveSceneNameTarget(target);
          if (sceneName == null) return;
          await sendRequest(
            'SetCurrentProgramScene',
            requestData: <String, dynamic>{'sceneName': sceneName},
          );
          break;
        case ButtonActionType.setPreviewScene:
          if (!_state.studioModeEnabled) return;
          final target = action.targetId ?? action.targetName;
          if (target == null || target.isEmpty) return;
          final sceneName = _resolveSceneNameTarget(target);
          if (sceneName == null) return;
          await sendRequest(
            'SetCurrentPreviewScene',
            requestData: <String, dynamic>{'sceneName': sceneName},
          );
          break;
        case ButtonActionType.showSource:
          await _applySourceVisibilityAction(
            action.targetId ?? action.targetName,
            _VisibilityMode.show,
          );
          break;
        case ButtonActionType.hideSource:
          await _applySourceVisibilityAction(
            action.targetId ?? action.targetName,
            _VisibilityMode.hide,
          );
          break;
        case ButtonActionType.toggleSourceVisibility:
          await _applySourceVisibilityAction(
            action.targetId ?? action.targetName,
            _VisibilityMode.toggle,
          );
          break;
        case ButtonActionType.mute:
          await _applyMuteAction(
            action.targetId ?? action.targetName,
            _MuteMode.mute,
            action.metadata,
          );
          break;
        case ButtonActionType.unmute:
          await _applyMuteAction(
            action.targetId ?? action.targetName,
            _MuteMode.unmute,
            action.metadata,
          );
          break;
        case ButtonActionType.toggleMute:
          await _applyMuteAction(
            action.targetId ?? action.targetName,
            _MuteMode.toggle,
            action.metadata,
          );
          break;
        case ButtonActionType.startStream:
          _emitState(_state.copyWith(streamStatus: StreamStatus.starting));
          await sendRequest('StartStream');
          break;
        case ButtonActionType.stopStream:
          _emitState(_state.copyWith(streamStatus: StreamStatus.stopping));
          await sendRequest('StopStream');
          break;
        case ButtonActionType.toggleStream:
          final isLive = _state.streamStatus == StreamStatus.live ||
              _state.streamStatus == StreamStatus.starting;
          _emitState(
            _state.copyWith(
              streamStatus:
                  isLive ? StreamStatus.stopping : StreamStatus.starting,
            ),
          );
          await sendRequest('ToggleStream');
          break;
        case ButtonActionType.startRecording:
          _emitState(
              _state.copyWith(recordingStatus: RecordingStatus.starting));
          await sendRequest('StartRecord');
          break;
        case ButtonActionType.stopRecording:
          _emitState(
              _state.copyWith(recordingStatus: RecordingStatus.stopping));
          await sendRequest('StopRecord');
          break;
        case ButtonActionType.pauseRecording:
          _emitState(_state.copyWith(recordingStatus: RecordingStatus.paused));
          await sendRequest('PauseRecord');
          break;
        case ButtonActionType.resumeRecording:
          _emitState(
              _state.copyWith(recordingStatus: RecordingStatus.recording));
          await sendRequest('ResumeRecord');
          break;
        case ButtonActionType.toggleRecording:
          final isRecordingActive =
              _state.recordingStatus == RecordingStatus.recording ||
                  _state.recordingStatus == RecordingStatus.paused ||
                  _state.recordingStatus == RecordingStatus.starting;
          _emitState(
            _state.copyWith(
              recordingStatus: isRecordingActive
                  ? RecordingStatus.stopping
                  : RecordingStatus.starting,
            ),
          );
          await sendRequest('ToggleRecord');
          break;
        case ButtonActionType.startVirtualCamera:
          _emitState(_state.copyWith(virtualCameraActive: true));
          await sendRequest('StartVirtualCam');
          break;
        case ButtonActionType.stopVirtualCamera:
          _emitState(_state.copyWith(virtualCameraActive: false));
          await sendRequest('StopVirtualCam');
          break;
        case ButtonActionType.toggleVirtualCamera:
          _emitState(
            _state.copyWith(virtualCameraActive: !_state.virtualCameraActive),
          );
          await sendRequest('ToggleVirtualCam');
          break;
        case ButtonActionType.enableStudioMode:
          _emitState(_state.copyWith(studioModeEnabled: true));
          await sendRequest(
            'SetStudioModeEnabled',
            requestData: const <String, dynamic>{'studioModeEnabled': true},
          );
          break;
        case ButtonActionType.disableStudioMode:
          _emitState(_state.copyWith(studioModeEnabled: false));
          await sendRequest(
            'SetStudioModeEnabled',
            requestData: const <String, dynamic>{'studioModeEnabled': false},
          );
          break;
        case ButtonActionType.toggleStudioMode:
          final nextStudioMode = !_state.studioModeEnabled;
          _emitState(
            _state.copyWith(studioModeEnabled: nextStudioMode),
          );
          await sendRequest(
            'SetStudioModeEnabled',
            requestData: <String, dynamic>{
              'studioModeEnabled': nextStudioMode,
            },
          );
          break;
        case ButtonActionType.runMacro:
          break;
      }
    } finally {
      if (mutatesOutputState) {
        // Correct optimistic states quickly if OBS rejects a request or if
        // an output event arrives late.
        unawaited(_statsService.refreshNow());
      }
      if (mutatesVirtualCameraState) {
        unawaited(_refreshVirtualCameraStatus());
      }
      if (mutatesStudioModeState) {
        unawaited(_refreshStudioMode());
      }
    }
  }

  String? _resolveSceneNameTarget(String targetId) {
    if (targetId.isEmpty) return null;

    final direct = _state.scenes
        .where((scene) => scene.id == targetId || scene.name == targetId)
        .firstOrNull;
    if (direct != null) return direct.name;

    final normalizedTarget = _normalizeTargetToken(targetId);
    final withoutScenePrefix =
        normalizedTarget.replaceFirst(RegExp(r'^scene'), '');

    final fuzzy = _state.scenes.where((scene) {
      final normalizedScene = _normalizeTargetToken(scene.name);
      return normalizedScene == normalizedTarget ||
          normalizedScene == withoutScenePrefix ||
          normalizedScene.contains(withoutScenePrefix) ||
          withoutScenePrefix.contains(normalizedScene);
    }).firstOrNull;
    if (fuzzy != null) return fuzzy.name;

    final isSafeSceneRequest = normalizedTarget.contains('safe') ||
        normalizedTarget.contains('brb') ||
        normalizedTarget.contains('emergency');
    if (isSafeSceneRequest) {
      const safeKeywords = <String>[
        'safe',
        'brb',
        'berightback',
        'break',
        'intermission',
      ];

      final fallback = _state.scenes.where((scene) {
        final normalized = _normalizeTargetToken(scene.name);
        return safeKeywords.any(normalized.contains);
      }).firstOrNull;
      if (fallback != null) return fallback.name;
    }

    return null;
  }

  Future<void> _applyMuteAction(
    String? targetId,
    _MuteMode mode,
    Map<String, dynamic> metadata,
  ) async {
    final normalizedTarget = _normalizeTargetToken(targetId ?? '');
    final all = metadata['all'] == true || normalizedTarget == 'allaudio';

    if (all) {
      final resolvedMode = switch (mode) {
        _MuteMode.mute => _MuteMode.mute,
        _MuteMode.unmute => _MuteMode.unmute,
        _MuteMode.toggle => _state.audioSources.every((input) => input.isMuted)
            ? _MuteMode.unmute
            : _MuteMode.mute,
      };
      for (final input in _state.audioSources) {
        await _setMute(input.id, resolvedMode);
      }
      return;
    }

    if (targetId == null || targetId.isEmpty) return;
    await _setMute(targetId, mode);
  }

  Future<void> _setMute(String inputName, _MuteMode mode) async {
    final resolvedInputName = _resolveAudioInputTarget(inputName);
    if (resolvedInputName == null) return;

    switch (mode) {
      case _MuteMode.toggle:
        await sendRequest(
          'ToggleInputMute',
          requestData: <String, dynamic>{'inputName': resolvedInputName},
        );
        break;
      case _MuteMode.mute:
        await sendRequest(
          'SetInputMute',
          requestData: <String, dynamic>{
            'inputName': resolvedInputName,
            'inputMuted': true,
          },
        );
        break;
      case _MuteMode.unmute:
        await sendRequest(
          'SetInputMute',
          requestData: <String, dynamic>{
            'inputName': resolvedInputName,
            'inputMuted': false,
          },
        );
        break;
    }
  }

  String? _resolveAudioInputTarget(String targetId) {
    final direct = _state.audioSources
        .where((source) => source.id == targetId || source.name == targetId)
        .firstOrNull;
    if (direct != null) return direct.id;

    final normalizedTarget =
        _normalizeTargetToken(targetId).replaceFirst(RegExp(r'^audio'), '');
    if (normalizedTarget.isEmpty) return null;

    final fuzzy = _state.audioSources.where((source) {
      final normalizedSource = _normalizeTargetToken(source.name);
      return normalizedSource == normalizedTarget ||
          normalizedSource.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedSource);
    }).firstOrNull;

    return fuzzy?.id;
  }

  Future<void> _applySourceVisibilityAction(
    String? targetId,
    _VisibilityMode mode,
  ) async {
    if (targetId == null || targetId.isEmpty) return;

    if (_isOverlayGroupTarget(targetId)) {
      final overlayTargets = _resolveOverlayGroupTargets();
      if (overlayTargets.isEmpty) return;
      for (final target in overlayTargets) {
        await _setSceneItemVisibility(target, mode);
      }
      return;
    }

    final target = _resolveSourceTarget(targetId);
    if (target == null) return;
    await _setSceneItemVisibility(target, mode);
  }

  Future<void> _setSceneItemVisibility(
    _SceneItemTarget target,
    _VisibilityMode mode,
  ) async {
    final current = _state.sources
        .where((source) => source.id == target.sceneItemKey)
        .map((source) => source.isVisible)
        .firstOrNull;
    final currentVisible = current ?? false;

    final nextVisible = switch (mode) {
      _VisibilityMode.toggle => !currentVisible,
      _VisibilityMode.show => true,
      _VisibilityMode.hide => false,
    };

    await sendRequest(
      'SetSceneItemEnabled',
      requestData: <String, dynamic>{
        'sceneName': target.sceneName,
        'sceneItemId': target.sceneItemId,
        'sceneItemEnabled': nextVisible,
      },
    );
  }

  bool _isOverlayGroupTarget(String targetId) {
    final normalized = _normalizeTargetToken(targetId);
    return normalized == 'overlaygroup' || normalized == 'overlays';
  }

  List<_SceneItemTarget> _resolveOverlayGroupTargets() {
    const overlayKeywords = <String>[
      'overlay',
      'chat',
      'alert',
      'browser',
      'widget',
      'lowerthird',
    ];

    final matches = _state.sources.where((source) {
      final normalizedName = _normalizeTargetToken(source.name);
      return overlayKeywords.any(normalizedName.contains);
    }).toList();

    return matches
        .map((source) => _parseSceneItemKey(source.id))
        .whereType<_SceneItemTarget>()
        .toList();
  }

  _SceneItemTarget? _resolveSourceTarget(String targetId) {
    if (targetId.contains('::')) {
      final parts = targetId.split('::');
      if (parts.length == 2) {
        final sceneName = parts.first;
        final idString = parts.last;
        final id = int.tryParse(idString);
        if (id != null) {
          return _SceneItemTarget(
            sceneName: sceneName,
            sceneItemId: id,
            sceneItemKey: '$sceneName::$id',
          );
        }

        final matching =
            _state.sources.where((source) => source.id == targetId).firstOrNull;
        if (matching != null) {
          final parsedId = int.tryParse(parts.last);
          if (parsedId != null) {
            return _SceneItemTarget(
              sceneName: matching.sceneId,
              sceneItemId: parsedId,
              sceneItemKey: matching.id,
            );
          }
        }
      }
    }

    final fromId =
        _state.sources.where((source) => source.id == targetId).firstOrNull;
    if (fromId != null) {
      final parsed = _parseSceneItemKey(fromId.id);
      if (parsed != null) return parsed;
    }

    final fromName =
        _state.sources.where((source) => source.name == targetId).firstOrNull;
    if (fromName != null) {
      final parsed = _parseSceneItemKey(fromName.id);
      if (parsed != null) return parsed;
    }

    final normalizedTarget =
        _normalizeTargetToken(targetId).replaceFirst(RegExp(r'^source'), '');
    if (normalizedTarget.isEmpty) return null;

    final fuzzy = _state.sources.where((source) {
      final normalizedName = _normalizeTargetToken(source.name);
      return normalizedName == normalizedTarget ||
          normalizedName.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedName);
    }).firstOrNull;
    if (fuzzy != null) {
      final parsed = _parseSceneItemKey(fuzzy.id);
      if (parsed != null) return parsed;
    }

    return null;
  }

  String _normalizeTargetToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  _SceneItemTarget? _parseSceneItemKey(String key) {
    final parts = key.split('::');
    if (parts.length != 2) return null;
    final id = int.tryParse(parts.last);
    if (id == null) return null;
    return _SceneItemTarget(
      sceneName: parts.first,
      sceneItemId: id,
      sceneItemKey: key,
    );
  }

  Future<List<SceneItem>> _refreshScenesAndSources() async {
    try {
      final response = await sendRequest('GetSceneList');
      final data = _responseData(response);

      final currentProgram = data['currentProgramSceneName'] as String?;
      final currentPreview = data['currentPreviewSceneName'] as String?;

      final rawScenes = (data['scenes'] as List?) ?? <dynamic>[];
      final sceneNames = rawScenes
          .whereType<Map>()
          .map((entry) => (entry['sceneName'] as String?) ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      var scenes =
          sceneNames.map((name) => SceneItem(id: name, name: name)).toList();
      scenes = _applySceneFlags(
        scenes,
        currentProgram: currentProgram,
        currentPreview: currentPreview,
      );

      final sourceItems = <SourceItem>[];
      for (final sceneName in sceneNames) {
        try {
          final sceneItemResponse = await sendRequest(
            'GetSceneItemList',
            requestData: <String, dynamic>{'sceneName': sceneName},
          );
          final sceneItemData = _responseData(sceneItemResponse);
          final items = (sceneItemData['sceneItems'] as List?) ?? <dynamic>[];

          for (final item in items.whereType<Map>()) {
            final sceneItemId = (item['sceneItemId'] as num?)?.toInt();
            final sourceName = item['sourceName'] as String?;
            final enabled = item['sceneItemEnabled'] as bool? ?? true;
            if (sceneItemId == null ||
                sourceName == null ||
                sourceName.isEmpty) {
              continue;
            }

            sourceItems.add(
              SourceItem(
                id: '$sceneName::$sceneItemId',
                name: sourceName,
                sceneId: sceneName,
                isVisible: enabled,
              ),
            );
          }
        } catch (_) {
          // Continue with other scenes.
        }
      }

      _emitState(
        _state.copyWith(
          scenes: scenes,
          currentScene: currentProgram,
          previewScene: currentPreview,
          sources: sourceItems,
        ),
      );

      return scenes;
    } catch (error) {
      _emitState(_state.copyWith(lastError: _errorMessage(error)));
      return _state.scenes;
    }
  }

  Future<List<AudioSource>> _refreshInputs() async {
    try {
      final response = await sendRequest('GetInputList');
      final data = _responseData(response);
      final rawInputs = (data['inputs'] as List?) ?? <dynamic>[];

      final audioSources = <AudioSource>[];
      for (final input in rawInputs.whereType<Map>()) {
        final name = input['inputName'] as String?;
        if (name == null || name.isEmpty) continue;

        try {
          final muteResponse = await sendRequest(
            'GetInputMute',
            requestData: <String, dynamic>{'inputName': name},
          );
          final muteData = _responseData(muteResponse);
          final muted = muteData['inputMuted'] as bool? ?? false;

          audioSources.add(
            AudioSource(
              id: name,
              name: name,
              isMuted: muted,
              volume: 0,
              levelDb: _meterFloorDb,
            ),
          );
        } catch (_) {
          // Non-audio inputs can fail GetInputMute. Skip them.
        }
      }

      _emitAudioSources(audioSources);
      return audioSources;
    } catch (error) {
      _emitState(_state.copyWith(lastError: _errorMessage(error)));
      return _state.audioSources;
    }
  }

  Future<Map<String, dynamic>> _requestStatsPayload(String requestType) async {
    final response = await sendRequest(requestType);
    return _responseData(response);
  }

  void _applyStatsSnapshot(ObsStatsSnapshot snapshot) {
    _emitState(
      _state.copyWith(
        streamStatus: snapshot.streamStatus,
        recordingStatus: snapshot.recordingStatus,
        bitrateKbps: snapshot.bitrateKbps,
        droppedFramesPercent: snapshot.droppedFramesPercent,
        cpuUsagePercent: snapshot.cpuUsagePercent,
        activeFps: snapshot.activeFps,
        averageFrameRenderTimeMs: snapshot.averageFrameRenderTimeMs,
        renderSkippedFrames: snapshot.renderSkippedFrames,
        renderTotalFrames: snapshot.renderTotalFrames,
        uptime: snapshot.streamDuration,
        streamTimecode: snapshot.streamTimecode,
        streamOutputBytes: snapshot.streamOutputBytes,
        outputReconnecting: snapshot.outputReconnecting,
        outputCongestion: snapshot.outputCongestion,
        outputSkippedFrames: snapshot.outputSkippedFrames,
        outputTotalFrames: snapshot.outputTotalFrames,
        recordingDuration: snapshot.recordingDuration,
        recordingTimecode: snapshot.recordingTimecode,
      ),
    );
  }

  Future<void> _refreshStudioMode() async {
    try {
      final response = await sendRequest('GetStudioModeEnabled');
      final data = _responseData(response);
      _emitState(
        _state.copyWith(
          studioModeEnabled: data['studioModeEnabled'] as bool? ?? false,
        ),
      );
    } catch (_) {
      // Older OBS versions/plugins may not support this. Ignore.
    }
  }

  Future<void> _refreshVirtualCameraStatus() async {
    try {
      final response = await sendRequest('GetVirtualCamStatus');
      final data = _responseData(response);
      final active = _resolveVirtualCameraActive(data);
      _emitState(_state.copyWith(virtualCameraActive: active));
    } catch (_) {
      // Virtual camera controls can be unavailable depending on OBS build.
      // Keep previous state if request is unsupported.
    }
  }

  bool _resolveVirtualCameraActive(Map<String, dynamic> data) {
    final outputActive = data['outputActive'];
    if (outputActive is bool) return outputActive;

    final outputState = (data['outputState'] as String?)?.toUpperCase() ?? '';
    if (outputState.contains('START') ||
        outputState.contains('ACTIVE') ||
        outputState.contains('RUNNING')) {
      return true;
    }
    if (outputState.contains('STOP') ||
        outputState.contains('INACTIVE') ||
        outputState == 'OFF') {
      return false;
    }

    final state = (data['state'] as String?)?.toUpperCase() ?? '';
    if (state.contains('START') ||
        state.contains('ACTIVE') ||
        state.contains('RUNNING')) {
      return true;
    }
    if (state.contains('STOP') ||
        state.contains('INACTIVE') ||
        state == 'OFF') {
      return false;
    }

    return _state.virtualCameraActive;
  }

  void _handleIncoming(dynamic event) {
    if (_disposed) return;
    if (event is! String) return;

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map) return;
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final op = (message['op'] as num?)?.toInt();
    final data = message['d'];
    final payload =
        data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

    switch (op) {
      case 0:
        _handleHello(payload);
      case 2:
        _handleIdentified();
      case 5:
        _handleEvent(payload);
      case 7:
        _handleRequestResponse(payload);
      default:
        return;
    }
  }

  void _handleHello(Map<String, dynamic> helloData) {
    final rpcVersion = (helloData['rpcVersion'] as num?)?.toInt() ?? 1;

    final identifyData = <String, dynamic>{
      'rpcVersion': rpcVersion,
      'eventSubscriptions': _eventSubscriptions,
    };

    final auth = helloData['authentication'];
    if (auth is Map) {
      final challenge = auth['challenge'] as String?;
      final salt = auth['salt'] as String?;
      if (challenge != null && salt != null) {
        identifyData['authentication'] =
            _buildAuthString(_lastConfig?.password ?? '', challenge, salt);
      }
    }

    _send(<String, dynamic>{'op': 1, 'd': identifyData});
  }

  void _handleIdentified() {
    _identified = true;
    _identifyCompleter?.completeIfPending();
  }

  void _handleRequestResponse(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null) return;

    final completer = _pendingRequests[requestId];
    if (completer == null) return;

    final requestType = data['requestType'] as String? ?? 'UnknownRequest';
    final status = data['requestStatus'];
    final statusData =
        status is Map ? status.cast<String, dynamic>() : <String, dynamic>{};
    final success = statusData['result'] == true;

    if (success) {
      completer.complete(data);
      return;
    }

    final code = statusData['code'];
    final comment = statusData['comment'] as String? ?? 'OBS request failed.';
    debugPrint(
      '[OBS][request:$requestId][$requestType] failed code=$code comment=$comment',
    );
    completer.completeError(
      AppException(
        '$requestType failed (${code ?? 'unknown'}): $comment',
        code: code?.toString(),
      ),
    );
  }

  void _handleEvent(Map<String, dynamic> payload) {
    final eventType = payload['eventType'] as String?;
    final data = payload['eventData'];
    final eventData =
        data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

    switch (eventType) {
      case 'CurrentProgramSceneChanged':
        final sceneName = eventData['sceneName'] as String?;
        _emitState(
          _state.copyWith(
            currentScene: sceneName,
            scenes: _applySceneFlags(
              _state.scenes,
              currentProgram: sceneName,
              currentPreview: _state.previewScene,
            ),
          ),
        );
        if (sceneName != null &&
            sceneName.isNotEmpty &&
            !_state.scenes.any((scene) => scene.name == sceneName)) {
          unawaited(_refreshScenesAndSources());
        }
      case 'CurrentPreviewSceneChanged':
        final sceneName = eventData['sceneName'] as String?;
        _emitState(
          _state.copyWith(
            previewScene: sceneName,
            scenes: _applySceneFlags(
              _state.scenes,
              currentProgram: _state.currentScene,
              currentPreview: sceneName,
            ),
          ),
        );
      case 'StreamStateChanged':
        final active = eventData['outputActive'] as bool? ?? false;
        final outputState = eventData['outputState'] as String?;
        final outputReconnecting = eventData['outputReconnecting'] as bool? ??
            _state.outputReconnecting;
        final outputCongestion =
            (eventData['outputCongestion'] as num?)?.toDouble() ??
                _state.outputCongestion;
        final outputSkippedFrames =
            (eventData['outputSkippedFrames'] as num?)?.toInt() ??
                _state.outputSkippedFrames;
        final outputTotalFrames =
            (eventData['outputTotalFrames'] as num?)?.toInt() ??
                _state.outputTotalFrames;
        final outputDurationMs =
            (eventData['outputDuration'] as num?)?.toInt() ??
                (active ? _state.uptime.inMilliseconds : 0);
        final outputBytes = (eventData['outputBytes'] as num?)?.toInt() ??
            _state.streamOutputBytes;
        final outputTimecode = eventData['outputTimecode'] as String?;
        final droppedFramesPercent = outputTotalFrames <= 0
            ? 0.0
            : ((outputSkippedFrames / outputTotalFrames) * 100).toDouble();
        _emitState(
          _state.copyWith(
            streamStatus: _mapOutputState(
              active: active,
              outputState: outputState,
              isStream: true,
            ) as StreamStatus,
            uptime: active
                ? Duration(milliseconds: outputDurationMs)
                : Duration.zero,
            streamTimecode: active ? outputTimecode : null,
            streamOutputBytes: active ? outputBytes : 0,
            droppedFramesPercent: active ? droppedFramesPercent : 0,
            outputReconnecting: outputReconnecting,
            outputCongestion: outputCongestion,
            outputSkippedFrames: outputSkippedFrames,
            outputTotalFrames: outputTotalFrames,
          ),
        );
        unawaited(_statsService.refreshNow());
      case 'RecordStateChanged':
        final active = eventData['outputActive'] as bool? ?? false;
        final outputState = eventData['outputState'] as String?;
        final outputDurationMs =
            (eventData['outputDuration'] as num?)?.toInt() ??
                (active ? _state.recordingDuration.inMilliseconds : 0);
        final outputTimecode = eventData['outputTimecode'] as String?;
        _emitState(
          _state.copyWith(
            recordingStatus: _mapOutputState(
              active: active,
              outputState: outputState,
              isStream: false,
            ) as RecordingStatus,
            recordingDuration: active
                ? Duration(milliseconds: outputDurationMs)
                : Duration.zero,
            recordingTimecode: active ? outputTimecode : null,
          ),
        );
        unawaited(_statsService.refreshNow());
      case 'InputMuteStateChanged':
        final inputName = eventData['inputName'] as String?;
        final inputMuted = eventData['inputMuted'] as bool?;
        if (inputName != null && inputMuted != null) {
          var found = false;
          final updated = _state.audioSources.map((source) {
            if (source.id == inputName) {
              found = true;
              return source.copyWith(isMuted: inputMuted);
            }
            return source;
          }).toList();
          _emitAudioSources(updated);
          if (!found) {
            unawaited(_refreshInputs());
          }
        }
      case 'SceneItemEnableStateChanged':
        final sceneName = eventData['sceneName'] as String?;
        final sceneItemId = (eventData['sceneItemId'] as num?)?.toInt();
        final enabled = eventData['sceneItemEnabled'] as bool?;

        if (sceneName != null && sceneItemId != null && enabled != null) {
          final key = '$sceneName::$sceneItemId';
          var found = false;
          final updated = _state.sources.map((source) {
            if (source.id == key) {
              found = true;
              return source.copyWith(isVisible: enabled);
            }
            return source;
          }).toList();
          _emitState(_state.copyWith(sources: updated));
          if (!found) {
            unawaited(_refreshScenesAndSources());
          }
        }
      case 'InputVolumeMeters':
        _handleInputVolumeMeters(eventData);
      case 'StudioModeStateChanged':
      case 'StudioModeSwitched':
        _emitState(
          _state.copyWith(
            studioModeEnabled: eventData['studioModeEnabled'] as bool? ?? false,
          ),
        );
      case 'VirtualcamStateChanged':
      case 'VirtualCamStateChanged':
        _emitState(
          _state.copyWith(
            virtualCameraActive: _resolveVirtualCameraActive(eventData),
          ),
        );
        // Some OBS builds send partial payloads here; sync authoritative value.
        unawaited(_refreshVirtualCameraStatus());
      case 'SceneCreated':
      case 'SceneRemoved':
      case 'SceneNameChanged':
      case 'CurrentSceneCollectionChanged':
      case 'SceneItemCreated':
      case 'SceneItemRemoved':
      case 'SceneItemListReindexed':
        unawaited(_refreshScenesAndSources());
      case 'InputCreated':
      case 'InputRemoved':
      case 'InputNameChanged':
        unawaited(_refreshInputs());
      case 'ExitStarted':
        _emitState(_state.copyWith(lastError: 'OBS is shutting down.'));
      default:
        return;
    }
  }

  void _handleInputVolumeMeters(Map<String, dynamic> data) {
    final inputs = (data['inputs'] as List?) ?? <dynamic>[];
    if (inputs.isEmpty) return;

    final meterByName = <String, ({double level, double db})>{};

    for (final item in inputs.whereType<Map>()) {
      final inputName = item['inputName'] as String?;
      if (inputName == null || inputName.isEmpty) continue;

      final meterDb = _extractPeakValue(item['inputLevelsDb']);
      final meterMul = _extractPeakValue(item['inputLevelsMul']);
      final resolvedDb = meterDb ?? _mulToDb(meterMul);
      final resolvedLevel = meterMul ?? _dbToLevel(meterDb);

      if (resolvedDb == null || resolvedLevel == null) continue;

      meterByName[inputName] = (
        level: resolvedLevel.clamp(0.0, 1.0),
        db: resolvedDb.clamp(_meterFloorDb, 0.0),
      );
    }

    if (meterByName.isEmpty) return;
    _audioMetersAvailable = true;

    final updated = _state.audioSources.map((source) {
      final meter = meterByName[source.id];
      if (meter == null) return source;
      return source.copyWith(
        volume: meter.level,
        levelDb: meter.db,
        hasLiveMeter: true,
      );
    }).toList();

    _emitAudioSources(updated);
  }

  void _emitAudioSources(List<AudioSource> audioSources) {
    final silentMicrophoneName = _resolveSilentMicrophone(audioSources);
    _emitState(
      _state.copyWith(
        audioSources: audioSources,
        audioMetersAvailable: _audioMetersAvailable,
        microphoneSilent: silentMicrophoneName != null,
        silentMicrophoneName: silentMicrophoneName,
      ),
    );
  }

  String? _resolveSilentMicrophone(List<AudioSource> audioSources) {
    if (!_audioMetersAvailable) return null;

    final now = DateTime.now();
    final activeIds = audioSources.map((source) => source.id).toSet();
    _lastAudibleAtByInput.removeWhere(
      (inputId, _) => !activeIds.contains(inputId),
    );

    final candidates = _microphoneCandidates(audioSources);
    for (final source in candidates) {
      _lastAudibleAtByInput.putIfAbsent(source.id, () => now);

      if (source.isMuted || !source.hasLiveMeter) {
        _lastAudibleAtByInput[source.id] = now;
        continue;
      }

      if (source.levelDb > _microphoneSilenceThresholdDb) {
        _lastAudibleAtByInput[source.id] = now;
        continue;
      }

      final lastAudibleAt = _lastAudibleAtByInput[source.id]!;
      if (now.difference(lastAudibleAt) >= _microphoneSilenceWindow) {
        return source.name;
      }
    }

    return null;
  }

  List<AudioSource> _microphoneCandidates(List<AudioSource> audioSources) {
    final microphones = audioSources
        .where((source) => _looksLikeMicrophone(source.name))
        .toList();
    if (microphones.isNotEmpty) return microphones;

    final fallback = audioSources
        .where((source) => !_looksLikeDesktopAudio(source.name))
        .take(1)
        .toList();
    return fallback;
  }

  bool _looksLikeMicrophone(String name) {
    final normalized = _normalizeTargetToken(name);
    if (normalized.isEmpty) return false;
    if (_looksLikeDesktopAudio(name)) return false;

    const keywords = <String>[
      'mic',
      'microphone',
      'aux',
      'voice',
      'xlr',
      'headset',
      'lav',
      'boom',
      'wireless',
    ];
    return keywords.any(normalized.contains);
  }

  bool _looksLikeDesktopAudio(String name) {
    final normalized = _normalizeTargetToken(name);
    if (normalized.isEmpty) return false;

    const keywords = <String>[
      'desktop',
      'system',
      'speaker',
      'output',
      'game',
      'music',
      'media',
      'monitor',
    ];
    return keywords.any(normalized.contains);
  }

  double? _extractPeakValue(dynamic rawLevels) {
    if (rawLevels is! List) return null;

    double? peak;
    for (final channel in rawLevels.whereType<List>()) {
      for (final sample in channel.whereType<num>()) {
        final value = sample.toDouble();
        if (!value.isFinite) continue;
        peak = peak == null ? value : math.max(peak, value);
      }
    }
    return peak;
  }

  double? _mulToDb(double? level) {
    if (level == null) return null;
    if (level <= 0) return _meterFloorDb;
    final db = 20 * (math.log(level) / math.ln10);
    return db.isFinite ? db : _meterFloorDb;
  }

  double? _dbToLevel(double? db) {
    if (db == null) return null;
    if (!db.isFinite) return 0;
    if (db <= _meterFloorDb) return 0;
    if (db >= 0) return 1;
    return math.pow(10, db / 20).toDouble().clamp(0.0, 1.0);
  }

  void _resetAudioMonitoring() {
    _audioMetersAvailable = false;
    _lastAudibleAtByInput.clear();
  }

  void _handleSocketError(Object error) {
    if (_manualDisconnect) return;

    final (status, message) = _classifyConnectionError(error);
    _identifyCompleter?.completeErrorIfPending(AppException(message));
    _handleDisconnect(status, reason: message);
  }

  void _handleSocketDone() {
    if (_manualDisconnect) {
      return;
    }

    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    final status = _mapCloseCodeToStatus(closeCode);

    final reason = closeReason?.trim().isNotEmpty == true
        ? closeReason!.trim()
        : _defaultMessageForStatus(status);

    _identifyCompleter?.completeErrorIfPending(AppException(reason));
    _handleDisconnect(status, reason: reason);
  }

  void _handleDisconnect(
    ConnectionStatus status, {
    String? reason,
  }) {
    _identified = false;
    _statsService.setConnected(false);
    _resetAudioMonitoring();

    _failPendingRequests(
      AppException(
        reason ?? 'Disconnected from OBS.',
        code: 'socket_closed',
      ),
    );

    _emitState(
      _state.copyWith(
        connectionStatus: status,
        audioMetersAvailable: false,
        microphoneSilent: false,
        silentMicrophoneName: null,
        lastError: reason,
      ),
    );

    if (_shouldAutoReconnect(status)) {
      _scheduleReconnect(reason);
    }
  }

  Future<void> _failConnection(
    ConnectionStatus status,
    String message,
  ) async {
    _statsService.setConnected(false);
    await _tearDownConnection(emitDisconnected: false);
    _resetAudioMonitoring();
    _emitState(
      _state.copyWith(
        connectionStatus: status,
        audioMetersAvailable: false,
        microphoneSilent: false,
        silentMicrophoneName: null,
        lastError: message,
      ),
    );

    if (_shouldAutoReconnect(status)) {
      _scheduleReconnect(message);
    }
  }

  Future<void> _tearDownConnection({required bool emitDisconnected}) async {
    _identified = false;
    _statsService.setConnected(false);
    _resetAudioMonitoring();

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _failPendingRequests(const AppException('Connection closed.'));

    if (emitDisconnected) {
      _emitState(
        _state.copyWith(
          connectionStatus: ConnectionStatus.disconnected,
          audioMetersAvailable: false,
          microphoneSilent: false,
          silentMicrophoneName: null,
          clearLastError: true,
        ),
      );
    }
  }

  void _send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(frame));
  }

  List<SceneItem> _applySceneFlags(
    List<SceneItem> scenes, {
    required String? currentProgram,
    required String? currentPreview,
  }) {
    return scenes.map((scene) {
      return scene.copyWith(
        isProgram: scene.name == currentProgram,
        isPreview: scene.name == currentPreview,
      );
    }).toList();
  }

  Map<String, dynamic> _responseData(Map<String, dynamic> requestResponse) {
    final data = requestResponse['responseData'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'req_$_requestCounter';
  }

  dynamic _mapOutputState({
    required bool active,
    required String? outputState,
    required bool isStream,
  }) {
    final state = outputState?.toUpperCase() ?? '';

    if (state.contains('STARTING')) {
      return isStream ? StreamStatus.starting : RecordingStatus.starting;
    }

    if (state.contains('STOPPING')) {
      return isStream ? StreamStatus.stopping : RecordingStatus.stopping;
    }

    if (state.contains('ERROR')) {
      return isStream ? StreamStatus.error : RecordingStatus.error;
    }

    if (!isStream && state.contains('PAUSE')) {
      return RecordingStatus.paused;
    }

    if (active) {
      return isStream ? StreamStatus.live : RecordingStatus.recording;
    }

    return isStream ? StreamStatus.offline : RecordingStatus.stopped;
  }

  (ConnectionStatus, String) _classifyConnectionError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (error is SocketException ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('timed out')) {
      return (ConnectionStatus.notFound, 'Could not reach OBS host/port.');
    }

    if (lower.contains('authentication') || lower.contains('4005')) {
      return (ConnectionStatus.wrongPassword, 'OBS authentication failed.');
    }

    if (error is WebSocketException) {
      return (ConnectionStatus.error, 'WebSocket handshake failed.');
    }

    return (ConnectionStatus.error, 'Unexpected OBS connection error.');
  }

  ConnectionStatus _mapCloseCodeToStatus(int? code) {
    if (code == null) return ConnectionStatus.disconnected;

    switch (code) {
      case 4005:
        return ConnectionStatus.wrongPassword;
      case 1006:
        return ConnectionStatus.notFound;
      default:
        return ConnectionStatus.disconnected;
    }
  }

  String _defaultMessageForStatus(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected.';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case ConnectionStatus.wrongPassword:
        return 'Authentication failed.';
      case ConnectionStatus.notFound:
        return 'Could not reach OBS host.';
      case ConnectionStatus.error:
        return 'Unexpected connection error.';
      case ConnectionStatus.disconnected:
        return 'Disconnected from OBS.';
    }
  }

  String _buildAuthString(String password, String challenge, String salt) {
    final secret = base64Encode(
      sha256.convert(utf8.encode('$password$salt')).bytes,
    );
    return base64Encode(
      sha256.convert(utf8.encode('$secret$challenge')).bytes,
    );
  }

  String _errorMessage(Object error) {
    if (error is AppException) return error.message;
    return error.toString();
  }

  void _failPendingRequests(AppException exception) {
    for (final completer in _pendingRequests.values) {
      completer.completeErrorIfPending(exception);
    }
    _pendingRequests.clear();
  }

  void _emitState(ObsRuntimeState state) {
    if (_disposed) return;

    _state = state;
    _connectionController.add(state.connectionStatus);
    _streamController.add(state.streamStatus);
    _recordingController.add(state.recordingStatus);
    _sceneController.add(state.currentScene);
    _scenesController.add(state.scenes);
    _audioController.add(state.audioSources);
    _sourcesController.add(state.sources);
    _stateController.add(state);
  }

  bool _shouldAutoReconnect(ConnectionStatus status) {
    return !_manualDisconnect &&
        (_lastConfig?.autoReconnect ?? false) &&
        status != ConnectionStatus.wrongPassword;
  }

  void _scheduleReconnect(String? reason) {
    final reconnectMessage = (reason == null || reason.trim().isEmpty)
        ? 'Reconnecting to OBS...'
        : '${reason.trim()} Reconnecting...';

    _emitState(
      _state.copyWith(
        connectionStatus: ConnectionStatus.reconnecting,
        lastError: reconnectMessage,
      ),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      final config = _lastConfig;
      if (config != null) {
        unawaited(connect(config));
      }
    });
  }

  void dispose() {
    _disposed = true;
    _statsService.dispose();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();

    _connectionController.close();
    _streamController.close();
    _recordingController.close();
    _sceneController.close();
    _scenesController.close();
    _audioController.close();
    _sourcesController.close();
    _stateController.close();
  }
}

class _SceneItemTarget {
  const _SceneItemTarget({
    required this.sceneName,
    required this.sceneItemId,
    required this.sceneItemKey,
  });

  final String sceneName;
  final int sceneItemId;
  final String sceneItemKey;
}

enum _MuteMode {
  toggle,
  mute,
  unmute,
}

enum _VisibilityMode {
  toggle,
  show,
  hide,
}

extension _CompleterExt<T> on Completer<T> {
  void completeIfPending([FutureOr<T>? value]) {
    if (isCompleted) return;
    if (value == null) {
      complete();
      return;
    }
    complete(value);
  }

  void completeErrorIfPending(Object error, [StackTrace? stackTrace]) {
    if (isCompleted) return;
    completeError(error, stackTrace);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
