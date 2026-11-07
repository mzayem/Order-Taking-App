import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One shimmer controller for the whole app. Every [SkeletonBox] listens to
/// it, so ten placeholders cost one ticker, not ten. The ticker only runs
/// while at least one skeleton is on screen.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({super.key, required this.child});
  final Widget child;

  static Animation<double>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShimmerInherited>()
      ?.animation;

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  int _users = 0;

  void _attach() {
    if (_users++ == 0) _controller.repeat();
  }

  void _detach() {
    if (--_users == 0) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ShimmerInherited(
        animation: _controller,
        attach: _attach,
        detach: _detach,
        child: widget.child,
      );
}

class _ShimmerInherited extends InheritedWidget {
  const _ShimmerInherited({
    required this.animation,
    required this.attach,
    required this.detach,
    required super.child,
  });
  final Animation<double> animation;
  final VoidCallback attach;
  final VoidCallback detach;

  @override
  bool updateShouldNotify(_ShimmerInherited old) => false;
}

/// A grey placeholder block that shimmers while content loads.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.circle = false,
  });
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> {
  _ShimmerInherited? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion: stay static and keep the shared ticker asleep.
    final scope = MediaQuery.of(context).disableAnimations
        ? null
        : context.getInheritedWidgetOfExactType<_ShimmerInherited>();
    if (scope != _scope) {
      _scope?.detach();
      _scope = scope;
      _scope?.attach();
    }
  }

  @override
  void dispose() {
    _scope?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.circle
        ? BoxDecoration(color: AppColors.skeletonBase, shape: BoxShape.circle)
        : BoxDecoration(
            color: AppColors.skeletonBase,
            borderRadius: BorderRadius.circular(widget.radius));
    final box = SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(decoration: shape),
    );

    final animation = _scope?.animation;
    if (animation == null) return box;
    // Fade between two greys: no gradient shader per frame.
    return FadeTransition(
      opacity: _pulse(animation),
      child: box,
    );
  }

  static final _curve = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.45), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.45, end: 1.0), weight: 1),
  ]);

  Animation<double> _pulse(Animation<double> parent) => _curve.animate(parent);
}

/// Placeholder for a card row: leading circle, two lines, trailing value.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile(
      {super.key, this.leading = true, this.trailing = true});
  final bool leading;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading) ...[
            const SkeletonBox(width: 36, height: 36, circle: true),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                    widthFactor: 0.6, child: SkeletonBox(height: 12)),
                SizedBox(height: 8),
                FractionallySizedBox(
                    widthFactor: 0.35, child: SkeletonBox(height: 10)),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 56, height: 14),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for the Home transaction list (cards with a row each).
class TransactionListSkeleton extends StatelessWidget {
  const TransactionListSkeleton({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline, width: 0.5),
          ),
          child: const SkeletonListTile(),
        ),
      ),
    );
  }
}

/// Skeleton for a full form screen (customer picker, product picker, rows).
class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SkeletonBox(width: 90, height: 10),
          const SizedBox(height: 8),
          const SkeletonBox(height: 48, radius: AppRadius.sm),
          const SizedBox(height: 20),
          const SkeletonBox(width: 90, height: 10),
          const SizedBox(height: 8),
          const SkeletonBox(height: 48, radius: AppRadius.sm),
          const SizedBox(height: 24),
          for (var i = 0; i < rows; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.hairline, width: 0.5),
              ),
              child: const SkeletonListTile(leading: false),
            ),
        ],
      ),
    );
  }
}

/// Skeleton for the profile header card.
class ProfileCardSkeleton extends StatelessWidget {
  const ProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: Column(
        children: [
          SkeletonBox(width: 96, height: 96, circle: true),
          SizedBox(height: 14),
          SkeletonBox(width: 140, height: 16),
          SizedBox(height: 8),
          SkeletonBox(width: 90, height: 12),
        ],
      ),
    );
  }
}
