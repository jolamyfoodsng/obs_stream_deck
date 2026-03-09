class ConnectionPreflightReport {
  const ConnectionPreflightReport({
    required this.localAddresses,
    required this.hasLocalNetwork,
    required this.hostIsLoopback,
    required this.hostIsPrivateIpv4,
    required this.likelySameSubnet,
    required this.hostResolved,
    required this.tcpReachable,
    required this.portOpen,
    this.tcpFailure,
  });

  final List<String> localAddresses;
  final bool hasLocalNetwork;
  final bool hostIsLoopback;
  final bool hostIsPrivateIpv4;
  final bool likelySameSubnet;
  final bool hostResolved;
  final bool tcpReachable;
  final bool portOpen;
  final String? tcpFailure;
}
