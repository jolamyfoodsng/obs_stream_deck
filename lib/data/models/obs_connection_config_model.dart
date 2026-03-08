import '../../domain/entities/obs_connection_config.dart';

class ObsConnectionConfigModel {
  const ObsConnectionConfigModel._();

  static Map<String, dynamic> toJson(ObsConnectionConfig config) {
    return <String, dynamic>{
      'host': config.host,
      'port': config.port,
      'password': config.password,
      'autoReconnect': config.autoReconnect,
      'rememberConnectionInfo': config.rememberConnectionInfo,
    };
  }

  static ObsConnectionConfig fromJson(Map<String, dynamic> json) {
    return ObsConnectionConfig(
      host: json['host'] as String? ?? '127.0.0.1',
      port: (json['port'] as num?)?.toInt() ?? 4455,
      password: json['password'] as String? ?? '',
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      rememberConnectionInfo: json['rememberConnectionInfo'] as bool? ?? true,
    );
  }
}
