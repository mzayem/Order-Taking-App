import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// Home header in the ERP sidebar style: navy gradient, white text,
/// glass tiles. Totals count up when they change; a light sheen crosses the
/// card once when it first appears. Nothing runs after that.
class OverviewHero extends StatelessWidget {
  const OverviewHero({
    super.key,
    required this.dateLabel,
    required this.orderTotal,
    required this.cashTotal,
    required this.entries,
    required this.notSynced,
    required this.onExport,
    required this.onPrevDay,
    required this.onNextDay,
    required this.onPickDate,
  });

  final String dateLabel;
  final double orderTotal;
  final double cashTotal;
  final int entries;
  final int notSynced;
  final VoidCallback onExport;
  final VoidCallback onPrevDay;
  final VoidCallback onNextDay;
  final VoidCallback onPickDate;

  static final _money = NumberFormat('#,##0');
  static String rs(double v) => 'Rs ${_money.format(v)}';

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: heroGradient(),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
                color: AppColors.heroStart.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(
          children: [
            // Two soft light sources, static.
            Positioned(
              right: -50,
              top: -60,
              child: _Glow(
                  size: 190, color: AppColors.accent.withValues(alpha: 0.30)),
            ),
            Positioned(
              left: -70,
              bottom: -90,
              child:
                  _Glow(size: 200, color: Colors.white.withValues(alpha: 0.06)),
            ),
            const Positioned.fill(child: _Sheen()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Text('Overview',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: AppText.semibold,
                                color: Colors.white)),
                      ),
                      _HeroAction(
                          icon: Icons.ios_share,
                          label: 'Export day',
                          onTap: onExport),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DateBar(
                    label: dateLabel,
                    onPrev: onPrevDay,
                    onNext: onNextDay,
                    onPick: onPickDate,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.shopping_bag_outlined,
                          label: 'Orders',
                          value: orderTotal,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.payments_outlined,
                          label: 'Cash',
                          value: cashTotal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        icon: Icons.receipt_long_outlined,
                        text: '$entries ${entries == 1 ? 'entry' : 'entries'}',
                      ),
                      _Chip(
                        icon: notSynced == 0
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        text: notSynced == 0
                            ? 'All synced'
                            : '$notSynced not synced',
                        warn: notSynced > 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass bar: previous day | date (tap to pick) | next day.
class _DateBar extends StatelessWidget {
  const _DateBar({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Pressable(
            onTap: onTap,
            scale: 0.9,
            child: SizedBox(
              width: 44,
              height: 40,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        );

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, 'Previous day', onPrev),
          Expanded(
            child: Pressable(
              onTap: onPick,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_rounded,
                      size: 16, color: AppColors.heroMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: AppText.semibold,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 'Next day', onNext),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

/// A diagonal band of light that crosses the card once (900 ms).
class _Sheen extends StatefulWidget {
  const _Sheen();

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating && !_c.isCompleted) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          if (_c.value == 0 || _c.isCompleted) return const SizedBox.shrink();
          final t = Curves.easeInOut.transform(_c.value);
          return FractionalTranslation(
            translation: Offset(-1.2 + 2.4 * t, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -0.4),
                  end: const Alignment(1, 0.4),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.35, 0.5, 0.65],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small glass pill on the gradient.
class _HeroAction extends StatelessWidget {
  const _HeroAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: AppText.semibold,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: AppColors.heroMuted)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUp(
                    value: value,
                    format: OverviewHero.rs,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: AppText.semibold,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = warn ? const Color(0xFFFFD27A) : AppColors.heroMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: warn ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}
