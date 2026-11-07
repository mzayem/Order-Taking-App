import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full "Softifex" word logo. Dark mode uses the white version, light mode
/// the colour version; both have transparent backgrounds (no white box).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 240});
  final double width;

  @override
  Widget build(BuildContext context) {
    final px = (width * MediaQuery.of(context).devicePixelRatio).round();
    return Image.asset(
      AppColors.isDark
          ? 'assets/images/logo_dark.png'
          : 'assets/images/logo_light.png',
      width: width,
      fit: BoxFit.contain,
      cacheWidth: px.clamp(1, 900), // decode at display size only
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true, // no flash when the theme switches
    );
  }
}
