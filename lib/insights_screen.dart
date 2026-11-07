import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db/database.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'widgets/page_hero.dart';
import 'widgets/skeleton.dart';

/// Today vs yesterday, a 7-day bar chart and the best customers. Read from the
/// phone's own database, so it works offline. Lives under Profile so the Home
/// overview stays short and quick.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  static final _key = DateFormat('yyyy-MM-dd');
  static final _short = DateFormat('E');
  static final _money = NumberFormat('#,##0', 'en_US');

  Map<String, Map<String, double>>? _totals;
  List<Map<String, dynamic>> _top = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final totals = await AppDatabase.getDailyTotals(7);
    final top = await AppDatabase.getTopCustomers(7);
    if (!mounted) return;
    setState(() {
      _totals = totals;
      _top = top;
    });
  }

  double _sum(DateTime d, String type) => _totals?[_key.format(d)]?[type] ?? 0;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: SafeArea(
        child: _totals == null
            ? ListView(padding: const EdgeInsets.all(16), children: const [
                SkeletonBox(height: 110),
                SizedBox(height: 14),
                SkeletonBox(height: 190),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const PageHero(
                    icon: Icons.insights_rounded,
                    title: 'Insights',
                    subtitle: 'How today compares, and the last 7 days',
                  ),
                  Row(children: [
                    Expanded(
                        child: _Compare(
                            label: 'Orders',
                            today: _sum(today, 'Order'),
                            yesterday: _sum(yesterday, 'Order'),
                            upIsGood: true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Compare(
                            label: 'Cash',
                            today: _sum(today, 'Cash'),
                            yesterday: _sum(yesterday, 'Cash'),
                            upIsGood: true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Compare(
                            label: 'Returns',
                            today: _sum(today, 'Return'),
                            yesterday: _sum(yesterday, 'Return'),
                            // A bigger return is not good news.
                            upIsGood: false)),
                  ]),
                  const SizedBox(height: 16),
                  _chartCard(today),
                  const SizedBox(height: 16),
                  _topCard(),
                ],
              ),
      ),
    );
  }

  Widget _chartCard(DateTime today) {
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))
    ];
    final orders = [for (final d in days) _sum(d, 'Order')];
    final cash = [for (final d in days) _sum(d, 'Cash')];
    final maxV = [...orders, ...cash, 1.0].reduce((a, b) => a > b ? a : b);
    return FadeSlideIn(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: glassDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('Last 7 days',
                    style: TextStyle(
                        fontWeight: AppText.semibold,
                        fontSize: 16,
                        color: AppColors.textPrimary))),
            _Legend(color: AppColors.accent, label: 'Orders'),
            const SizedBox(width: 12),
            _Legend(color: AppColors.green, label: 'Cash'),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Semantics(
                      label: '${_short.format(days[i])}: orders '
                          '${_money.format(orders[i])}, cash ${_money.format(cash[i])}',
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Bar(
                                    fraction: orders[i] / maxV,
                                    color: AppColors.accent),
                                const SizedBox(width: 3),
                                _Bar(
                                    fraction: cash[i] / maxV,
                                    color: AppColors.green),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_short.format(days[i]),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == 6
                                      ? AppText.semibold
                                      : AppText.regular,
                                  color: i == 6
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _topCard() {
    return FadeSlideIn(
      index: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: glassDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Top customers (orders, 7 days)',
              style: TextStyle(
                  fontWeight: AppText.semibold,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (_top.isEmpty)
            Text('No orders in the last 7 days.',
                style: TextStyle(color: AppColors.textSecondary))
          else
            for (var i = 0; i < _top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.brandSoft,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: AppText.semibold,
                            color: AppColors.brand)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${_top[i]['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Text('Rs. ${_money.format(_top[i]['amt'] ?? 0)}',
                      style: TextStyle(
                          fontWeight: AppText.semibold,
                          color: AppColors.textPrimary)),
                ]),
              ),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight * fraction.clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: fraction > 0 ? h.clamp(3.0, c.maxHeight) : 0,
            constraints: const BoxConstraints(maxWidth: 12),
            decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4))),
          ),
        );
      }),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]);
}

/// One tile: today's amount and a badge against yesterday.
class _Compare extends StatelessWidget {
  const _Compare(
      {required this.label,
      required this.today,
      required this.yesterday,
      required this.upIsGood});
  final String label;
  final double today;
  final double yesterday;
  final bool upIsGood;

  static final _money = NumberFormat('#,##0', 'en_US');

  @override
  Widget build(BuildContext context) {
    final diff = today - yesterday;
    String badge = 'same as yesterday';
    Color tone = AppColors.textSecondary;
    IconData icon = Icons.remove_rounded;
    if (yesterday == 0 && today == 0) {
      badge = 'no activity';
    } else if (yesterday == 0) {
      badge = 'new today';
      icon = Icons.arrow_upward_rounded;
      tone = upIsGood ? AppColors.green : AppColors.red;
    } else if (diff != 0) {
      final pct = (diff.abs() / yesterday * 100).round();
      badge = '$pct% vs yesterday';
      icon =
          diff > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      tone = (diff > 0) == upIsGood ? AppColors.green : AppColors.red;
    }
    return FadeSlideIn(
      child: Semantics(
        container: true,
        label: '$label today ${_money.format(today)}, $badge',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: glassDecoration(),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_money.format(today),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: AppText.semibold,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 14, color: tone),
              const SizedBox(width: 2),
              Expanded(
                child: Text(badge,
                    maxLines: 2, style: TextStyle(fontSize: 11, color: tone)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
