import '../../domain/entities/controller_page.dart';
import 'controller_button_model.dart';

class ControllerPageModel {
  const ControllerPageModel._();

  static Map<String, dynamic> toJson(ControllerPage page) {
    return <String, dynamic>{
      'id': page.id,
      'name': page.name,
      'columns': page.columns,
      'rows': page.rows,
      'isDefault': page.isDefault,
      'buttons': page.buttons
          .map((button) => ControllerButtonModel.toJson(button))
          .toList(),
    };
  }

  static ControllerPage fromJson(Map<String, dynamic> json) {
    return ControllerPage(
      id: json['id'] as String,
      name: json['name'] as String,
      columns: (json['columns'] as num).toInt(),
      rows: (json['rows'] as num).toInt(),
      isDefault: json['isDefault'] as bool? ?? false,
      buttons: ((json['buttons'] as List?) ?? <dynamic>[])
          .map((entry) => ControllerButtonModel.fromJson(
                (entry as Map).cast<String, dynamic>(),
              ))
          .toList(),
    );
  }
}
