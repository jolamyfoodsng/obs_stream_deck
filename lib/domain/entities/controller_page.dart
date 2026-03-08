import 'controller_button.dart';

class ControllerPage {
  const ControllerPage({
    required this.id,
    required this.name,
    required this.columns,
    required this.rows,
    required this.buttons,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final int columns;
  final int rows;
  final List<ControllerButton> buttons;
  final bool isDefault;

  int get buttonCount => buttons.length;

  ControllerPage copyWith({
    String? id,
    String? name,
    int? columns,
    int? rows,
    List<ControllerButton>? buttons,
    bool? isDefault,
  }) {
    return ControllerPage(
      id: id ?? this.id,
      name: name ?? this.name,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      buttons: buttons ?? this.buttons,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
