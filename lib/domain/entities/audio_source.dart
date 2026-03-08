class AudioSource {
  const AudioSource({
    required this.id,
    required this.name,
    required this.isMuted,
    required this.volume,
  });

  final String id;
  final String name;
  final bool isMuted;
  final double volume;

  AudioSource copyWith({
    String? id,
    String? name,
    bool? isMuted,
    double? volume,
  }) {
    return AudioSource(
      id: id ?? this.id,
      name: name ?? this.name,
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
    );
  }
}
