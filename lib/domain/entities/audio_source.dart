class AudioSource {
  const AudioSource({
    required this.id,
    required this.name,
    required this.isMuted,
    required this.volume,
    this.levelDb = -60,
    this.hasLiveMeter = false,
  });

  final String id;
  final String name;
  final bool isMuted;
  final double volume;
  final double levelDb;
  final bool hasLiveMeter;

  AudioSource copyWith({
    String? id,
    String? name,
    bool? isMuted,
    double? volume,
    double? levelDb,
    bool? hasLiveMeter,
  }) {
    return AudioSource(
      id: id ?? this.id,
      name: name ?? this.name,
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
      levelDb: levelDb ?? this.levelDb,
      hasLiveMeter: hasLiveMeter ?? this.hasLiveMeter,
    );
  }
}
