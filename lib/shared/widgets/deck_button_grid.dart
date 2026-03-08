import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/entities/controller_button.dart';
import '../state/deck_button_runtime_state.dart';
import 'deck_button.dart';

class DeckButtonGrid extends StatelessWidget {
  const DeckButtonGrid({
    super.key,
    required this.buttons,
    required this.columns,
    required this.rows,
    required this.showEmptySlots,
    required this.resolveButtonState,
    required this.onButtonTap,
    required this.onButtonLongPress,
    this.selectedButtonId,
    this.showHoldBadges = false,
    this.onEmptySlotTap,
    this.childAspectRatio = 1,
    this.thumbnailForButton,
    this.allowDisabledButtonInteraction = false,
  });

  final List<ControllerButton> buttons;
  final int columns;
  final int rows;
  final bool showEmptySlots;
  final DeckButtonRuntimeState Function(ControllerButton) resolveButtonState;
  final ValueChanged<ControllerButton> onButtonTap;
  final ValueChanged<ControllerButton> onButtonLongPress;
  final String? selectedButtonId;
  final bool showHoldBadges;
  final ValueChanged<int>? onEmptySlotTap;
  final double childAspectRatio;
  final String? Function(ControllerButton button)? thumbnailForButton;
  final bool allowDisabledButtonInteraction;

  @override
  Widget build(BuildContext context) {
    final orderedButtons = [...buttons]
      ..sort((a, b) => a.position.compareTo(b.position));
    final slots = showEmptySlots
        ? _buildSlots(orderedButtons, columns * rows)
        : orderedButtons.cast<ControllerButton?>();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: slots.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (_, index) {
        final button = slots[index];
        if (button == null) {
          return _AddButtonSlot(
            onTap: onEmptySlotTap == null ? null : () => onEmptySlotTap!(index),
          );
        }
        final runtimeState = resolveButtonState(button);

        return DeckButton(
          button: button,
          active: runtimeState.active,
          enabled: runtimeState.enabled,
          pending: runtimeState.pending,
          hasError: runtimeState.hasError,
          allowInteractionWhenDisabled: allowDisabledButtonInteraction,
          thumbnailData: thumbnailForButton?.call(button),
          selected: selectedButtonId == button.id,
          showHoldBadge: showHoldBadges,
          onTap: () => onButtonTap(button),
          onLongPress: () => onButtonLongPress(button),
        );
      },
    );
  }

  static List<ControllerButton?> _buildSlots(
    List<ControllerButton> buttons,
    int configuredSlots,
  ) {
    final maxPosition = buttons.isEmpty
        ? -1
        : buttons.map((button) => button.position).reduce(max);

    var slotCount = max(configuredSlots, maxPosition + 1);
    slotCount = max(slotCount, buttons.length);
    final slots = List<ControllerButton?>.filled(slotCount, null);
    final overflow = <ControllerButton>[];

    for (final button in buttons) {
      final position = button.position;
      if (position >= 0 && position < slotCount && slots[position] == null) {
        slots[position] = button;
      } else {
        overflow.add(button);
      }
    }

    var fillIndex = 0;
    for (final button in overflow) {
      while (fillIndex < slots.length && slots[fillIndex] != null) {
        fillIndex++;
      }
      if (fillIndex < slots.length) {
        slots[fillIndex] = button;
      } else {
        slots.add(button);
      }
    }

    return slots;
  }
}

class _AddButtonSlot extends StatelessWidget {
  const _AddButtonSlot({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.35),
              width: 1.6,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.add,
                color: colorScheme.primary.withValues(alpha: 0.9),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                'ADD',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
