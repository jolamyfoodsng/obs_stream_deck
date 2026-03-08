class SourceItem {
  const SourceItem({
    required this.id,
    required this.name,
    required this.sceneId,
    required this.isVisible,
  });

  final String id;
  final String name;
  final String sceneId;
  final bool isVisible;

  SourceItem copyWith({
    String? id,
    String? name,
    String? sceneId,
    bool? isVisible,
  }) {
    return SourceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      sceneId: sceneId ?? this.sceneId,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}
