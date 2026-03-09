import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/entities/premium_feature.dart';
import '../state/app_providers.dart';
import '../state/premium_controller.dart';
import 'pro_badge.dart';

Future<void> showPremiumUpgradeModal(
  BuildContext context, {
  PremiumFeature? highlightedFeature,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumUpgradeSheet(
      highlightedFeature: highlightedFeature,
    ),
  );
}

class _PremiumUpgradeSheet extends ConsumerStatefulWidget {
  const _PremiumUpgradeSheet({
    required this.highlightedFeature,
  });

  final PremiumFeature? highlightedFeature;

  @override
  ConsumerState<_PremiumUpgradeSheet> createState() =>
      _PremiumUpgradeSheetState();
}

class _PremiumUpgradeSheetState extends ConsumerState<_PremiumUpgradeSheet> {
  bool _busy = false;

  static const List<PremiumFeature> _featureOrder = <PremiumFeature>[
    PremiumFeature.unlimitedPages,
    PremiumFeature.unlimitedScenes,
    PremiumFeature.macros,
    PremiumFeature.scenePreviews,
    PremiumFeature.streamHealthMonitoring,
    PremiumFeature.emergencyPage,
  ];

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumControllerProvider);
    final controller = ref.read(premiumControllerProvider.notifier);

    final bulletStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final featureList = <PremiumFeature>[
      ..._featureOrder,
      if (widget.highlightedFeature != null &&
          !_featureOrder.contains(widget.highlightedFeature))
        widget.highlightedFeature!,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.28),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome, color: Color(0xFFEAB308)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'DeckPilot Premium',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ProBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock the full power of your OBS control deck.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                ...featureList.map(
                  (feature) => Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              feature == widget.highlightedFeature
                                  ? Icons.star
                                  : Icons.check_circle,
                              size: 16,
                              color: feature == widget.highlightedFeature
                                  ? const Color(0xFFEAB308)
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature.label,
                                style: bulletStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (feature == PremiumFeature.macros)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'More macro actions',
                                  style: bulletStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (feature ==
                          PremiumFeature.streamHealthMonitoring) ...<Widget>[
                        const _FeatureDetailBullet(
                          text:
                              'Live bitrate and throughput from OBS stream output',
                        ),
                        const _FeatureDetailBullet(
                          text:
                              'Dropped and skipped frame tracking during broadcast',
                        ),
                        const _FeatureDetailBullet(
                          text:
                              'Real CPU usage, FPS, and render-time telemetry',
                        ),
                        const _FeatureDetailBullet(
                          text:
                              'Congestion, reconnect, and network warning banners',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${premium.productPrice} one-time purchase',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                ),
                if ((premium.error ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    premium.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy || premium.purchasePending
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            final errorColor =
                                Theme.of(context).colorScheme.error;
                            setState(() => _busy = true);
                            final result = await controller.purchasePremium();
                            if (!mounted) return;
                            setState(() => _busy = false);

                            switch (result) {
                              case PremiumPurchaseResult.success:
                              case PremiumPurchaseResult.alreadyPremium:
                                navigator.pop();
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'DeckPilot Premium activated.',
                                      ),
                                      duration: Duration(milliseconds: 1400),
                                    ),
                                  );
                                break;
                              case PremiumPurchaseResult.cancelled:
                                break;
                              case PremiumPurchaseResult.unavailable:
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        premium.error ??
                                            'Billing is unavailable right now. Try again later.',
                                      ),
                                    ),
                                  );
                                break;
                              case PremiumPurchaseResult.failed:
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        premium.error ??
                                            'Purchase failed. Please try again.',
                                      ),
                                      backgroundColor: errorColor,
                                    ),
                                  );
                                break;
                            }
                          },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        if (_busy || premium.purchasePending)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.lock_open),
                        const SizedBox(width: 8),
                        Text(
                          premium.isPremium
                              ? 'Premium Activated'
                              : 'Upgrade Now',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: _busy || premium.purchasePending
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Maybe Later'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _busy || premium.purchasePending
                            ? null
                            : () async {
                                final navigator = Navigator.of(context);
                                await controller.restorePurchases();
                                if (!mounted) return;
                                if (ref
                                    .read(premiumControllerProvider)
                                    .isPremium) {
                                  navigator.pop();
                                }
                              },
                        child: const Text('Restore'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureDetailBullet extends StatelessWidget {
  const _FeatureDetailBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.check_circle,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
