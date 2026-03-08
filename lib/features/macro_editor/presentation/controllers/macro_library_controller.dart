import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/button_action.dart';
import '../../../../domain/entities/controller_button.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/repositories/controller_repository.dart';
import '../../../../domain/repositories/macro_repository.dart';
import '../../../../domain/usecases/run_macro_usecase.dart';
import '../../../../shared/state/app_providers.dart';

class MacroLibraryState {
  const MacroLibraryState({
    required this.macros,
    required this.pages,
    this.runningMacroIds = const <String>{},
    this.isLoading = false,
  });

  final List<MacroDefinition> macros;
  final List<ControllerPage> pages;
  final Set<String> runningMacroIds;
  final bool isLoading;

  MacroLibraryState copyWith({
    List<MacroDefinition>? macros,
    List<ControllerPage>? pages,
    Set<String>? runningMacroIds,
    bool? isLoading,
  }) {
    return MacroLibraryState(
      macros: macros ?? this.macros,
      pages: pages ?? this.pages,
      runningMacroIds: runningMacroIds ?? this.runningMacroIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  factory MacroLibraryState.initial() {
    return const MacroLibraryState(
      macros: <MacroDefinition>[],
      pages: <ControllerPage>[],
      isLoading: true,
    );
  }
}

class MacroLibraryController extends StateNotifier<MacroLibraryState> {
  MacroLibraryController({
    required MacroRepository macroRepository,
    required ControllerRepository controllerRepository,
    required RunMacroUseCase runMacro,
  })  : _macroRepository = macroRepository,
        _controllerRepository = controllerRepository,
        _runMacro = runMacro,
        super(MacroLibraryState.initial()) {
    unawaited(refresh());
  }

  final MacroRepository _macroRepository;
  final ControllerRepository _controllerRepository;
  final RunMacroUseCase _runMacro;

  static const Set<String> _protectedMacroIds = <String>{
    'macro_restart_stream',
    'macro_emergency_reset',
  };

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final macros = await _macroRepository.loadMacros();
    final pages = await _controllerRepository.loadPages();
    state = state.copyWith(
      macros: macros,
      pages: pages,
      isLoading: false,
    );
  }

  Future<void> testMacro(String macroId) async {
    final nextRunning = <String>{...state.runningMacroIds, macroId};
    state = state.copyWith(runningMacroIds: nextRunning);
    try {
      await _runMacro(macroId);
    } finally {
      final updated = <String>{...state.runningMacroIds}..remove(macroId);
      state = state.copyWith(runningMacroIds: updated);
    }
  }

  Future<void> duplicateMacro(String macroId) async {
    final macro = state.macros.where((item) => item.id == macroId).firstOrNull;
    if (macro == null) return;

    final duplicateName = _nextDuplicateName(macro.name, state.macros);
    final duplicate = macro.copyWith(
      id: 'macro_${DateTime.now().microsecondsSinceEpoch}',
      name: duplicateName,
      steps: macro.steps
          .map(
            (step) => step.copyWith(
              id: 'step_${DateTime.now().microsecondsSinceEpoch}_${step.id}',
            ),
          )
          .toList(growable: false),
    );

    final updated = <MacroDefinition>[...state.macros, duplicate];
    await _macroRepository.saveMacros(updated);
    state = state.copyWith(macros: updated);
  }

  Future<void> deleteMacro(String macroId) async {
    if (_protectedMacroIds.contains(macroId)) {
      throw Exception('This macro is system-managed and cannot be deleted.');
    }

    final updated = state.macros.where((item) => item.id != macroId).toList();
    await _macroRepository.saveMacros(updated);
    state = state.copyWith(macros: updated);
  }

  Future<void> assignMacroToSlot({
    required MacroDefinition macro,
    required String pageId,
    required int slotIndex,
    String? customLabel,
  }) async {
    final pageIndex = state.pages.indexWhere((page) => page.id == pageId);
    if (pageIndex < 0) {
      throw Exception('Target page not found.');
    }

    final pages = <ControllerPage>[...state.pages];
    final page = pages[pageIndex];
    final pageButtons = <ControllerButton>[...page.buttons];

    final label = (customLabel == null || customLabel.trim().isEmpty)
        ? macro.name
        : customLabel.trim();

    final action = ButtonAction(
      type: ButtonActionType.runMacro,
      targetId: macro.id,
      targetName: macro.name,
    );

    final existingIndex =
        pageButtons.indexWhere((button) => button.position == slotIndex);

    if (existingIndex >= 0) {
      final existing = pageButtons[existingIndex];
      pageButtons[existingIndex] = existing.copyWith(
        label: label,
        icon: macro.icon,
        activeColor: macro.colorHex,
        inactiveColor: '#64748B',
        category: DeckButtonCategory.macro,
        action: action,
      );
    } else {
      pageButtons.add(
        ControllerButton(
          id: 'btn_${DateTime.now().microsecondsSinceEpoch}',
          label: label,
          icon: macro.icon,
          activeColor: macro.colorHex,
          inactiveColor: '#64748B',
          category: DeckButtonCategory.macro,
          action: action,
          position: slotIndex,
        ),
      );
    }

    final configuredSlots = page.columns * page.rows;
    final highestPosition =
        pageButtons.map((button) => button.position).fold<int>(-1, _max);
    final requiredRows =
        ((highestPosition + 1 + page.columns - 1) / page.columns).ceil();
    final minRows = configuredSlots <= 0
        ? AppConstants.defaultPageRows
        : (configuredSlots / page.columns).ceil();
    final nextRows = requiredRows > minRows ? requiredRows : minRows;

    pages[pageIndex] = page.copyWith(
      buttons: pageButtons,
      rows: nextRows,
    );

    await _controllerRepository.savePages(pages);
    state = state.copyWith(pages: pages);
  }

  int maxAssignableSlotsForPage(ControllerPage page) {
    final configured = page.columns * page.rows;
    final nextFreePosition = page.buttons.isEmpty
        ? 0
        : page.buttons.map((button) => button.position).fold<int>(-1, _max) +
            1;
    return configured > nextFreePosition ? configured : nextFreePosition;
  }

  bool isSystemMacro(String macroId) => _protectedMacroIds.contains(macroId);

  String _nextDuplicateName(String base, List<MacroDefinition> macros) {
    final names = macros.map((macro) => macro.name.toLowerCase()).toSet();
    final trimmed = base.trim();
    var candidate = '$trimmed Copy';
    var counter = 2;

    while (names.contains(candidate.toLowerCase())) {
      candidate = '$trimmed Copy $counter';
      counter += 1;
    }

    return candidate;
  }

  static int _max(int a, int b) => a > b ? a : b;
}

final macroLibraryControllerProvider =
    StateNotifierProvider<MacroLibraryController, MacroLibraryState>((ref) {
  return MacroLibraryController(
    macroRepository: ref.watch(macroRepositoryProvider),
    controllerRepository: ref.watch(controllerRepositoryProvider),
    runMacro: ref.watch(runMacroUseCaseProvider),
  );
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
