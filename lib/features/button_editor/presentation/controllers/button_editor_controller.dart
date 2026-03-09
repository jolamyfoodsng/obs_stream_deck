import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/macro_plan_access.dart';
import '../../../../domain/entities/button_action.dart';
import '../../../../domain/entities/controller_button.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/entities/obs_action_catalog.dart';
import '../../../../domain/entities/obs_runtime_state.dart';
import '../../../../domain/repositories/controller_repository.dart';
import '../../../../domain/repositories/macro_repository.dart';
import '../../../../domain/repositories/obs_repository.dart';
import '../../../../domain/usecases/execute_button_action_usecase.dart';
import '../../../../shared/models/action_target_option.dart';
import '../../../../shared/extensions/icon_mapper.dart';
import '../../../../shared/state/app_providers.dart';

class ButtonEditorArgs {
  const ButtonEditorArgs({
    this.buttonId,
    this.pageId,
    this.slotPosition,
  });

  final String? buttonId;
  final String? pageId;
  final int? slotPosition;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ButtonEditorArgs &&
        other.buttonId == buttonId &&
        other.pageId == pageId &&
        other.slotPosition == slotPosition;
  }

  @override
  int get hashCode => Object.hash(buttonId, pageId, slotPosition);
}

class ButtonEditorState {
  const ButtonEditorState({
    required this.button,
    required this.obsState,
    required this.isSaving,
    required this.error,
  });

  final ControllerButton button;
  final ObsRuntimeState obsState;
  final bool isSaving;
  final String? error;

  ButtonEditorState copyWith({
    ControllerButton? button,
    ObsRuntimeState? obsState,
    bool? isSaving,
    String? error,
  }) {
    return ButtonEditorState(
      button: button ?? this.button,
      obsState: obsState ?? this.obsState,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }

  factory ButtonEditorState.initial() {
    return ButtonEditorState(
      button: const ControllerButton(
        id: 'new_button',
        label: 'New Button',
        icon: 'play_arrow',
        activeColor: '#137FEC',
        inactiveColor: '#64748B',
        category: DeckButtonCategory.scene,
        action: ButtonAction(type: ButtonActionType.switchScene),
        position: 0,
      ),
      obsState: ObsRuntimeState.initial(),
      isSaving: false,
      error: null,
    );
  }
}

class ButtonEditorController extends StateNotifier<ButtonEditorState> {
  ButtonEditorController({
    required this.args,
    required ControllerRepository controllerRepository,
    required MacroRepository macroRepository,
    required ObsRepository obsRepository,
    required ExecuteButtonActionUseCase executeButtonAction,
    required Ref ref,
  })  : _controllerRepository = controllerRepository,
        _macroRepository = macroRepository,
        _obsRepository = obsRepository,
        _executeButtonAction = executeButtonAction,
        _ref = ref,
        super(ButtonEditorState.initial()) {
    _init();
  }

  final ButtonEditorArgs args;
  final ControllerRepository _controllerRepository;
  final MacroRepository _macroRepository;
  final ObsRepository _obsRepository;
  final ExecuteButtonActionUseCase _executeButtonAction;
  final Ref _ref;

  StreamSubscription? _obsSub;
  List<ControllerPage> _pages = <ControllerPage>[];
  List<MacroDefinition> _macros = <MacroDefinition>[];

  Future<void> _init() async {
    _pages = await _controllerRepository.loadPages();
    _macros = await _macroRepository.loadMacros();

    final found = _findButtonById(args.buttonId);
    if (found != null) {
      state = state.copyWith(button: found);
    } else {
      state = state.copyWith(
        button: state.button.copyWith(
          position: args.slotPosition ?? state.button.position,
        ),
      );
    }

    _obsSub = _obsRepository.watchState().listen((obsState) {
      state = state.copyWith(obsState: obsState);
      _syncCurrentActionTarget();
    });

    state = state.copyWith(
      obsState: _obsRepository.currentState(),
      error: state.error,
    );
    _syncCurrentActionTarget();
  }

  ControllerButton? _findButtonById(String? id) {
    if (id == null) return null;

    for (final page in _pages) {
      for (final button in page.buttons) {
        if (button.id == id) return button;
      }
    }

    return null;
  }

  void updateLabel(String label) {
    state = state.copyWith(button: state.button.copyWith(label: label));
  }

  void updateIcon(String iconName) {
    state = state.copyWith(button: state.button.copyWith(icon: iconName));
  }

