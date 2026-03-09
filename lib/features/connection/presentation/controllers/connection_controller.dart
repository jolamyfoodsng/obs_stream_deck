import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/services/connection_diagnostics_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/obs_auto_discovery_service.dart';
import '../../../../domain/entities/connection_diagnostic.dart';
import '../../../../domain/entities/connection_method.dart';
import '../../../../domain/entities/connection_preflight_report.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/discovered_obs_device.dart';
import '../../../../domain/entities/obs_connection_config.dart';
import '../../../../domain/entities/saved_obs_connection.dart';
import '../../../../domain/repositories/connection_repository.dart';
import '../../../../domain/repositories/obs_repository.dart';
import '../../../../domain/usecases/connect_to_obs_usecase.dart';
import '../../../../shared/state/app_providers.dart';

enum ConnectionUiAction {
  none,
  connect,
  test,
}

class ConnectionScreenState {
  const ConnectionScreenState({
    required this.host,
    required this.port,
    required this.password,
    required this.connectionMethod,
    required this.autoReconnect,
    required this.rememberConnectionInfo,
    required this.status,
    required this.statusMessage,
    this.diagnostics = const <ConnectionDiagnostic>[],
    this.preflight,
    required this.showSetupGuide,
    this.latencyMs,
    this.connectionLabel,
    this.savedConnections = const <SavedObsConnection>[],
    this.discoveredDevices = const <DiscoveredObsDevice>[],
    this.activeAction = ConnectionUiAction.none,
    this.isBusy = false,
    this.isDetecting = false,
  });

  final String host;
  final String port;
  final String password;
  final ConnectionMethod connectionMethod;
  final bool autoReconnect;
  final bool rememberConnectionInfo;
  final ConnectionStatus status;
  final String statusMessage;
  final List<ConnectionDiagnostic> diagnostics;
  final ConnectionPreflightReport? preflight;
  final bool showSetupGuide;
  final int? latencyMs;
  final String? connectionLabel;
  final List<SavedObsConnection> savedConnections;
  final List<DiscoveredObsDevice> discoveredDevices;
  final ConnectionUiAction activeAction;
  final bool isBusy;
  final bool isDetecting;

  bool get isConnectingAction => activeAction == ConnectionUiAction.connect;
  bool get isTestingAction => activeAction == ConnectionUiAction.test;

  ObsConnectionConfig toConfig() {
    return ObsConnectionConfig(
      host: host.trim(),
      port: int.tryParse(port.trim()) ?? 4455,
      password: password,
      connectionMethod: connectionMethod,
      autoReconnect: autoReconnect,
      rememberConnectionInfo: rememberConnectionInfo,
    );
  }

  ConnectionScreenState copyWith({
    String? host,
    String? port,
    String? password,
    ConnectionMethod? connectionMethod,
    bool? autoReconnect,
    bool? rememberConnectionInfo,
    ConnectionStatus? status,
    String? statusMessage,
    List<ConnectionDiagnostic>? diagnostics,
    Object? preflight = _sentinel,
    bool? showSetupGuide,
    Object? latencyMs = _sentinel,
    String? connectionLabel,
    List<SavedObsConnection>? savedConnections,
    List<DiscoveredObsDevice>? discoveredDevices,
    ConnectionUiAction? activeAction,
    bool? isBusy,
    bool? isDetecting,
  }) {
    return ConnectionScreenState(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      connectionMethod: connectionMethod ?? this.connectionMethod,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      rememberConnectionInfo:
          rememberConnectionInfo ?? this.rememberConnectionInfo,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      diagnostics: diagnostics ?? this.diagnostics,
      preflight: identical(preflight, _sentinel)
          ? this.preflight
          : preflight as ConnectionPreflightReport?,
      showSetupGuide: showSetupGuide ?? this.showSetupGuide,
      latencyMs:
          identical(latencyMs, _sentinel) ? this.latencyMs : latencyMs as int?,
      connectionLabel: connectionLabel ?? this.connectionLabel,
      savedConnections: savedConnections ?? this.savedConnections,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      activeAction: activeAction ?? this.activeAction,
      isBusy: isBusy ?? this.isBusy,
      isDetecting: isDetecting ?? this.isDetecting,
    );
  }

