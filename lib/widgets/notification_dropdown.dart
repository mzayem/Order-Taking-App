import 'package:flutter/material.dart';

import '../notification_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'motion.dart';
import 'skeleton.dart';

/// Called whenever the dropdown has a newer list or unread count, so the
/// bell badge and Home's cached list stay in step without another API call.
typedef NotificationsChanged = void Function(
    List<Map<String, dynamic>> items, int unread);

/// Opens the notification panel under the bell at [anchor] (global rect).
/// Shows the cached [initial] list at once and refreshes it in the
/// background. "View all" opens the full Notifications screen.
Future<void> showNotificationDropdown({
  required BuildContext context,
  required Rect anchor,
  required List<Map<String, dynamic>>? initial,
  required NotificationsChanged onChanged,
}) {
  return Navigator.of(context).push(_DropdownRoute(
    anchor: anchor,
    initial: initial,
    onChanged: onChanged,
    reduceMotion: MediaQuery.of(context).disableAnimations,
  ));
}

class _DropdownRoute extends PopupRoute<void> {
  _DropdownRoute({
    required this.anchor,
    required this.initial,
    required this.onChanged,
    required this.reduceMotion,
  });

  final Rect anchor;
  final List<Map<String, dynamic>>? initial;
  final NotificationsChanged onChanged;
  final bool reduceMotion;

  @override
  Color? get barrierColor => const Color(0x14000000);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close notifications';
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

  /// Panel position: under the bell, but always fully on screen (the bell
  /// is not the right-most icon, so right-aligning to it could push the
  /// panel off the left edge).
  ({double left, double width}) _box(Size size) {
    final width = (size.width - 24).clamp(0.0, 380.0);
    final left =
        (anchor.right - width + 8).clamp(12.0, size.width - width - 12);
    return (left: left, width: width);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final size = MediaQuery.of(context).size;
    final b = _box(size);
    return Stack(
      children: [
        Positioned(
          top: anchor.bottom + 6,
          left: b.left,
          width: b.width,
          child: ConstrainedBox(
            // Leave room above the floating nav bar.
            constraints: BoxConstraints(
                maxHeight: (size.height - anchor.bottom - 110)
                    .clamp(220.0, size.height)),
            // Very large phone fonts would overflow the header row.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: _NotificationPanel(initial: initial, onChanged: onChanged),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // The transition wraps the full-screen page, so the scale origin is the
    // bell's spot on screen: the panel grows out of the bell.
    final size = MediaQuery.of(context).size;
    final origin = Alignment(
      (anchor.center.dx / size.width) * 2 - 1,
      ((anchor.bottom + 6) / size.height) * 2 - 1,
    );
    final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        alignment: origin,
        scale: Tween(begin: 0.88, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({required this.initial, required this.onChanged});
  final List<Map<String, dynamic>>? initial;
  final NotificationsChanged onChanged;

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  static const _shown = 5;

  List<Map<String, dynamic>>? _items;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _items = widget.initial;
    _refresh();
  }

  Future<void> _refresh() async {
    final res = await ApiService.fetchNotifications();
    if (!mounted) return;
    setState(() {
      if (res == null) {
        _offline = _items == null; // keep showing the cached list
      } else {
        _offline = false;
        _items = List<Map<String, dynamic>>.from((res['notifications'] as List)
            .map((n) => Map<String, dynamic>.from(n)));
      }
    });
    if (res != null) _notify();
  }

  int get _unread => _items?.where((n) => n['unread'] == true).length ?? 0;

  void _notify() {
    final items = _items;
    if (items != null) widget.onChanged(items, _unread);
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['unread'] != true) return;
    setState(() => n['unread'] = false);
    _notify();
    await ApiService.markNotificationRead(n['id'] as int);
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final n in _items ?? const <Map<String, dynamic>>[]) {
        n['unread'] = false;
      }
    });
    _notify();
    await ApiService.markNotificationRead();
  }

  Future<void> _viewAll() async {
    final nav = Navigator.of(context);
    nav.pop();
    // The full screen hands back its unread count (null when offline).
    final unread = await nav.push<int>(
        MaterialPageRoute(builder: (_) => const NotificationScreen()));
    if (unread != null) {
      // Its list is fresher than ours; Home re-reads it on the next check.
      widget.onChanged(_items ?? const [], unread);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    // The 5 LATEST, whatever order the server sent them in. Everything else
    // is behind "View all".
    final latest = items == null
        ? const <Map<String, dynamic>>[]
        : (sortNewestFirst([...items])).take(_shown).toList();

    Widget body;
    if (items == null && !_offline) {
      body = const Column(
        children: [
          SkeletonListTile(trailing: false),
          SkeletonListTile(trailing: false),
          SkeletonListTile(trailing: false),
        ],
      );
    } else if (items == null || items.isEmpty) {
      body = _Message(
        icon: _offline ? Icons.cloud_off : Icons.notifications_none,
        text: _offline ? 'Could not reach the server.' : 'No notifications',
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < latest.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52),
            FadeSlideIn(
              index: i,
              offset: 10,
              child: _Row(n: latest[i], onTap: () => _markRead(latest[i])),
            ),
          ],
        ],
      );
    }

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: glassDecoration(radius: AppRadius.lg).copyWith(
            color: AppColors.surface, // solid: list text must stay sharp
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Flexible(
                      child: Text('Notifications',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16, fontWeight: AppText.semibold)),
                    ),
                    if (_unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('$_unread new',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: AppText.semibold,
                                color: AppColors.brandDark)),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(child: SingleChildScrollView(child: body)),
              const Divider(height: 1),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_unread > 0) ...[
                      Expanded(
                        child: _FooterButton(
                          label: 'Mark all read',
                          icon: Icons.done_all_rounded,
                          onTap: _markAllRead,
                        ),
                      ),
                      VerticalDivider(width: 1, color: AppColors.hairline),
                    ],
                    Expanded(
                      child: _FooterButton(
                        label: (items?.length ?? 0) > _shown
                            ? 'View all (${items!.length})'
                            : 'View all',
                        icon: Icons.chevron_right,
                        iconAfter: true,
                        onTap: _viewAll,
                      ),
                    ),
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

