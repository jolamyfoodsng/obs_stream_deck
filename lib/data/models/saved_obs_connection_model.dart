import '../../domain/entities/saved_obs_connection.dart';

class SavedObsConnectionModel {
  const SavedObsConnectionModel._();

  static Map<String, dynamic> toJson(SavedObsConnection connection) {
    return <String, dynamic>{
      'id': connection.id,
      'label': connection.label,
      'host': connection.host,
      'port': connection.port,
      'password': connection.password,
      'lastConnectedAt': connection.lastConnectedAt.toIso8601String(),
    };
  }

  static SavedObsConnection fromJson(Map<String, dynamic> json) {
    final parsedDate =
        DateTime.tryParse(json['lastConnectedAt'] as String? ?? '');
    return SavedObsConnection(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'OBS Device',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 4455,
      password: json['password'] as String? ?? '',
      lastConnectedAt: parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
