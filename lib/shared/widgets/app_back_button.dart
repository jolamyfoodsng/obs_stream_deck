import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.fallbackRoute = '/controller',
  });

  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back',
      onPressed: () {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          context.pop();
          return;
        }
        context.go(fallbackRoute);
      },
    );
  }
}
