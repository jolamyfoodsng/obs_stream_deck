class SceneItem {
  const SceneItem({
    required this.id,
    required this.name,
    this.isProgram = false,
    this.isPreview = false,
  });

  final String id;
  final String name;
  final bool isProgram;
  final bool isPreview;

  SceneItem copyWith({
    String? id,
    String? name,
    bool? isProgram,
    bool? isPreview,
  }) {
    return SceneItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isProgram: isProgram ?? this.isProgram,
      isPreview: isPreview ?? this.isPreview,
    );
  }
}
