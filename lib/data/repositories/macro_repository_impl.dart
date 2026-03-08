import '../../data/datasources/macro_local_datasource.dart';
import '../../domain/entities/macro_definition.dart';
import '../../domain/repositories/macro_repository.dart';

class MacroRepositoryImpl implements MacroRepository {
  MacroRepositoryImpl(this._dataSource);

  final MacroLocalDataSource _dataSource;

  @override
  Future<List<MacroDefinition>> loadMacros() async {
    final saved = await _dataSource.loadMacros();
    final ensured = _ensureSystemMacros(saved);

    final changed = saved.isEmpty || ensured.length != saved.length;
    if (changed) {
      await _dataSource.saveMacros(ensured);
    }

    return ensured;
  }

  @override
  Future<void> saveMacros(List<MacroDefinition> macros) =>
      _dataSource.saveMacros(macros);

  List<MacroDefinition> _ensureSystemMacros(List<MacroDefinition> macros) {
    var updated = <MacroDefinition>[...macros];

    final hasRestart =
        updated.any((macro) => macro.id == 'macro_restart_stream');
    if (!hasRestart) {
      updated = <MacroDefinition>[
        ...updated,
        const MacroDefinition(
          id: 'macro_restart_stream',
          name: 'Restart Stream',
          icon: 'autorenew',
          colorHex: '#EF4444',
          steps: <MacroAction>[
            MacroAction(
              id: 'restart_stream_step_1',
              type: MacroActionType.stopStream,
            ),
            MacroAction(
              id: 'restart_stream_step_2',
              type: MacroActionType.delay,
              delayMs: 2000,
            ),
            MacroAction(
              id: 'restart_stream_step_3',
              type: MacroActionType.startStream,
            ),
          ],
        ),
      ];
    }

    final hasEmergencyReset =
        updated.any((macro) => macro.id == 'macro_emergency_reset');
    if (!hasEmergencyReset) {
      updated = <MacroDefinition>[
        ...updated,
        const MacroDefinition(
          id: 'macro_emergency_reset',
          name: 'Emergency Reset',
          icon: 'warning',
          colorHex: '#EF4444',
          steps: <MacroAction>[
            MacroAction(
              id: 'emergency_reset_step_1',
              type: MacroActionType.stopRecording,
            ),
            MacroAction(
              id: 'emergency_reset_step_2',
              type: MacroActionType.stopStream,
            ),
          ],
        ),
      ];
    }

    return updated;
  }
}