/// One half of the panel footer; the label shrinks instead of overflowing.
class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconAfter = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final text = Flexible(
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(fontWeight: AppText.semibold, color: AppColors.brand)),
    );
    final ic = Icon(icon, size: 18, color: AppColors.brand);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: iconAfter
              ? [text, const SizedBox(width: 4), ic]
              : [ic, const SizedBox(width: 6), text],
        ),
      ),
    );
  }
}

/// Sorts in place, newest first. Ids only ever grow, so the highest id is
/// the latest notification (the server also sends them newest first, this
/// just does not depend on it). Rows without an id keep their place.
List<Map<String, dynamic>> sortNewestFirst(List<Map<String, dynamic>> list) {
  int id(Map<String, dynamic> n) => (n['id'] as num?)?.toInt() ?? -1;
  list.sort((a, b) => id(b).compareTo(id(a)));
  return list;
}

/// Server types (NotificationType, lower-cased): info, success, warning, danger.
(IconData, Color) notificationStyle(String? type) => switch (type) {
      'success' => (Icons.check_circle_outline, AppColors.green),
      'warning' => (Icons.warning_amber_rounded, AppColors.orange),
      'danger' => (Icons.error_outline, AppColors.red),
      _ => (Icons.info_outline, AppColors.blue),
    };

class _Row extends StatelessWidget {
  const _Row({required this.n, required this.onTap});
  final Map<String, dynamic> n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = n['unread'] == true;
    final (icon, color) = notificationStyle(n['type']?.toString());
    final body = (n['body'] ?? '').toString();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            unread ? AppText.semibold : AppText.regular),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 4),
                  Text(n['date']?.toString() ?? '',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 6),
                child: Icon(Icons.circle, size: 8, color: AppColors.brand),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.textTertiary),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}
