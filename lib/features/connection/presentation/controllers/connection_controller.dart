import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/obs_auto_discovery_service.dart';
import '../../../../domain/entities/connection_method.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/discovered_obs_device.dart';
import '../../../../domain/entities/obs_connection_config.dart';
import '../../../../domain/entities/saved_obs_connection.dart';
import '../../../../domain/repositories/connection_repository.dart';
import '../../../../domain/repositories/obs_repository.dart';
import '../../../../domain/usecases/connect_to_obs_usecase.dart';
import '../../../../shared/state/app_providers.dart';

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
    this.connectionLabel,
    this.savedConnections = const <SavedObsConnection>[],
    this.discoveredDevices = const <DiscoveredObsDevice>[],
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
  final String? connectionLabel;
  final List<SavedObsConnection> savedConnections;
  final List<DiscoveredObsDevice> discoveredDevices;
  final bool isBusy;
  final bool isDetecting;

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
    String? connectionLabel,
    List<SavedObsConnection>? savedConnections,
    List<DiscoveredObsDevice>? discoveredDevices,
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
      connectionLabel: connectionLabel ?? this.connectionLabel,
      savedConnections: savedConnections ?? this.savedConnections,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      isBusy: isBusy ?? this.isBusy,
      isDetecting: isDetecting ?? this.isDetecting,
    );
  }
}

class ConnectionController extends StateNotifier<ConnectionScreenState> {
  ConnectionController({
    required ConnectToObsUseCase connectToObs,
    required ConnectionRepository connectionRepository,
    required ObsRepository obsRepository,
    required ObsAutoDiscoveryService autoDiscoveryService,
  })  : _connectToObs = connectToObs,
        _connectionRepository = connectionRepository,
        _obsRepository = obsRepository,
        _autoDiscoveryService = autoDiscoveryService,
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
          ),
        ) {
    _init();
  }

  final ConnectToObsUseCase _connectToObs;
  final ConnectionRepository _connectionRepository;
  final ObsRepository _obsRepository;
  final ObsAutoDiscoveryService _autoDiscoveryService;

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
    }

    if (savedConnections.isNotEmpty) {
      final sorted = <SavedObsConnection>[...savedConnections]
        ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      state = state.copyWith(savedConnections: sorted);
    }

    _obsSubscription = _obsRepository.watchState().listen((runtimeState) {
      state = state.copyWith(
        status: runtimeState.connectionStatus,
        statusMessage: runtimeState.lastError?.trim().isNotEmpty == true
            ? runtimeState.lastError!
            : _statusMessage(runtimeState.connectionStatus),
        isBusy: runtimeState.connectionStatus == ConnectionStatus.connecting ||
            runtimeState.connectionStatus == ConnectionStatus.reconnecting,
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

  void updateAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
  }

  void updateRememberConnectionInfo(bool value) {
    state = state.copyWith(rememberConnectionInfo: value);
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
          statusMessage:
              'Couldn\'t find OBS automatically. Try Scan QR or Manual Setup.',
        );
      } else {
        state = state.copyWith(
          discoveredDevices: discovered,
          statusMessage: 'Found ${discovered.length} OBS device(s).',
        );
      }
    } catch (_) {
      state = state.copyWith(
        discoveredDevices: const <DiscoveredObsDevice>[],
        statusMessage:
            'Couldn\'t find OBS automatically. Try Scan QR or Manual Setup.',
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
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
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

    final wasConnected = state.status == ConnectionStatus.connected;
    state = state.copyWith(
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
        statusMessage:
            'Connection test successful. Tap Connect to OBS to stay connected.',
      );
    } catch (error) {
      final message =
          error.toString().trim().replaceFirst(RegExp(r'^Exception:\s*'), '');
      state = state.copyWith(
        status: state.status == ConnectionStatus.connecting
            ? ConnectionStatus.error
            : state.status,
        statusMessage: message.isEmpty ? 'Connection test failed.' : message,
      );
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> connect() async {
    _normalizeStateForSelectedMethod();
    if (!_validate()) return;

    state = state.copyWith(isBusy: true, status: ConnectionStatus.connecting);

    try {
      await _connectToObs(state.toConfig());
      await _saveSuccessfulConnection();
    } finally {
      state = state.copyWith(isBusy: false);
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
      savedConnections: const <SavedObsConnection>[],
    );
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
      );
      return false;
    }

    final parsed = int.tryParse(state.port.trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        statusMessage: 'Port must be between 1 and 65535.',
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
        return 'Auth failed. Update password and retry.';
      case ConnectionStatus.notFound:
        return 'OBS unreachable. Check host/port and firewall.';
      case ConnectionStatus.error:
        return 'Connection error.';
      case ConnectionStatus.disconnected:
        return 'Not connected.';
    }
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
    );
  },
);
