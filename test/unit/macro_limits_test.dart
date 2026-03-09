import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/features/macro_editor/presentation/controllers/macro_editor_controller.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_macro_repository.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_container.dart';

void main() {
  group('Macro limits', () {
    test('free plan blocks fourth macro action', () async {
      final prefs = await buildTestPreferences();
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: FakeObsRepository(),
        macroRepository: FakeMacroRepository(),
      );
      final subscription = container.listen(
        macroEditorControllerProvider(null),
        (_, __) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final controller =
          container.read(macroEditorControllerProvider(null).notifier);
      await settleContainer();

      expect(controller.addStep(MacroActionType.switchScene), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.startStream), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.startRecording), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.mute), MacroStepAddResult.blockedByPremium);
    });

    test('free plan blocks creating a second user macro', () async {
      final prefs = await buildTestPreferences();
      final repo = FakeMacroRepository(
        macros: <MacroDefinition>[sampleMacro(id: 'macro_existing')],
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: FakeObsRepository(),
        macroRepository: repo,
      );
      final subscription = container.listen(
        macroEditorControllerProvider(null),
        (_, __) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final controller =
          container.read(macroEditorControllerProvider(null).notifier);
      await settleContainer();

      expect(controller.canCreateMacro, isFalse);
      final result = await controller.save();
      expect(result, MacroSaveResult.blockedByPremium);
    });

    test('premium plan allows more than three macro actions', () async {
      final prefs = await buildTestPreferences(<String, Object>{
        'premium_unlocked': true,
      });
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: FakeObsRepository(),
        macroRepository: FakeMacroRepository(),
      );
      final subscription = container.listen(
        macroEditorControllerProvider(null),
        (_, __) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final controller =
          container.read(macroEditorControllerProvider(null).notifier);
      await settleContainer();

      expect(controller.addStep(MacroActionType.switchScene), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.startStream), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.startRecording), MacroStepAddResult.added);
      expect(controller.addStep(MacroActionType.mute), MacroStepAddResult.added);
    });
  });
}