  static const Object _sentinel = Object();
}

class ConnectionController extends StateNotifier<ConnectionScreenState> {
  ConnectionController({
    required ConnectToObsUseCase connectToObs,
    required ConnectionRepository connectionRepository,
    required ObsRepository obsRepository,
    required ObsAutoDiscoveryService autoDiscoveryService,
    required ConnectionDiagnosticsService diagnosticsService,
    required LocalStorageService localStorage,
  })  : _connectToObs = connectToObs,
        _connectionRepository = connectionRepository,
        _obsRepository = obsRepository,
        _autoDiscoveryService = autoDiscoveryService,
        _diagnosticsService = diagnosticsService,
        _localStorage = localStorage,
        super(
          const ConnectionScreenState(
            host: '127.0.0.1',
            port: '4455',
            password: '',
            connectionMethod: ConnectionMethod.autoDetect,
            autoReconnect: true,
            rememberConnectionInfo: true,
            status: ConnectionStatus.disconnected,
            statusMessage: 'Not connected.',
            showSetupGuide: false,
          ),
        ) {
    _init();
  }

  final ConnectToObsUseCase _connectToObs;
  final ConnectionRepository _connectionRepository;
  final ObsRepository _obsRepository;
  final ObsAutoDiscoveryService _autoDiscoveryService;
  final ConnectionDiagnosticsService _diagnosticsService;
  final LocalStorageService _localStorage;

  StreamSubscription? _obsSubscription;

  Future<void> _init() async {
    final savedConfig = await _connectionRepository.loadConfig();
    final savedConnections = await _connectionRepository.loadSavedConnections();

    if (savedConfig != null) {
      state = state.copyWith(
        host: savedConfig.host,
        port: savedConfig.port.toString(),
        password: savedConfig.password,
        connectionMethod: savedConfig.connectionMethod,
        autoReconnect: savedConfig.autoReconnect,
        rememberConnectionInfo: savedConfig.rememberConnectionInfo,
      );
    } else {
      state = state.copyWith(host: _defaultHostForPlatform());
      state = state.copyWith(
        autoReconnect:
            _localStorage.getBool(StorageKeys.connectionAutoReconnectPref) ??
                state.autoReconnect,
        rememberConnectionInfo:
            _localStorage.getBool(StorageKeys.connectionRememberInfoPref) ??
                state.rememberConnectionInfo,
      );
    }

    if (savedConnections.isNotEmpty) {
      final sorted = <SavedObsConnection>[...savedConnections]
        ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      state = state.copyWith(savedConnections: sorted);
    }

    final guideDismissed =
        _localStorage.getBool(StorageKeys.connectionGuideDismissed) ?? false;
    final shouldShowGuide =
        !guideDismissed && savedConfig == null && savedConnections.isEmpty;
    state = state.copyWith(showSetupGuide: shouldShowGuide);

    _obsSubscription = _obsRepository.watchState().listen((runtimeState) {
      final reconnectingDiagnostics =
          runtimeState.connectionStatus == ConnectionStatus.reconnecting
              ? const <ConnectionDiagnostic>[
                  ConnectionDiagnostic(
                    type: ConnectionDiagnosticType.reconnecting,
                    severity: ConnectionDiagnosticSeverity.info,
                    title: 'Reconnecting to OBS',
                    message:
                        'The connection dropped. DeckPilot is retrying automatically.',
                    fix:
                        'Keep OBS open. If this repeats, check Wi-Fi and firewall rules.',
                  ),
                ]
              : state.diagnostics;
      state = state.copyWith(
        status: runtimeState.connectionStatus,
        statusMessage: runtimeState.lastError?.trim().isNotEmpty == true
            ? runtimeState.lastError!
            : _statusMessage(runtimeState.connectionStatus),
        diagnostics: runtimeState.connectionStatus == ConnectionStatus.connected
            ? const <ConnectionDiagnostic>[]
            : reconnectingDiagnostics,
        showSetupGuide:
            runtimeState.connectionStatus == ConnectionStatus.connected
                ? false
                : state.showSetupGuide,
        latencyMs: runtimeState.connectionLatencyMs,
      );
    });
  }

