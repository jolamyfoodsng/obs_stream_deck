class DiscoveredObsDevice {
  const DiscoveredObsDevice({
    required this.host,
    required this.port,
    required this.requiresPassword,
    this.obsVersion,
  });

  final String host;
  final int port;
  final bool requiresPassword;
  final String? obsVersion;
}
