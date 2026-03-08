class ObsConnectionConfig {
  const ObsConnectionConfig({
    required this.host,
    required this.port,
    required this.password,
    this.autoReconnect = true,
    this.rememberConnectionInfo = true,
  });

  final String host;
  final int port;
  final String password;
  final bool autoReconnect;
  final bool rememberConnectionInfo;

  ObsConnectionConfig copyWith({
    String? host,
    int? port,
    String? password,
    bool? autoReconnect,
    bool? rememberConnectionInfo,
  }) {
    return ObsConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      rememberConnectionInfo:
          rememberConnectionInfo ?? this.rememberConnectionInfo,
    );
  }
}
