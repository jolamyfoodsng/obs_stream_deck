import 'dart:async';

class FakeStreamHealthMonitor {
  final StreamController<List<String>> _warningsController =
      StreamController<List<String>>.broadcast();

  List<String> currentWarnings = <String>[];

  Stream<List<String>> get warningsStream async* {
    yield currentWarnings;
    yield* _warningsController.stream;
  }

  void emit(List<String> warnings) {
    currentWarnings = List<String>.from(warnings);
    _warningsController.add(currentWarnings);
  }

  void dispose() {
    _warningsController.close();
  }
}
