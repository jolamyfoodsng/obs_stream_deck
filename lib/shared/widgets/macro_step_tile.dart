import 'package:flutter/material.dart';

import '../../domain/entities/macro_definition.dart';

class MacroStepTile extends StatelessWidget {
  const MacroStepTile({
    super.key,
    required this.index,
    required this.step,
    this.onDelete,
  });

  final int index;
  final MacroAction step;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text('${index + 1}'),
        ),
        title: Text(step.type.name),
        subtitle: Text(
          step.type == MacroActionType.delay
              ? 'Delay: ${step.delayMs ?? 0} ms'
              : 'Target: ${step.targetId ?? '-'}',
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}