  void updateActiveColor(String colorHex) {
    state =
        state.copyWith(button: state.button.copyWith(activeColor: colorHex));
  }

  void updateInactiveColor(String colorHex) {
    state =
        state.copyWith(button: state.button.copyWith(inactiveColor: colorHex));
  }

  void updateLongPressTrigger(bool enabled) {
    state = state.copyWith(
      button: state.button.copyWith(longPressTrigger: enabled),
    );
  }

  void updateActionType(ButtonActionType type) {
    final definition = ObsActionCatalog.definitionForButtonType(type);
    final target = _defaultTargetFor(type);

    state = state.copyWith(
      button: state.button.copyWith(
        category: _categoryForAction(type),
        action: ButtonAction(
          type: type,
          targetId: definition.requiresTarget ? target?.id : null,
          targetName: definition.requiresTarget ? target?.label : null,
          metadata: const <String, dynamic>{},
        ),
      ),
    );
  }

  void updateActionTarget(String? target) {
    final option = target == null
        ? null
        : _targetOptionForId(state.button.action.type, target);

    state = state.copyWith(
      button: state.button.copyWith(
        action: state.button.action.copyWith(
          targetId: target,
          targetName: option?.label ?? target,
        ),
      ),
    );
  }

  Future<void> testAction() {
    return _executeButtonAction(state.button.action);
  }

  Future<bool> save() async {
    if (state.button.label.trim().isEmpty) {
      state = state.copyWith(error: 'Button label is required.');
      return false;
    }

    if (isActionPremiumLocked(state.button.action.type)) {
      state = state.copyWith(
        error: 'Run Macro is available on DeckPilot Premium.',
      );
      return false;
    }

    final actionDefinition =
        ObsActionCatalog.definitionForButtonType(state.button.action.type);
    if (actionDefinition.requiresTarget) {
      final targetId = state.button.action.targetId;
      if (targetId == null || targetId.isEmpty) {
        state = state.copyWith(error: 'Select an action target.');
        return false;
      }
    }

    state = state.copyWith(isSaving: true, error: null);

    try {
      if (_pages.isEmpty) {
        _pages = await _controllerRepository.loadPages();
      }

      bool updated = false;
      final updatedPages = _pages.map((page) {
        final buttons = page.buttons.map((button) {
          if (button.id == state.button.id) {
            updated = true;
            return state.button;
          }
          return button;
        }).toList();

        return page.copyWith(buttons: buttons);
      }).toList();

      if (!updated && updatedPages.isNotEmpty) {
        final targetPageIndex = args.pageId == null
            ? 0
            : updatedPages.indexWhere((page) => page.id == args.pageId);
        final pageIndex = targetPageIndex >= 0 ? targetPageIndex : 0;
        final targetPage = updatedPages[pageIndex];
        final targetSlot = args.slotPosition;
        final nextPosition = targetSlot ?? targetPage.buttons.length;
        final newButton = state.button.copyWith(
          id: 'btn_${DateTime.now().millisecondsSinceEpoch}',
          position: nextPosition,
        );

        final pageButtons = <ControllerButton>[...targetPage.buttons];
        final replaceIndex = targetSlot == null
            ? -1
            : pageButtons.indexWhere((button) => button.position == targetSlot);

        if (replaceIndex >= 0) {
          pageButtons[replaceIndex] = newButton;
        } else {
          pageButtons.add(newButton);
        }

        updatedPages[pageIndex] = targetPage.copyWith(
          buttons: pageButtons,
        );
      }

      await _controllerRepository.savePages(updatedPages);
      _pages = updatedPages;
      state = state.copyWith(isSaving: false);
      return true;
    } catch (_) {
      state = state.copyWith(isSaving: false, error: 'Failed to save button.');
      return false;
    }
  }

  List<String> availableIcons() => IconMapper.availableIcons();

  List<ButtonActionType> availableActionTypes() {
    return ObsActionCatalog.buttonActions();
  }

  bool isActionPremiumLocked(ButtonActionType type) {
    return false;
  }

  ObsActionDefinition actionDefinition(ButtonActionType type) {
    return ObsActionCatalog.definitionForButtonType(type);
  }

  String labelForActionType(ButtonActionType type) {
    return ObsActionCatalog.definitionForButtonType(type).label;
  }

