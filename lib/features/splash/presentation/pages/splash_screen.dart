import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/brand_identity.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
    });

    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      context.go('/controller');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF061126),
      body: SafeArea(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _visible ? 1 : 0.95,
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: Colors.white.withValues(alpha: 0.03),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color:
                              const Color(0xFF20E9F5).withValues(alpha: 0.25),
                          blurRadius: 26,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const BrandSymbol(size: 84),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'DeckPilot',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'for OBS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF2FAFFF),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mobile Stream Deck for OBS',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.68),
                          letterSpacing: 0.3,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
