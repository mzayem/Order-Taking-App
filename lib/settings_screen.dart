import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db/database.dart';
import 'services/app_log.dart';
import 'services/transaction_export.dart';
import 'theme/app_theme.dart';
import 'utils/ui_utils.dart';
import 'widgets/motion.dart';
import 'widgets/page_hero.dart';
import 'widgets/skeleton.dart';

/// Data tools kept away from the Home screen so nothing is cleared by
/// mistake: export a date range (with sync status), then optionally clear it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _day = DateFormat('dd MMM yyyy');

  late DateTimeRange _range = () {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateTimeRange(
        start: today.subtract(const Duration(days: 30)), end: today);
  }();

  List<Map<String, dynamic>>? _rows; // null while counting
  bool _busy = false;

  int get _total => _rows?.length ?? 0;
  int get _synced =>
      _rows?.where((r) => r['SyncStatus'] == 'Synced').length ?? 0;
  int get _notSynced => _total - _synced;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    setState(() => _rows = null);
    final rows =
        await AppDatabase.getTransactionsInRange(_range.start, _range.end);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _pickRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: _range,
      helpText: 'Transactions taken between',
    );
    if (picked == null) return;
    _range = picked;
    _count();
  }

  List<int> _ids({bool syncedOnly = false}) => (_rows ?? const [])
      .where((r) => !syncedOnly || r['SyncStatus'] == 'Synced')
      .map((r) => r['TransactionID'] as int)
      .toList();

  String get _rangeLabel =>
      '${_day.format(_range.start)} - ${_day.format(_range.end)}';

  /// Exports [ids]; returns true when the share sheet opened.
  Future<bool> _export(List<int> ids) async {
    final csv = await TransactionExport.buildCsv(ids);
    if (csv == null) {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, 'Nothing to export',
            isSuccess: false);
      }
      return false;
    }
    final stamp = DateFormat('yyyyMMdd');
    if (!mounted) return false;
    // Saves to Downloads, shows a toast with the location, opens share.
    return TransactionExport.saveAndShare(context, csv,
        name:
            'Transactions_${stamp.format(_range.start)}_${stamp.format(_range.end)}');
  }

  Future<void> _exportOnly() async {
    setState(() => _busy = true);
    try {
      await _export(_ids());
    } catch (e) {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, 'Export failed: $e',
            isSuccess: false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Export first, then ask; unsynced rows stay unless the user ticks the box.
  Future<void> _exportAndClear() async {
    setState(() => _busy = true);
    try {
      final exported = await _export(_ids());
      if (!exported || !mounted) return;

      final includeUnsynced = await showDialog<bool>(
        context: context,
        builder: (_) => _ClearDialog(
          range: _rangeLabel,
          synced: _synced,
          notSynced: _notSynced,
        ),
      );
      if (includeUnsynced == null) return; // cancelled

      final ids = _ids(syncedOnly: !includeUnsynced);
      await AppDatabase.deleteTransactions(ids);
      await AppLog.warning(LogCategory.app,
          'Cleared ${ids.length} transaction(s) from $_rangeLabel${includeUnsynced ? ' (including not synced)' : ''}');
      if (mounted) {
        UiUtils.showBeautifulSnackBar(
            context, 'Cleared ${ids.length} transaction(s)');
      }
      await _count();
    } catch (e) {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, 'Clear failed: $e',
            isSuccess: false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counting = _rows == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const PageHero(
            icon: Icons.tune_rounded,
            title: 'Settings',
            subtitle: 'Data tools for this phone',
          ),
          FormSection(
            index: 1,
            title: 'Export and clear transactions',
            icon: Icons.inventory_outlined,
            children: [
              Text(
                'Pick a date range. The CSV includes a status column '
                '(Synced / Pending / Failed). Clearing always exports first.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Pressable(
                onTap: _busy ? null : _pickRange,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.date_range_rounded, color: AppColors.brand),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date range',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 2),
                            Text(_rangeLabel,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: AppText.semibold)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (counting)
                const Row(children: [
                  Expanded(child: SkeletonBox(height: 58, radius: 14)),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonBox(height: 58, radius: 14)),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonBox(height: 58, radius: 14)),
                ])
              else
                Row(children: [
                  Expanded(
                      child: _Stat(
                          label: 'Total',
                          value: _total,
                          color: AppColors.brand,
                          bg: AppColors.brandSoft)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Stat(
                          label: 'Synced',
                          value: _synced,
                          color: AppColors.green,
                          bg: AppColors.greenSoft)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Stat(
                          label: 'Not synced',
                          value: _notSynced,
                          color: AppColors.orange,
                          bg: AppColors.orangeSoft)),
                ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: AppButtons.primarySoft,
                      onPressed:
                          _busy || counting || _total == 0 ? null : _exportOnly,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: AppButtons.dangerSoft,
                      onPressed: _busy || counting || _total == 0
                          ? null
                          : _exportAndClear,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('Export & clear'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          FadeSlideIn(
            index: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 16, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not-synced transactions are kept unless you choose '
                      'to delete them too. They are not on the server yet.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label,
      required this.value,
      required this.color,
      required this.bg});
  final String label;
  final int value;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          CountUp(
            value: value.toDouble(),
            format: (v) => v.round().toString(),
            style: TextStyle(
                fontSize: 20, fontWeight: AppText.semibold, color: color),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

/// Returns true (also delete not-synced), false (synced only), null (cancel).
class _ClearDialog extends StatefulWidget {
  const _ClearDialog(
      {required this.range, required this.synced, required this.notSynced});
  final String range;
  final int synced;
  final int notSynced;

  @override
  State<_ClearDialog> createState() => _ClearDialogState();
}

class _ClearDialogState extends State<_ClearDialog> {
  bool _alsoUnsynced = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.synced + (_alsoUnsynced ? widget.notSynced : 0);
    return AlertDialog(
      icon: Icon(Icons.delete_sweep_outlined, color: AppColors.red, size: 32),
      title: const Text('Clear transactions?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The export is done. Delete from this phone:\n${widget.range}',
              style: TextStyle(color: AppColors.textSecondary)),
          if (widget.notSynced > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _alsoUnsynced,
                activeColor: AppColors.red,
                onChanged: (v) => setState(() => _alsoUnsynced = v ?? false),
                title: Text(
                    'Also delete ${widget.notSynced} not synced (not on the server)',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        ElevatedButton(
          style: AppButtons.neutral,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: AppButtons.danger,
          onPressed:
              count == 0 ? null : () => Navigator.pop(context, _alsoUnsynced),
          child: Text('Delete $count'),
        ),
      ],
    );
  }
}
