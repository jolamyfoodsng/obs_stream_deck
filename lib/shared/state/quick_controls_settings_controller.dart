import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../domain/entities/quick_control.dart';

class QuickControlsSettings {
  const QuickControlsSettings({
    required this.enabledControls,
  });

  final Set<QuickControlId> enabledControls;

  QuickControlsSettings copyWith({
    Set<QuickControlId>? enabledControls,
  }) {
    return QuickControlsSettings(
      enabledControls: enabledControls ?? this.enabledControls,
    );
  }

  List<QuickControlId> visibleControls({required bool isPremium}) {
    if (!isPremium) return defaultQuickControls;
    return QuickControlId.values
        .where(enabledControls.contains)
        .toList(growable: false);
  }
}

class QuickControlsSettingsController
    extends StateNotifier<QuickControlsSettings> {
  QuickControlsSettingsController(this._storage)
      : super(
          QuickControlsSettings(
            enabledControls: _loadInitialState(_storage),
          ),
        );

  final LocalStorageService _storage;

  static Set<QuickControlId> _loadInitialState(LocalStorageService storage) {
    final stored =
        storage.getStringListOrNull(StorageKeys.quickControlsEnabled);
    if (stored == null) {
      return defaultQuickControls.toSet();
    }

    final enabled = quickControlIdsFromNames(stored);
    const previousDefaults = <QuickControlId>{
      QuickControlId.muteMic,
      QuickControlId.stream,
      QuickControlId.recording,
    };
    if (enabled.length == previousDefaults.length &&
        enabled.containsAll(previousDefaults)) {
      return <QuickControlId>{
        ...enabled,
        QuickControlId.studioMode,
      };
    }

    return enabled;
  }

  Future<void> setEnabled(QuickControlId control, bool enabled) async {
    final next = <QuickControlId>{...state.enabledControls};
    if (enabled) {
      next.add(control);
    } else {
      next.remove(control);
    }
    state = state.copyWith(enabledControls: next);
    await _storage.setStringList(
      StorageKeys.quickControlsEnabled,
      quickControlNamesFromIds(next),
    );
  }
}
