import 'package:flutter/material.dart';

/// The Softifex emblem on a solid white disc, so the logo looks the same on
/// light and dark backgrounds (no grey rectangle around the image).
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 96, this.glow = true});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.of(context).devicePixelRatio).round();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: size * 0.25,
                    offset: Offset(0, size * 0.06)),
              ]
            : null,
      ),
      child: Image.asset(
        'assets/images/emblem.png',
        fit: BoxFit.contain,
        cacheWidth: px, // decode at display size only
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
