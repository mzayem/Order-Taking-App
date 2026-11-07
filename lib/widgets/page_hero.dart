import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// Compact navy gradient header for inner pages (same family as the Home
/// hero): glass icon tile, title, one line of help, optional trailing widget.
/// Slides in once when the page opens.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: RepaintBoundary(
        child: Container(
          margin: margin,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            gradient: heroGradient(),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                  color: AppColors.heroStart.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -50,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.accent.withValues(alpha: 0.32),
                      AppColors.accent.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(colors: [
                          Colors.white.withValues(alpha: 0.24),
                          Colors.white.withValues(alpha: 0.08),
                        ]),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 23),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: AppText.semibold,
                                  color: Colors.white)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(subtitle!,
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.heroMuted)),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass section card for forms: groups fields with a small heading.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.children,
    this.title,
    this.icon,
    this.index = 0,
  });

  final List<Widget> children;
  final String? title;
  final IconData? icon;
  final int index;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: glassDecoration(radius: AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.brand),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppText.semibold,
                          color: AppColors.textPrimary)),
                ),
              ]),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
