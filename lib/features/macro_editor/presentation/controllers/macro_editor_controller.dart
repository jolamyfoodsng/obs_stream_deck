import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/macro_plan_access.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/entities/obs_action_catalog.dart';
import '../../../../domain/entities/obs_runtime_state.dart';
import '../../../../domain/repositories/macro_repository.dart';
import '../../../../domain/repositories/obs_repository.dart';
import '../../../../domain/usecases/run_macro_usecase.dart';
import '../../../../shared/models/action_target_option.dart';
import '../../../../shared/state/app_providers.dart';

class MacroEditorState {
  const MacroEditorState({
    required this.macro,
    required this.obsState,
    required this.isSaving,
  });

  final MacroDefinition macro;
  final ObsRuntimeState obsState;
  final bool isSaving;

  MacroEditorState copyWith({
    MacroDefinition? macro,
    ObsRuntimeState? obsState,
    bool? isSaving,
  }) {
    return MacroEditorState(
      macro: macro ?? this.macro,
      obsState: obsState ?? this.obsState,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  factory MacroEditorState.initial() {
    return MacroEditorState(
      macro: const MacroDefinition(
        id: 'macro_new',
        name: 'New Macro',
        icon: 'bolt',
        colorHex: '#8B5CF6',
        steps: <MacroAction>[],
      ),
      obsState: ObsRuntimeState.initial(),
      isSaving: false,
    );
  }
}

enum MacroStepAddResult {
  added,
  blockedByPremium,
}

enum MacroSaveResult {
  success,
  validationFailed,
  blockedByPremium,
  failed,
}

class MacroEditorController extends StateNotifier<MacroEditorState> {
  MacroEditorController({
    required this.macroId,
    required Ref ref,
    required MacroRepository macroRepository,
    required ObsRepository obsRepository,
    required RunMacroUseCase runMacro,
  })  : _macroRepository = macroRepository,
        _ref = ref,
        _obsRepository = obsRepository,
        _runMacro = runMacro,
        super(MacroEditorState.initial()) {
    _init();
  }

  final String? macroId;
  final MacroRepository _macroRepository;
  final Ref _ref;
  final ObsRepository _obsRepository;
  final RunMacroUseCase _runMacro;

  StreamSubscription? _obsSub;
  List<MacroDefinition> _macros = <MacroDefinition>[];

  Future<void> _init() async {
    _macros = await _macroRepository.loadMacros();

    final selected = _macros.where((macro) => macro.id == macroId).firstOrNull;
    if (selected != null) {
      state = state.copyWith(macro: selected);
    }

    _obsSub = _obsRepository.watchState().listen((obsState) {
      state = state.copyWith(obsState: obsState);
      _syncStepTargets();
    });

    state = state.copyWith(obsState: _obsRepository.currentState());
    _syncStepTargets();
  }

  void updateName(String value) {
    state = state.copyWith(macro: state.macro.copyWith(name: value));
  }

  void updateIcon(String icon) {
    state = state.copyWith(macro: state.macro.copyWith(icon: icon));
  }

  void updateColor(String colorHex) {
    state = state.copyWith(macro: state.macro.copyWith(colorHex: colorHex));
  }

  MacroStepAddResult addStep(MacroActionType type) {
    if (!canAddAnotherStep) {
      return MacroStepAddResult.blockedByPremium;
    }
    final target = _defaultTargetFor(type);
    final step = MacroAction(
      id: 'step_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      targetId: target?.id,
      targetName: target?.label,
      delayMs: type == MacroActionType.delay ? 1000 : null,
    );

    state = state.copyWith(
      macro: state.macro
          .copyWith(steps: <MacroAction>[...state.macro.steps, step]),
    );
    return MacroStepAddResult.added;
  }

  void removeStep(String stepId) {
    state = state.copyWith(
      macro: state.macro.copyWith(
        steps: state.macro.steps.where((step) => step.id != stepId).toList(),
      ),
    );
  }

  void reorderSteps(int oldIndex, int newIndex) {
    final steps = <MacroAction>[...state.macro.steps];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = steps.removeAt(oldIndex);
    steps.insert(newIndex, item);
    state = state.copyWith(macro: state.macro.copyWith(steps: steps));
  }

  void updateStepTarget({
    required String stepId,
    required String? targetId,
  }) {
    final updated = state.macro.steps.map((step) {
      if (step.id != stepId) return step;
      final label =
          targetId == null ? null : labelForTarget(step.type, targetId);
      return step.copyWith(
        targetId: targetId,
        targetName: label ?? targetId,
      );
    }).toList(growable: false);

    state = state.copyWith(macro: state.macro.copyWith(steps: updated));
  }

  void updateStepDelay({
    required String stepId,
    required int delayMs,
  }) {
    final safeDelay = delayMs.clamp(0, 300000);
    final updated = state.macro.steps.map((step) {
      if (step.id != stepId) return step;
      return step.copyWith(delayMs: safeDelay);
    }).toList(growable: false);

    state = state.copyWith(macro: state.macro.copyWith(steps: updated));
  }

  Future<void> testMacro() {
    return _runMacro(state.macro.id);
  }

  Future<MacroSaveResult> save() async {
    final name = state.macro.name.trim();
    if (name.isEmpty) return MacroSaveResult.validationFailed;
    if (isLockedForCurrentPlan) return MacroSaveResult.blockedByPremium;
    if (!_isPremiumUser &&
        state.macro.steps.length > freeActionLimit) {
      return MacroSaveResult.blockedByPremium;
    }
    if (isNewMacro && !canCreateMacro) {
      return MacroSaveResult.blockedByPremium;
    }

    state = state.copyWith(isSaving: true);

    try {
      bool updated = false;
      final macros = _macros.map((macro) {
        if (macro.id == state.macro.id) {
          updated = true;
          return state.macro;
        }
        return macro;
      }).toList();

      if (!updated) {
        macros.add(
          state.macro
              .copyWith(id: 'macro_${DateTime.now().millisecondsSinceEpoch}'),
        );
      }

      await _macroRepository.saveMacros(macros);
      _macros = macros;
      state = state.copyWith(isSaving: false);
      return MacroSaveResult.success;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return MacroSaveResult.failed;
    }
  }

  List<MacroActionType> availableActionTypes() {
    return ObsActionCatalog.macroActions();
  }

  ObsActionDefinition actionDefinition(MacroActionType type) {
    return ObsActionCatalog.definitionForMacroType(type);
  }

  String labelForActionType(MacroActionType type) {
    return ObsActionCatalog.definitionForMacroType(type).label;
  }

  List<ActionTargetOption> availableTargets(MacroActionType type) {
    final definition = ObsActionCatalog.definitionForMacroType(type);
    switch (definition.targetKind) {
      case ObsActionTargetKind.scene:
        return state.obsState.scenes
            .map(
              (scene) => ActionTargetOption(
                id: scene.id,
                label: scene.name,
              ),
            )
            .toList(growable: false);
      case ObsActionTargetKind.source:
        return state.obsState.sources
            .map(
              (source) => ActionTargetOption(
                id: source.id,
                label: '${source.name} (${source.sceneId})',
              ),
            )
            .toList(growable: false);
      case ObsActionTargetKind.audioSource:
        return state.obsState.audioSources
            .map(
              (source) => ActionTargetOption(
                id: source.id,
                label: source.name,
              ),
            )
            .toList(growable: false);
      case ObsActionTargetKind.macro:
        return accessibleMacros
            .where((macro) => macro.id != state.macro.id)
            .map(
              (macro) => ActionTargetOption(
                id: macro.id,
                label: macro.name,
              ),
            )
            .toList(growable: false);
      case ObsActionTargetKind.none:
      case ObsActionTargetKind.delayMs:
        return const <ActionTargetOption>[];
    }
  }

  String? labelForTarget(MacroActionType type, String targetId) {
    return availableTargets(type)
            .where((target) => target.id == targetId)
            .map((target) => target.label)
            .firstOrNull ??
        targetId;
  }

  ActionTargetOption? _defaultTargetFor(MacroActionType type) {
    return availableTargets(type).firstOrNull;
  }

  bool get isNewMacro => macroId == null || state.macro.id == 'macro_new';

  bool get _isPremiumUser => _ref.read(premiumControllerProvider).isPremium;

  int get freeActionLimit => AppConstants.freeMacroActionLimit;

  List<MacroDefinition> get accessibleMacros => MacroPlanAccess.accessibleMacros(
        isPremium: _isPremiumUser,
        macros: _macros,
      );

  bool get canCreateMacro => MacroPlanAccess.canCreateMacro(
        isPremium: _isPremiumUser,
        macros: _macros,
      );

  bool get canAddAnotherStep => !isLockedForCurrentPlan &&
      MacroPlanAccess.canAddStep(
        isPremium: _isPremiumUser,
        macro: state.macro,
      );

  bool get isLockedForCurrentPlan {
    if (_isPremiumUser) return false;
    if (state.macro.steps.length > freeActionLimit) return true;
    if (isNewMacro) return !canCreateMacro;

    return MacroPlanAccess.isLockedForFreePlan(
      isPremium: _isPremiumUser,
      macros: _macros,
      macro: state.macro,
    );
  }

  void _syncStepTargets() {
    if (state.macro.steps.isEmpty) return;

    var changed = false;
    final updatedSteps = state.macro.steps.map((step) {
      final definition = ObsActionCatalog.definitionForMacroType(step.type);

      if (!definition.requiresTarget) {
        if (step.targetId == null && step.targetName == null) {
          return step;
        }
        changed = true;
        return step.copyWith(targetId: null, targetName: null);
      }

      final targets = availableTargets(step.type);
      if (targets.isEmpty) {
        return step;
      }

      final selected = step.targetId == null
          ? null
          : targets.where((target) => target.id == step.targetId).firstOrNull;
      final resolved = selected ?? targets.first;

      if (resolved.id == step.targetId && resolved.label == step.targetName) {
        return step;
      }

      changed = true;
      return step.copyWith(targetId: resolved.id, targetName: resolved.label);
    }).toList(growable: false);

    if (!changed) return;
    state = state.copyWith(macro: state.macro.copyWith(steps: updatedSteps));
  }

  @override
  void dispose() {
    _obsSub?.cancel();
    super.dispose();
  }
}

final macroEditorControllerProvider = StateNotifierProvider.autoDispose
    .family<MacroEditorController, MacroEditorState, String?>((ref, macroId) {
  return MacroEditorController(
    macroId: macroId,
    ref: ref,
    macroRepository: ref.watch(macroRepositoryProvider),
    obsRepository: ref.watch(obsRepositoryProvider),
    runMacro: ref.watch(runMacroUseCaseProvider),
  );
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
