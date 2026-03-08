class DeckButtonRuntimeState {
  const DeckButtonRuntimeState({
    required this.enabled,
    required this.active,
    this.pending = false,
    this.hasError = false,
  });

  final bool enabled;
  final bool active;
  final bool pending;
  final bool hasError;
}
