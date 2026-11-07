import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'services/app_log.dart';
import 'theme/app_theme.dart';
import 'widgets/skeleton.dart';
import 'widgets/page_hero.dart';

/// Local activity log: sync results, API errors, sign-outs.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 50;
  static final _timeFmt = DateFormat('dd MMM yyyy, HH:mm:ss');

  LogLevel? _level;
  String? _category;
  List<LogEntry> _rows = const [];
  int _page = 0;
  int _total = 0;
  bool _loading = true;

  int get _pages => _total == 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 0}) async {
    setState(() => _loading = true);
    final total = await AppLog.count(level: _level, category: _category);
    final rows = await AppLog.page(
        level: _level, category: _category, page: page, pageSize: _pageSize);
    if (!mounted) return;
    setState(() {
      _total = total;
      _rows = rows;
      _page = page;
      _loading = false;
    });
  }

  String _asText(List<LogEntry> rows) => rows
      .map((e) =>
          '${_timeFmt.format(e.time)} [${e.level.name.toUpperCase()}] ${e.category}: ${e.message}')
      .join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _asText(_rows)));
    if (!mounted) return;
    AppToast.show(context, 'Copied ${_rows.length} entries',
        type: ToastType.success);
  }

  Future<void> _share() async {
    await SharePlus.instance
        .share(ShareParams(text: _asText(_rows), subject: 'Activity log'));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear activity?'),
        content: const Text('All log entries on this phone will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await AppLog.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasRows = _rows.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
              tooltip: 'Copy',
              onPressed: hasRows ? _copy : null,
              icon: const Icon(Icons.copy_all_outlined)),
          IconButton(
              tooltip: 'Share',
              onPressed: hasRows ? _share : null,
              icon: const Icon(Icons.share_outlined)),
          IconButton(
              tooltip: 'Clear',
              onPressed: _total > 0 ? _clear : null,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: PageHero(
              icon: Icons.history_rounded,
              title: 'Activity',
              subtitle: '$_total entries on this phone',
              margin: const EdgeInsets.only(bottom: 8),
            ),
          ),
          _Filters(
            level: _level,
            category: _category,
            onLevel: (l) {
              _level = l;
              _load();
            },
            onCategory: (c) {
              _category = c;
              _load();
            },
          ),
          Expanded(
            child: _loading
                ? const TransactionListSkeleton(count: 8)
                : !hasRows
                    ? const _Empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) =>
                            _LogTile(entry: _rows[i], timeFmt: _timeFmt),
                      ),
          ),
          if (_total > _pageSize)
            _Pager(
              page: _page,
              pages: _pages,
              total: _total,
              onPrev: _page > 0 ? () => _load(page: _page - 1) : null,
              onNext: _page < _pages - 1 ? () => _load(page: _page + 1) : null,
            ),
        ],
      ),
    );
  }
}

(IconData, Color) _levelStyle(LogLevel l) => switch (l) {
      LogLevel.info => (Icons.info_outline, AppColors.blue),
      LogLevel.warning => (Icons.warning_amber_rounded, AppColors.orange),
      LogLevel.error => (Icons.error_outline, AppColors.red),
    };

IconData _categoryIcon(String c) => switch (c) {
      LogCategory.sync => Icons.sync,
      LogCategory.api => Icons.cloud_outlined,
      LogCategory.auth => Icons.lock_outline,
      LogCategory.notification => Icons.notifications_none,
      _ => Icons.phone_android,
    };

String _label(String s) => s[0].toUpperCase() + s.substring(1);

class _Filters extends StatelessWidget {
  const _Filters({
    required this.level,
    required this.category,
    required this.onLevel,
    required this.onCategory,
  });

  final LogLevel? level;
  final String? category;
  final ValueChanged<LogLevel?> onLevel;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, bool selected, VoidCallback onTap,
            {IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(text),
            avatar: icon == null ? null : Icon(icon, size: 16),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                chip('All levels', level == null, () => onLevel(null)),
                for (final l in LogLevel.values)
                  chip(_label(l.name), level == l, () => onLevel(l),
                      icon: _levelStyle(l).$1),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                chip('All', category == null, () => onCategory(null)),
                for (final c in LogCategory.all)
                  chip(_label(c), category == c, () => onCategory(c),
                      icon: _categoryIcon(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.timeFmt});
  final LogEntry entry;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _levelStyle(entry.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.message,
                    style:
                        TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(_categoryIcon(entry.category),
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(_label(entry.category),
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    // Shrinks with an ellipsis on narrow phones.
                    Expanded(
                      child: Text(timeFmt.format(entry.time),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pages;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          border:
              Border(top: BorderSide(color: AppColors.hairline, width: 0.5)),
        ),
        child: Row(
          children: [
            IconButton(
                tooltip: 'Newer',
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('Page ${page + 1} of $pages  ($total entries)',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
            IconButton(
                tooltip: 'Older',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 8),
            Text('No activity yet',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}
