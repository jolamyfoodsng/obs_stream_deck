class SavedObsConnection {
  const SavedObsConnection({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.password,
    required this.lastConnectedAt,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String password;
  final DateTime lastConnectedAt;

  SavedObsConnection copyWith({
    String? id,
    String? label,
    String? host,
    int? port,
    String? password,
    DateTime? lastConnectedAt,
  }) {
    return SavedObsConnection(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }
}
