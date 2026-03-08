import 'package:flutter/material.dart';

class BrandAssets {
  const BrandAssets._();

  static const String logoDark = 'assets/branding/logo_dark.png';
  static const String logoLight = 'assets/branding/logo_light.png';
  static const String symbolDark = 'assets/branding/symbol_dark.png';
  static const String symbolLight = 'assets/branding/symbol_light.png';
  static const String symbolSmall = 'assets/branding/symbol_small.png';
}

class BrandSymbol extends StatelessWidget {
  const BrandSymbol({
    super.key,
    this.size = 28,
    this.useSmallAsset = false,
  });

  final double size;
  final bool useSmallAsset;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final path = useSmallAsset
        ? BrandAssets.symbolSmall
        : (brightness == Brightness.dark
            ? BrandAssets.symbolDark
            : BrandAssets.symbolLight);

    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class BrandAppBarTitle extends StatelessWidget {
  const BrandAppBarTitle({
    super.key,
    required this.title,
    this.symbolSize = 24,
  });

  final String title;
  final double symbolSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandSymbol(
          size: symbolSize,
          useSmallAsset: symbolSize <= 24,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class BrandConnectHeader extends StatelessWidget {
  const BrandConnectHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        const BrandSymbol(size: 34),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'DeckPilot',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'for OBS',
              style: textTheme.bodySmall?.copyWith(
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
