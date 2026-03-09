enum QuickControlId {
  muteMic,
  stream,
  recording,
  virtualCamera,
  studioMode,
}

extension QuickControlIdX on QuickControlId {
  String get settingsLabel {
    switch (this) {
      case QuickControlId.muteMic:
        return 'Mute / Unmute Mic';
      case QuickControlId.stream:
        return 'Start / Stop Stream';
      case QuickControlId.recording:
        return 'Start / Stop Recording';
      case QuickControlId.virtualCamera:
        return 'Virtual Camera';
      case QuickControlId.studioMode:
        return 'Studio Mode';
    }
  }

  String get settingsDescription {
    switch (this) {
      case QuickControlId.muteMic:
        return 'State-aware microphone mute control.';
      case QuickControlId.stream:
        return 'State-aware stream start and stop control.';
      case QuickControlId.recording:
        return 'State-aware recording start and stop control.';
      case QuickControlId.virtualCamera:
        return 'Start or stop the OBS virtual camera.';
      case QuickControlId.studioMode:
        return 'Enable or disable OBS Studio Mode.';
    }
  }

  bool get premiumOnly {
    switch (this) {
      case QuickControlId.virtualCamera:
        return true;
      case QuickControlId.studioMode:
      case QuickControlId.muteMic:
      case QuickControlId.stream:
      case QuickControlId.recording:
        return false;
    }
  }

  bool get enabledByDefault => !premiumOnly;
}

List<QuickControlId> get defaultQuickControls => QuickControlId.values
    .where((control) => control.enabledByDefault)
    .toList(growable: false);

Set<QuickControlId> quickControlIdsFromNames(Iterable<String> rawValues) {
  final normalized = rawValues.map((value) => value.trim()).toSet();
  return QuickControlId.values
      .where((control) => normalized.contains(control.name))
      .toSet();
}

List<String> quickControlNamesFromIds(Iterable<QuickControlId> ids) {
  final enabled = ids.toSet();
  return QuickControlId.values
      .where(enabled.contains)
      .map((control) => control.name)
      .toList(growable: false);
}
