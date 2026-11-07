import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The fluid gradient behind every page (light: steel-blue sky, dark: deep
/// blue glow into near-black). Painted once and cached by the
/// RepaintBoundary, so scrolling pages never repaint it.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.45, 1.0],
                colors: [AppColors.bgTop, AppColors.bgMid, AppColors.bgBottom],
              ),
            ),
            // A soft light source at the top right, like the reference glow.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -1.05),
                  radius: 1.1,
                  colors: [
                    AppColors.bgGlow,
                    AppColors.bgGlow.withValues(alpha: 0)
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