  String targetFieldLabel(ButtonActionType type) {
    final definition = ObsActionCatalog.definitionForButtonType(type);
    switch (definition.targetKind) {
      case ObsActionTargetKind.scene:
        return 'Scene Target';
      case ObsActionTargetKind.source:
        return 'Source Target';
      case ObsActionTargetKind.audioSource:
        return 'Audio Target';
      case ObsActionTargetKind.macro:
        return 'Macro Target';
      case ObsActionTargetKind.none:
      case ObsActionTargetKind.delayMs:
        return 'Action Target';
    }
  }

  List<ActionTargetOption> availableTargets(ButtonActionType type) {
    final definition = ObsActionCatalog.definitionForButtonType(type);
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
        return MacroPlanAccess.accessibleMacros(
          isPremium: _ref.read(premiumControllerProvider).isPremium,
          macros: _macros,
        )
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

  String labelForTarget(ButtonActionType type, String targetId) {
    final option = _targetOptionForId(type, targetId);
    if (option != null) {
      return option.label;
    }

    final action = state.button.action;
    if (action.targetId == targetId && action.targetName != null) {
      return action.targetName!;
    }

    return targetId;
  }

  DeckButtonCategory _categoryForAction(ButtonActionType type) {
    final definition = ObsActionCatalog.definitionForButtonType(type);
    switch (definition.code) {
      case ObsActionCode.switchScene:
      case ObsActionCode.setPreviewScene:
        return DeckButtonCategory.scene;
      case ObsActionCode.showSource:
      case ObsActionCode.hideSource:
      case ObsActionCode.toggleSourceVisibility:
        return DeckButtonCategory.source;
      case ObsActionCode.mute:
      case ObsActionCode.unmute:
      case ObsActionCode.toggleMute:
        return DeckButtonCategory.audio;
      case ObsActionCode.startStream:
      case ObsActionCode.stopStream:
      case ObsActionCode.toggleStream:
        return DeckButtonCategory.stream;
      case ObsActionCode.startRecording:
      case ObsActionCode.stopRecording:
      case ObsActionCode.pauseRecording:
      case ObsActionCode.resumeRecording:
      case ObsActionCode.toggleRecording:
        return DeckButtonCategory.recording;
      case ObsActionCode.startVirtualCamera:
      case ObsActionCode.stopVirtualCamera:
      case ObsActionCode.toggleVirtualCamera:
      case ObsActionCode.enableStudioMode:
      case ObsActionCode.disableStudioMode:
      case ObsActionCode.toggleStudioMode:
        return DeckButtonCategory.utility;
      case ObsActionCode.runMacro:
        return DeckButtonCategory.macro;
      case ObsActionCode.delay:
        return DeckButtonCategory.utility;
    }
  }

  ActionTargetOption? _targetOptionForId(
      ButtonActionType type, String targetId) {
    return availableTargets(type)
        .where((item) => item.id == targetId)
        .firstOrNull;
  }

  ActionTargetOption? _defaultTargetFor(ButtonActionType type) {
    return availableTargets(type).firstOrNull;
  }

  void _syncCurrentActionTarget() {
    final action = state.button.action;
    final definition = ObsActionCatalog.definitionForButtonType(action.type);

    if (!definition.requiresTarget) {
      if (action.targetId == null && action.targetName == null) return;
      state = state.copyWith(
        button: state.button.copyWith(
          action: action.copyWith(targetId: null, targetName: null),
        ),
      );
      return;
    }

    final targets = availableTargets(action.type);
    if (targets.isEmpty) return;

    final selected = action.targetId == null
        ? null
        : targets.where((item) => item.id == action.targetId).firstOrNull;
    final resolved = selected ?? targets.first;

    if (resolved.id == action.targetId && resolved.label == action.targetName) {
      return;
    }

    state = state.copyWith(
      button: state.button.copyWith(
        action: action.copyWith(
          targetId: resolved.id,
          targetName: resolved.label,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _obsSub?.cancel();
    super.dispose();
  }
}

final buttonEditorControllerProvider = StateNotifierProvider.autoDispose
    .family<ButtonEditorController, ButtonEditorState, ButtonEditorArgs>(
        (ref, args) {
  return ButtonEditorController(
    args: args,
    controllerRepository: ref.watch(controllerRepositoryProvider),
    macroRepository: ref.watch(macroRepositoryProvider),
    obsRepository: ref.watch(obsRepositoryProvider),
    executeButtonAction: ref.watch(executeButtonActionUseCaseProvider),
    ref: ref,
  );
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