  void updateHost(String value) => state = state.copyWith(host: value);

  void updatePort(String value) => state = state.copyWith(port: value);

  void updatePassword(String value) => state = state.copyWith(password: value);

  void updateConnectionMethod(ConnectionMethod method) {
    if (method == state.connectionMethod) return;

    switch (method) {
      case ConnectionMethod.usb:
        state = state.copyWith(
          connectionMethod: method,
          host: _defaultUsbHostForPlatform(),
          port: state.port.trim().isEmpty ? '4455' : state.port,
          statusMessage:
              'USB mode selected. Connect USB and run ADB reverse, then connect.',
        );
        return;
      case ConnectionMethod.autoDetect:
        state = state.copyWith(
          connectionMethod: method,
          statusMessage: 'Tap Find OBS Automatically to scan your network.',
        );
        return;
      case ConnectionMethod.wifi:
        state = state.copyWith(
          connectionMethod: method,
          statusMessage:
              'Use your OBS computer local Wi-Fi IP, then connect or test.',
        );
        return;
      case ConnectionMethod.manual:
        state = state.copyWith(
          connectionMethod: method,
          statusMessage: 'Enter host, port, and password manually.',
        );
        return;
    }
  }

  void applyUsbDefaults() {
    state = state.copyWith(
      connectionMethod: ConnectionMethod.usb,
      host: _defaultUsbHostForPlatform(),
      port: '4455',
      statusMessage:
          'USB defaults applied. Run ADB reverse and tap Connect/Test.',
    );
  }

  Future<void> dismissSetupGuide() async {
    await _localStorage.setBool(StorageKeys.connectionGuideDismissed, true);
    state = state.copyWith(showSetupGuide: false);
  }

