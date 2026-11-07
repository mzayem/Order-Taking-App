import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NavItem {
  const NavItem({
    required this.icon,
    required this.label,
    this.activeIcon,
    this.badge = 0,
  });
  final IconData icon;
  final IconData? activeIcon; // filled variant for the selected tab
  final String label;

  /// Number shown on a small red badge; 0 hides it.
  final int badge;
}

/// iPhone-style floating glass tab bar. Every tab shows icon over a small
/// label; one glass capsule glides between tabs with a slight overshoot,
/// and the active icon pops. All implicit animations (no extra tickers
/// while idle).
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    // Fixed 66px bar: cap label scaling so icon + label always fit.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: RepaintBoundary(
          child: Container(
            height: 66,
            padding: const EdgeInsets.all(5),
            decoration:
                glassDecoration(radius: 33).copyWith(color: AppColors.navFill),
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / items.length;
              return Stack(
                children: [
                  // The gliding glass capsule.
                  AnimatedPositioned(
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 340),
                    curve: Curves.easeOutBack,
                    left: w * currentIndex,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.brand.withValues(alpha: 0.22),
                            AppColors.brand.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                            color: AppColors.brand.withValues(alpha: 0.25)),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _Tab(
                            item: items[i],
                            selected: i == currentIndex,
                            still: still,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.still,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool still;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brand : AppColors.textSecondary;
    final d = still ? Duration.zero : const Duration(milliseconds: 260);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: d,
              curve: Curves.easeOutBack,
              child: Badge(
                isLabelVisible: item.badge > 0,
                label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                child: Icon(
                  selected ? (item.activeIcon ?? item.icon) : item.icon,
                  size: 23,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: d,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? AppText.semibold : AppText.regular,
                color: color,
              ),
              child: Text(item.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
