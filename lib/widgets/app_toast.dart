import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show navigatorKey;
import '../theme/app_theme.dart';

enum ToastType { success, error, warning, info }

/// iOS-style toast: a glass capsule springs up from the bottom, its icon
/// pops and draws itself (check / cross / ! / i), a thin bar shows the time
/// left. Tap or swipe down to dismiss. One toast at a time; a new one
/// replaces the old. Lives in the root overlay, so it survives page changes
/// (e.g. "Login successful" while moving to Home).
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static GlobalKey<_ToastViewState>? _key;

  static void success(BuildContext context, String message) =>
      show(context, message, type: ToastType.success);
  static void error(BuildContext context, String message) =>
      show(context, message, type: ToastType.error);
  static void warning(BuildContext context, String message) =>
      show(context, message, type: ToastType.warning);
  static void info(BuildContext context, String message) =>
      show(context, message, type: ToastType.info);

  static void show(BuildContext context, String message,
      {ToastType type = ToastType.info, Duration? duration}) {
    final overlay = navigatorKey.currentState?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _remove();
    switch (type) {
      case ToastType.success:
        HapticFeedback.lightImpact();
      case ToastType.error:
      case ToastType.warning:
        HapticFeedback.mediumImpact();
      case ToastType.info:
        HapticFeedback.selectionClick();
    }

    final key = GlobalKey<_ToastViewState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: key,
        message: message,
        type: type,
        duration: duration ??
            (type == ToastType.error || type == ToastType.warning
                ? const Duration(milliseconds: 4000)
                : const Duration(milliseconds: 2800)),
        onGone: () {
          if (identical(_entry, entry)) _remove();
        },
      ),
    );
    _entry = entry;
    _key = key;
    overlay.insert(entry);
  }

  /// Animates the current toast away (if any).
  static void hide() => _key?.currentState?.dismiss();

  static void _remove() {
    _entry?.remove();
    _entry = null;
    _key = null;
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    required this.onGone,
  });

  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  // Entrance / exit of the capsule.
  late final AnimationController _show = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 220));
  // Icon pop + stroke drawing.
  late final AnimationController _icon = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 620));
  // Time-left bar.
  late final AnimationController _life =
      AnimationController(vsync: this, duration: widget.duration);

  double _drag = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((s) {
      if (s == AnimationStatus.completed) dismiss();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_show.status != AnimationStatus.dismissed) return;
    if (MediaQuery.of(context).disableAnimations) {
      _show.value = 1;
      _icon.value = 1;
    } else {
      _show.forward();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _icon.forward();
      });
    }
    _life.forward();
  }

  Future<void> dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _life.stop();
    await _show.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _show.dispose();
    _icon.dispose();
    _life.dispose();
    super.dispose();
  }

  (Color, IconPainterKind) get _style => switch (widget.type) {
        ToastType.success => (AppColors.green, IconPainterKind.check),
        ToastType.error => (AppColors.red, IconPainterKind.cross),
        ToastType.warning => (AppColors.orange, IconPainterKind.bang),
        ToastType.info => (AppColors.accent, IconPainterKind.info),
      };

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final (color, kind) = _style;
    // Above the floating tab bar, or above the keyboard when it is open.
    final bottom = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom + 16
        : mq.padding.bottom + 92;

    // Dark capsule on light pages, lighter navy on dark pages: always reads.
    final bg =
        AppColors.isDark ? const Color(0xF2203653) : const Color(0xF2162536);

    final enter = CurvedAnimation(
        parent: _show,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic);

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AnimatedBuilder(
              animation: enter,
              builder: (context, child) {
                final t = enter.value;
                return Opacity(
                  opacity: _show.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 60 + _drag),
                    child: Transform.scale(
                        scale: 0.9 + 0.1 * t.clamp(0.0, 1.2), child: child),
                  ),
                );
              },
              child: GestureDetector(
                onTap: dismiss,
                onVerticalDragUpdate: (d) => setState(
                    () => _drag = (_drag + d.delta.dy).clamp(0.0, 120.0)),
                onVerticalDragEnd: (d) {
                  if (_drag > 40 || (d.primaryVelocity ?? 0) > 300) {
                    dismiss();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                child: Semantics(
                  liveRegion: true,
                  label: widget.message,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: color.withValues(alpha: 0.25),
                            blurRadius: 18,
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                            child: Row(
                              children: [
                                _AnimatedBadge(
                                    animation: _icon, color: color, kind: kind),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    widget.message,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      height: 1.3,
                                      fontWeight: AppText.semibold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Time left.
                          AnimatedBuilder(
                            animation: _life,
                            builder: (_, __) => Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: 1 - _life.value,
                                child: Container(
                                    height: 3,
                                    color: color.withValues(alpha: 0.85)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum IconPainterKind { check, cross, bang, info }

/// Coloured disc that pops in, then its symbol is drawn stroke by stroke.
class _AnimatedBadge extends StatelessWidget {
  const _AnimatedBadge(
      {required this.animation, required this.color, required this.kind});
  final Animation<double> animation;
  final Color color;
  final IconPainterKind kind;

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.55, curve: Curves.elasticOut));
    final draw = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.3, 1, curve: Curves.easeOutCubic));
    return RepaintBoundary(
      child: ScaleTransition(
        scale: pop,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, Colors.black, 0.25)!],
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
          child: CustomPaint(painter: _SymbolPainter(draw, kind)),
        ),
      ),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.t, this.kind) : super(repaint: t);
  final Animation<double> t;
  final IconPainterKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final paths = <Path>[];
    switch (kind) {
      case IconPainterKind.check:
        paths.add(Path()
          ..moveTo(w * 0.28, w * 0.52)
          ..lineTo(w * 0.44, w * 0.67)
          ..lineTo(w * 0.73, w * 0.36));
      case IconPainterKind.cross:
        paths
          ..add(Path()
            ..moveTo(w * 0.33, w * 0.33)
            ..lineTo(w * 0.67, w * 0.67))
          ..add(Path()
            ..moveTo(w * 0.67, w * 0.33)
            ..lineTo(w * 0.33, w * 0.67));
      case IconPainterKind.bang:
        paths
          ..add(Path()
            ..moveTo(w * 0.5, w * 0.26)
            ..lineTo(w * 0.5, w * 0.56))
          ..add(Path()
            ..moveTo(w * 0.5, w * 0.72)
            ..lineTo(w * 0.5, w * 0.73));
      case IconPainterKind.info:
        paths
          ..add(Path()
            ..moveTo(w * 0.5, w * 0.27)
            ..lineTo(w * 0.5, w * 0.28))
          ..add(Path()
            ..moveTo(w * 0.5, w * 0.44)
            ..lineTo(w * 0.5, w * 0.74));
    }

    // Draw the strokes one after another as t goes 0 -> 1.
    final metrics = <PathMetric>[
      for (final path in paths) ...path.computeMetrics(),
    ];
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    var left = total * t.value;
    for (final m in metrics) {
      if (left <= 0) break;
      final len = left.clamp(0.0, m.length);
      canvas.drawPath(m.extractPath(0, len), p);
      left -= m.length;
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.kind != kind;
}