  void updateAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
    unawaited(_persistConnectionPreferences());
  }

  void updateRememberConnectionInfo(bool value) {
    state = state.copyWith(rememberConnectionInfo: value);
    unawaited(_persistConnectionPreferences());
  }

  Future<void> autoDetect() async {
    final parsedPort = int.tryParse(state.port.trim()) ?? 4455;
    final preferredHosts = <String>{
      state.host.trim(),
      ...state.savedConnections.map((item) => item.host),
    }.where((host) => host.isNotEmpty);

    state = state.copyWith(
      isDetecting: true,
      discoveredDevices: const <DiscoveredObsDevice>[],
      diagnostics: const <ConnectionDiagnostic>[],
      statusMessage: 'Scanning your network for OBS...',
    );

    try {
      final discovered = await _autoDiscoveryService.discover(
        preferredHosts: preferredHosts,
        port: parsedPort,
      );

      if (discovered.isEmpty) {
        state = state.copyWith(
          discoveredDevices: const <DiscoveredObsDevice>[],
          diagnostics: const <ConnectionDiagnostic>[
            ConnectionDiagnostic(
              type: ConnectionDiagnosticType.obsNotRunning,
              severity: ConnectionDiagnosticSeverity.warning,
              title: 'OBS Studio was not detected',
              message: 'Open OBS on your computer and try again.',
              fix:
                  'If OBS is open, go to Tools → WebSocket Server Settings and enable WebSocket Server.',
            ),
          ],
          statusMessage: _withSetupGuideHint(
            'Couldn\'t find OBS automatically. Try Scan QR or Manual Setup.',
          ),
        );
      } else {
        state = state.copyWith(
          discoveredDevices: discovered,
          diagnostics: const <ConnectionDiagnostic>[],
          statusMessage: 'Found ${discovered.length} OBS device(s).',
        );
      }
    } catch (_) {
      state = state.copyWith(
        discoveredDevices: const <DiscoveredObsDevice>[],
        diagnostics: const <ConnectionDiagnostic>[
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.networkCheck,
            severity: ConnectionDiagnosticSeverity.warning,
            title: 'Automatic detection did not complete',
            message: 'DeckPilot could not scan the network for OBS right now.',
            fix:
                'Try Scan QR Code or Manual Setup, then retry auto detect later.',
          ),
        ],
        statusMessage: _withSetupGuideHint(
          'Couldn\'t find OBS automatically. Try Scan QR or Manual Setup.',
        ),
      );
    } finally {
      state = state.copyWith(isDetecting: false);
    }
  }

  Future<void> useDiscoveredDevice(
    DiscoveredObsDevice device, {
    bool connectImmediately = true,
  }) async {
    state = state.copyWith(
      host: device.host,
      port: '${device.port}',
      connectionMethod: ConnectionMethod.autoDetect,
      connectionLabel: 'OBS ${device.host}',
      diagnostics: const <ConnectionDiagnostic>[],
      statusMessage: device.requiresPassword
          ? 'OBS found at ${device.host}. Enter password, then connect.'
          : 'OBS found at ${device.host}.',
    );

    if (!connectImmediately) return;
    if (device.requiresPassword && state.password.trim().isEmpty) {
      return;
    }
    await connect();
  }

  void applyScannedConnection({
    required String host,
    required int port,
    String password = '',
    String? label,
  }) {
    state = state.copyWith(
      host: host.trim(),
      port: '$port',
      password: password,
      connectionMethod: ConnectionMethod.wifi,
      connectionLabel: label,
      diagnostics: const <ConnectionDiagnostic>[],
      statusMessage:
          'QR details loaded. Confirm and tap Connect to OBS if needed.',
    );
  }

  Future<void> connectToSaved(SavedObsConnection saved) async {
    state = state.copyWith(
      host: saved.host,
      port: '${saved.port}',
      password: saved.password,
      connectionMethod: ConnectionMethod.manual,
      connectionLabel: saved.label,
      diagnostics: const <ConnectionDiagnostic>[],
      statusMessage: 'Reconnecting to ${saved.label}...',
    );
    await connect();
  }

  Future<void> removeSavedConnection(String id) async {
    final updated = state.savedConnections
        .where((connection) => connection.id != id)
        .toList();
    await _connectionRepository.saveSavedConnections(updated);
    state = state.copyWith(savedConnections: updated);
  }

  String _defaultHostForPlatform() {
    if (kIsWeb) return '127.0.0.1';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return '';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return '127.0.0.1';
    }
  }

  String _defaultUsbHostForPlatform() {
    if (kIsWeb) return '127.0.0.1';
    return '127.0.0.1';
  }

  void _normalizeStateForSelectedMethod() {
    if (state.connectionMethod != ConnectionMethod.usb) return;

    final host = state.host.trim();
    final port = state.port.trim();
    final normalizedHost = host.isEmpty ? _defaultUsbHostForPlatform() : host;
    final normalizedPort = port.isEmpty ? '4455' : port;

    if (normalizedHost == state.host && normalizedPort == state.port) return;

    state = state.copyWith(
      host: normalizedHost,
      port: normalizedPort,
    );
  }

  Future<void> testConnection() async {
    _normalizeStateForSelectedMethod();
    if (!_validate()) return;
    final preflight = await _runPreflight();

    final wasConnected = state.status == ConnectionStatus.connected;
    state = state.copyWith(
      activeAction: ConnectionUiAction.test,
      isBusy: true,
      status: ConnectionStatus.connecting,
      statusMessage: 'Testing OBS connection...',
    );

    try {
      if (wasConnected) {
        await _obsRepository.refreshState();
        state = state.copyWith(
          status: ConnectionStatus.connected,
          statusMessage: 'Connection test successful.',
        );
        return;
      }

      await _obsRepository.connect(state.toConfig());
      await _obsRepository.refreshState();
      await _obsRepository.disconnect();

      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        diagnostics: const <ConnectionDiagnostic>[],
        preflight: preflight,
        statusMessage:
            'Connection test successful. Tap Connect to OBS to stay connected.',
      );
    } catch (error) {
      final message =
          error.toString().trim().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final runtimeStatus = _obsRepository.currentState().connectionStatus;
      final resolvedStatus = runtimeStatus == ConnectionStatus.connecting
          ? ConnectionStatus.error
          : runtimeStatus;
      final diagnostics = _diagnosticsService.buildFailureDiagnostics(
        status: resolvedStatus,
        host: state.host.trim(),
        port: int.tryParse(state.port.trim()) ?? 4455,
        method: state.connectionMethod,
        report: preflight,
        rawMessage: message,
      );
      developer.log(
        'OBS test failed host=${state.host.trim()} port=${state.port.trim()} status=${resolvedStatus.name} reason=$message',
        name: 'DeckPilot.Connection',
        level: 1000,
      );
      state = state.copyWith(
        status: resolvedStatus,
        diagnostics: diagnostics,
        preflight: preflight,
        latencyMs: null,
        statusMessage: _withSetupGuideHint(
          diagnostics.first.message.isNotEmpty
              ? diagnostics.first.message
              : (message.isEmpty ? 'Connection test failed.' : message),
        ),
      );
    } finally {
      state = state.copyWith(
        activeAction: ConnectionUiAction.none,
        isBusy: false,
      );
    }
  }

  Future<void> connect() async {
    _normalizeStateForSelectedMethod();
    if (!_validate()) return;
    final preflight = await _runPreflight();

    state = state.copyWith(
      activeAction: ConnectionUiAction.connect,
      isBusy: true,
      status: ConnectionStatus.connecting,
    );

    try {
      developer.log(
        'OBS connect requested host=${state.host.trim()} port=${state.port.trim()} method=${state.connectionMethod.name}',
        name: 'DeckPilot.Connection',
      );
      await _connectToObs(state.toConfig());
      await _saveSuccessfulConnection();
      await dismissSetupGuide();
      state = state.copyWith(
        diagnostics: const <ConnectionDiagnostic>[],
        preflight: preflight,
      );
    } catch (error) {
      final message =
          error.toString().trim().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final runtimeStatus = _obsRepository.currentState().connectionStatus;
      final resolvedStatus = runtimeStatus == ConnectionStatus.connecting
          ? ConnectionStatus.error
          : runtimeStatus;
      final diagnostics = _diagnosticsService.buildFailureDiagnostics(
        status: resolvedStatus,
        host: state.host.trim(),
        port: int.tryParse(state.port.trim()) ?? 4455,
        method: state.connectionMethod,
        report: preflight,
        rawMessage: message,
      );
      state = state.copyWith(
        status: resolvedStatus,
        diagnostics: diagnostics,
        preflight: preflight,
        latencyMs: null,
        statusMessage: _withSetupGuideHint(
          diagnostics.first.message.isNotEmpty
              ? diagnostics.first.message
              : (message.isEmpty ? 'Connection failed.' : message),
        ),
      );
    } finally {
      state = state.copyWith(
        activeAction: ConnectionUiAction.none,
        isBusy: false,
      );
    }
  }

  Future<void> disconnect() async {
    await _obsRepository.disconnect();
  }

  Future<void> clearSavedConnection() async {
    await _connectionRepository.clearConfig();
    await _connectionRepository.saveSavedConnections(<SavedObsConnection>[]);
    state = state.copyWith(
      statusMessage: 'Saved connection info cleared.',
      rememberConnectionInfo: false,
      diagnostics: const <ConnectionDiagnostic>[],
      savedConnections: const <SavedObsConnection>[],
    );
  }

  Future<ConnectionPreflightReport> _runPreflight() async {
    final report = await _diagnosticsService.runPreflight(
      host: state.host.trim(),
      port: int.tryParse(state.port.trim()) ?? 4455,
      method: state.connectionMethod,
    );
    state = state.copyWith(
      preflight: report,
      diagnostics: _diagnosticsService.buildPreflightDiagnostics(
        report: report,
        host: state.host.trim(),
        port: int.tryParse(state.port.trim()) ?? 4455,
        method: state.connectionMethod,
      ),
    );
    return report;
  }

  Future<void> _saveSuccessfulConnection() async {
    if (!state.rememberConnectionInfo) return;

    final host = state.host.trim();
    final port = int.tryParse(state.port.trim()) ?? 4455;
    if (host.isEmpty) return;

    final fallbackLabel = _suggestLabel(host);
    final explicitLabel = state.connectionLabel?.trim();
    final label =
        (explicitLabel?.isNotEmpty == true) ? explicitLabel! : fallbackLabel;

    final now = DateTime.now();
    final existing = <SavedObsConnection>[...state.savedConnections];
    final existingIndex =
        existing.indexWhere((item) => item.host == host && item.port == port);

    final record = SavedObsConnection(
      id: existingIndex >= 0
          ? existing[existingIndex].id
          : 'saved_${now.microsecondsSinceEpoch}',
      label: label,
      host: host,
      port: port,
      password: state.password,
      lastConnectedAt: now,
    );

    if (existingIndex >= 0) {
      existing[existingIndex] = record;
    } else {
      existing.add(record);
    }

    existing.sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
    final limited = existing.take(8).toList(growable: false);
    await _connectionRepository.saveSavedConnections(limited);
    state = state.copyWith(savedConnections: limited);
  }

  Future<void> _persistConnectionPreferences() async {
    await _localStorage.setBool(
      StorageKeys.connectionAutoReconnectPref,
      state.autoReconnect,
    );
    await _localStorage.setBool(
      StorageKeys.connectionRememberInfoPref,
      state.rememberConnectionInfo,
    );

    if (!state.rememberConnectionInfo) {
      await _connectionRepository.clearConfig();
    } else {
      final existingConfig = await _connectionRepository.loadConfig();
      if (existingConfig != null) {
        await _connectionRepository.saveConfig(
          existingConfig.copyWith(
            autoReconnect: state.autoReconnect,
            rememberConnectionInfo: state.rememberConnectionInfo,
          ),
        );
      }
    }

    _obsRepository.updateConnectionPreferences(
      autoReconnect: state.autoReconnect,
      rememberConnectionInfo: state.rememberConnectionInfo,
    );
  }

  String _suggestLabel(String host) {
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return 'OBS $host';
    }
    return host;
  }

  bool _validate() {
    if (state.host.trim().isEmpty) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        statusMessage: 'Host is required.',
        diagnostics: const <ConnectionDiagnostic>[
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.invalidHost,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'Host is required',
            message:
                'Enter the IP address or hostname of the computer running OBS.',
            fix:
                'Use Find OBS Automatically, scan a QR code, or enter the local IP manually.',
          ),
        ],
      );
      return false;
    }

    final parsed = int.tryParse(state.port.trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        statusMessage: 'Port must be between 1 and 65535.',
        diagnostics: const <ConnectionDiagnostic>[
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.invalidHost,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'Port is invalid',
            message: 'OBS WebSocket usually listens on port 4455.',
            fix: 'Enter a port between 1 and 65535 and try again.',
          ),
        ],
      );
      return false;
    }

    return true;
  }

  String _statusMessage(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected.';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case ConnectionStatus.wrongPassword:
        return _withSetupGuideHint('Auth failed. Update password and retry.');
      case ConnectionStatus.notFound:
        return _withSetupGuideHint(
          'OBS unreachable. Check host/port and firewall.',
        );
      case ConnectionStatus.error:
        return _withSetupGuideHint('Connection error.');
      case ConnectionStatus.disconnected:
        return 'Not connected.';
    }
  }

  String _withSetupGuideHint(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return 'Open View Setup Guide if OBS WebSocket is not enabled.';
    }

    const hint = 'Open View Setup Guide if OBS WebSocket is not enabled.';
    if (trimmed.contains(hint)) {
      return trimmed;
    }
    return '$trimmed $hint';
  }

  @override
  void dispose() {
    _obsSubscription?.cancel();
    super.dispose();
  }
}

final connectionControllerProvider = StateNotifierProvider.autoDispose<
    ConnectionController, ConnectionScreenState>(
  (ref) {
    return ConnectionController(
      connectToObs: ref.watch(connectToObsUseCaseProvider),
      connectionRepository: ref.watch(connectionRepositoryProvider),
      obsRepository: ref.watch(obsRepositoryProvider),
      autoDiscoveryService: ref.watch(obsAutoDiscoveryServiceProvider),
      diagnosticsService: ref.watch(connectionDiagnosticsServiceProvider),
      localStorage: ref.watch(localStorageServiceProvider),
    );
  },
);
