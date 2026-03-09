import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/domain/usecases/run_macro_usecase.dart';

import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';

void main() {
  group('Macro execution', () {
    test('runs macro steps in order and updates OBS state', () async {
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);
      fakeObs.seedMacros(<MacroDefinition>[sampleMacro()]);

      final useCase = RunMacroUseCase(fakeObs);
      await useCase('macro_start_service');

      expect(
        fakeObs.actionLog,
        containsAllInOrder(<String>[
          'step:switchScene:scene_0',
          'action:switchScene:scene_0',
          'step:delay:',
          'step:startStream:',
          'action:startStream:',
        ]),
      );
      expect(fakeObs.currentState().currentScene, 'Scene 1');
      expect(fakeObs.currentState().streamStatus.name, 'live');
    });

    test('surfaces OBS action failures while running a macro', () async {
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);
      fakeObs.actionFailures[ButtonActionType.startStream] = 'Stream failed';
      fakeObs.seedMacros(<MacroDefinition>[sampleMacro()]);

      final useCase = RunMacroUseCase(fakeObs);
      expect(
        () => useCase('macro_start_service'),
        throwsA(isA<Exception>()),
      );
    });

    test('delay steps wait before continuing', () async {
      final macro = sampleMacro(
        steps: const <MacroAction>[
          MacroAction(id: 's1', type: MacroActionType.delay, delayMs: 30),
          MacroAction(id: 's2', type: MacroActionType.startStream),
        ],
      );
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);
      fakeObs.seedMacros(<MacroDefinition>[macro]);
      final stopwatch = Stopwatch()..start();

      await RunMacroUseCase(fakeObs)('macro_start_service');
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(25));
      expect(fakeObs.currentState().streamStatus.name, 'live');
    });
  });
}
