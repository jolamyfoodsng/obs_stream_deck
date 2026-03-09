import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/entities/controller_button.dart';
import '../extensions/color_extensions.dart';
import '../extensions/icon_mapper.dart';

class DeckButton extends StatefulWidget {
  const DeckButton({
    super.key,
    required this.button,
    required this.active,
    required this.enabled,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showHoldBadge = false,
    this.pending = false,
    this.hasError = false,
    this.allowInteractionWhenDisabled = false,
    this.thumbnailData,
  });

  final ControllerButton button;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showHoldBadge;
  final bool pending;
  final bool hasError;
  final bool allowInteractionWhenDisabled;
  final String? thumbnailData;

  @override
  State<DeckButton> createState() => _DeckButtonState();
}

class _DeckButtonState extends State<DeckButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.button.activeColor.toColor();
    final inactiveColor = widget.button.inactiveColor.toColor();
    final accentColor = widget.active ? activeColor : inactiveColor;
    final enabled = widget.enabled;
    final highlighted = widget.active && enabled;
    final canInteract = !widget.pending &&
        (enabled || widget.allowInteractionWhenDisabled) &&
        (widget.onTap != null || widget.onLongPress != null);
    final thumbnailProvider = _thumbnailProvider(widget.thumbnailData);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.button.label,
      hint: widget.button.longPressTrigger ? 'Hold to execute action' : null,
      child: GestureDetector(
        onTapDown: canInteract ? (_) => setState(() => _pressed = true) : null,
        onTapCancel:
            canInteract ? () => setState(() => _pressed = false) : null,
        onTapUp: canInteract && widget.onTap != null
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap?.call();
              }
            : null,
        onLongPressStart: canInteract && widget.onLongPress != null
            ? (_) => setState(() => _pressed = true)
            : null,
        onLongPressEnd: canInteract && widget.onLongPress != null
            ? (_) => setState(() => _pressed = false)
            : null,
        onLongPress: canInteract ? widget.onLongPress : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _pressed ? 0.96 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1 : 0.55,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.hasError
                      ? Theme.of(context).colorScheme.error
                      : widget.selected
                          ? Theme.of(context).colorScheme.primary
                          : highlighted
                              ? accentColor
                              : Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.25),
                  width:
                      widget.selected || highlighted || widget.hasError ? 2 : 1,
                ),
                boxShadow: (highlighted || widget.selected) && !widget.pending
                    ? <BoxShadow>[
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shortest = constraints.biggest.shortestSide;
                  final compact = shortest < 74;
                  final iconSize =
                      shortest < 68 ? 20.0 : (shortest < 84 ? 24.0 : 28.0);
                  final labelFontSize = shortest < 68 ? 9.0 : 11.0;
                  final labelMaxLines = shortest < 72 ? 1 : 2;
                  final gap = shortest < 72 ? 4.0 : 8.0;

                  final showHoldHint =
                      widget.showHoldBadge && widget.button.longPressTrigger;

                  return Stack(
                    children: <Widget>[
                      if (thumbnailProvider != null)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Opacity(
                              opacity: enabled ? 0.38 : 0.16,
                              child: Image(
                                image: thumbnailProvider,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      Align(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: showHoldHint ? (compact ? 12 : 14) : 0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                IconMapper.fromName(widget.button.icon),
                                color: enabled
                                    ? accentColor
                                    : Theme.of(context).colorScheme.outline,
                                size: iconSize,
                              ),
                              SizedBox(height: gap),
                              Text(
                                widget.button.label,
                                textAlign: TextAlign.center,
                                maxLines: labelMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: labelFontSize,
                                      height: 1.1,
                                      color: enabled
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                          : Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showHoldHint)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: compact ? 2 : 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                compact ? 'HOLD' : 'Hold to run',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: compact ? 8.5 : 9.5,
                                      letterSpacing: 0.5,
                                      fontWeight: FontWeight.w700,
                                      color: enabled
                                          ? accentColor
                                          : Theme.of(context)
                                              .colorScheme
                                              .outline,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.pending)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: SizedBox(
                              width: compact ? 14 : 16,
                              height: compact ? 14 : 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  ImageProvider<Object>? _thumbnailProvider(String? rawData) {
    if (rawData == null || rawData.isEmpty) return null;
    if (!rawData.startsWith('data:image/')) return null;
    final comma = rawData.indexOf(',');
    if (comma <= 0 || comma == rawData.length - 1) return null;
    final base64Part = rawData.substring(comma + 1);
    try {
      return MemoryImage(base64Decode(base64Part));
    } catch (_) {
      return null;
    }
  }
}
