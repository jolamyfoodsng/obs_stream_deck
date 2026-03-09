import 'package:obs_stream_deck/core/services/obs_auto_discovery_service.dart';
import 'package:obs_stream_deck/domain/entities/discovered_obs_device.dart';

class FakeObsAutoDiscoveryService extends ObsAutoDiscoveryService {
  FakeObsAutoDiscoveryService({List<DiscoveredObsDevice>? devices})
      : devices = devices ?? <DiscoveredObsDevice>[];

  List<DiscoveredObsDevice> devices;
  int discoverCalls = 0;

  @override
  Future<List<DiscoveredObsDevice>> discover({
    Iterable<String> preferredHosts = const <String>[],
    int port = 4455,
    Duration connectTimeout = const Duration(milliseconds: 420),
    Duration helloTimeout = const Duration(milliseconds: 650),
    int maxHosts = 320,
    int batchSize = 36,
  }) async {
    discoverCalls += 1;
    return List<DiscoveredObsDevice>.from(devices);
  }
}
