import 'connection_method.dart';

class ObsConnectionConfig {
  const ObsConnectionConfig({
    required this.host,
    required this.port,
    required this.password,
    this.connectionMethod = ConnectionMethod.autoDetect,
    this.autoReconnect = true,
    this.rememberConnectionInfo = true,
  });

  final String host;
  final int port;
  final String password;
  final ConnectionMethod connectionMethod;
  final bool autoReconnect;
  final bool rememberConnectionInfo;

  ObsConnectionConfig copyWith({
    String? host,
    int? port,
    String? password,
    ConnectionMethod? connectionMethod,
    bool? autoReconnect,
    bool? rememberConnectionInfo,
  }) {
    return ObsConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      connectionMethod: connectionMethod ?? this.connectionMethod,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      rememberConnectionInfo:
          rememberConnectionInfo ?? this.rememberConnectionInfo,
    );
  }
}
