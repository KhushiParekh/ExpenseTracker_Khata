import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../models/models.dart';
import '../../widgets/stat_charts.dart';
import '../../widgets/ui_kit.dart';

enum StatsRange { weekly, monthly, annually }

final _statsRangeProvider = StateProvider<StatsRange>((ref) => StatsRange.monthly);
final _statsAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());
final _statsKindProvider = StateProvider<String>((ref) => 'expense'); // 'expense' | 'income'

/// Unlike the Home tabs, Statistics counts EVERYTHING — including entries
/// marked as a yearly expense — so this is the true picture of spending.
///
/// Layout: Income | Expense tabs → Weekly / Monthly / Annually → period
/// navigator → category donut → Total + Biggest/Lowest cards → trend chart
/// → full category list.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  (DateTime, DateTime, String) _rangeFor(StatsRange range, DateTime anchor) {
    switch (range) {
      case StatsRange.weekly:
        final weekday = anchor.weekday % 7; // Sunday = 0
        final start = anchor.subtract(Duration(days: weekday));
        final end = start.add(const Duration(days: 6));
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(end.year, end.month, end.day, 23, 59, 59),
          '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}'
        );
      case StatsRange.monthly:
        final start = DateTime(anchor.year, anchor.month, 1);
        final end = DateTime(anchor.year, anchor.month + 1, 1).subtract(const Duration(seconds: 1));
        return (start, end, DateFormat('MMM yyyy').format(anchor));
      case StatsRange.annually:
        return (DateTime(anchor.year, 1, 1), DateTime(anchor.year, 12, 31, 23, 59, 59), '${anchor.year}');
    }
  }

  DateTime _shift(StatsRange range, DateTime anchor, int direction) {
    switch (range) {
      case StatsRange.weekly:
        return anchor.add(Duration(days: 7 * direction));
      case StatsRange.monthly:
        return DateTime(anchor.year, anchor.month + direction, 1);
      case StatsRange.annually:
        return DateTime(anchor.year + direction, anchor.month, 1);
    }
  }

  /// Sums [rows] into one bucket per day (weekly / monthly) or per month
  /// (annually). Shared by the trend chart and the Biggest / Lowest card.
  List<double> _buckets(List<MapEntry<DateTime, double>> events, DateTime start, DateTime end, StatsRange range) {
    if (range == StatsRange.annually) {
      final byMonth = List<double>.filled(12, 0);
      for (final e in events) {
        byMonth[e.key.month - 1] += e.value;
      }
      return byMonth;
    }
    final dayCount = end.difference(start).inDays + 1;
    final byDay = List<double>.filled(dayCount, 0);
    final s = DateTime(start.year, start.month, start.day);
    for (final e in events) {
      final idx = DateTime(e.key.year, e.key.month, e.key.day).difference(s).inDays;
      if (idx >= 0 && idx < dayCount) byDay[idx] += e.value;
    }
    return byDay;
  }

  String _bucketLabel(int i, DateTime start, StatsRange range) {
    if (range == StatsRange.annually) return DateFormat.MMM().format(DateTime(start.year, i + 1));
    return DateFormat('d MMM').format(DateTime(start.year, start.month, start.day + i));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(_statsRangeProvider);
    final anchor = ref.watch(_statsAnchorProvider);
    final kind = ref.watch(_statsKindProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final (start, end, label) = _rangeFor(range, anchor);
    final isIncome = kind == 'income';
    final kindColor = isIncome ? AppColors.incomeGreen : AppColors.expense;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: Column(
        children: [
          // ---- Income | Expense tabs ----
          Row(
            children: [
              _KindTab(
                label: 'Income',
                icon: Icons.arrow_downward_rounded,
                color: AppColors.incomeGreen,
                selected: isIncome,
                onTap: () => ref.read(_statsKindProvider.notifier).state = 'income',
              ),
              _KindTab(
                label: 'Expense',
                icon: Icons.arrow_upward_rounded,
                color: AppColors.expense,
                selected: !isIncome,
                onTap: () => ref.read(_statsKindProvider.notifier).state = 'expense',
              ),
            ],
          ),
          const Divider(height: 1),

          // ---- Weekly / Monthly / Annually ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  for (final r in StatsRange.values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          ref.read(_statsRangeProvider.notifier).state = r;
                          ref.read(_statsAnchorProvider.notifier).state = DateTime.now();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: r == range ? kindColor.withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Text(
                            const {StatsRange.weekly: 'Weekly', StatsRange.monthly: 'Monthly', StatsRange.annually: 'Annually'}[r]!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: r == range ? kindColor : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ---- Period navigator ----
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => ref.read(_statsAnchorProvider.notifier).state = _shift(range, anchor, -1),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 150),
                  child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => ref.read(_statsAnchorProvider.notifier).state = _shift(range, anchor, 1),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: txnRepo.watchStatsTransactionsBetween(start, end),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final rows = snap.data!;

                final db = ref.watch(appDatabaseProvider);
                return StreamBuilder<List<PeopleEntry>>(
                  stream: db.watchPeopleEntriesByEntryDate(start, end),
                  builder: (context, peopleSnap) {
                    final people = peopleSnap.data ?? const <PeopleEntry>[];
                    return StreamBuilder<List<PeopleEntry>>(
                      stream: db.watchSettledPeopleEntriesBySettleDate(start, end),
                      builder: (context, settledSnap) {
                        final peopleSettled = settledSnap.data ?? const <PeopleEntry>[];

                final matching = rows.where((r) => r.type == kind).toList();

                // Combine into (date, signed amount) events. People only
                // ever affects 'expense', never 'income'.
                final events = <MapEntry<DateTime, double>>[
                  for (final r in matching) MapEntry(r.txnDate, r.amount),
                  if (kind == 'expense') ...[
                    for (final p in people.where((p) => p.type == 'lent'))
                      MapEntry(p.entryDate, p.amount),
                    for (final p in peopleSettled)
                      MapEntry(p.settledAt!, p.type == 'borrowed' ? p.amount : -p.amount),
                  ],
                ];

                final total = events.fold(0.0, (a, b) => a + b.value);
                final yearlyPortion = matching.where((r) => r.isYearly).fold(0.0, (a, b) => a + b.amount);

                // Biggest / lowest bucket (day or month) that has any activity.
                final buckets = _buckets(events, start, end, range);
                int? bigIdx, lowIdx;
                for (int i = 0; i < buckets.length; i++) {
                  if (buckets[i] <= 0) continue;
                  if (bigIdx == null || buckets[i] > buckets[bigIdx]) bigIdx = i;
                  if (lowIdx == null || buckets[i] < buckets[lowIdx]) lowIdx = i;
                }
                final int? big = bigIdx;
                final int? low = lowIdx;

                return categoriesAsync.when(
                  data: (categories) {
                    final slices = kind == 'expense'
                        ? txnRepo.categoryBreakdownWithPeople(rows, people, peopleSettled, categories, kind: 'expense')
                        : txnRepo.categoryBreakdown(rows, categories, kind: 'income');
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // ---- By category ----
                        ChartCard(
                          title: 'By category',
                          subtitle: label,
                          height: 180,
                          child: CompactCategoryDonut(slices: slices),
                        ),

                        // ---- Total + Biggest / Lowest ----
                        TwoUp(
                          left: StatCard(
                            label: 'Total ${isIncome ? 'income' : 'expense'}',
                            value: fmtMoney(total),
                            color: kindColor,
                            icon: isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            subtitle: '${matching.length} transaction${matching.length == 1 ? '' : 's'}'
                                '${yearlyPortion > 0 ? ' · ${compactAmount(yearlyPortion)} yearly' : ''}',
                          ),
                          right: AppCard(
                            margin: EdgeInsets.zero,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _extremeLine(
                                  'Biggest ${isIncome ? 'income' : 'expense'}',
                                  big == null ? '—' : '${_bucketLabel(big, start, range)} · ${fmtMoney(buckets[big])}',
                                  kindColor,
                                ),
                                const SizedBox(height: 10),
                                _extremeLine(
                                  'Lowest ${isIncome ? 'income' : 'expense'}',
                                  low == null ? '—' : '${_bucketLabel(low, start, range)} · ${fmtMoney(buckets[low])}',
                                  Colors.grey.shade300,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ---- Trend within the period ----
                        ChartCard(
                          title: range == StatsRange.annually ? 'Month by month' : 'Day by day',
                          subtitle: 'Trend across $label',
                          height: 170,
                          child: _PeriodTrendChart(
                            events: events,
                            start: start,
                            end: end,
                            range: range,
                            color: kindColor,
                          ),
                        ),

                        // ---- Full category list ----
                        if (slices.isNotEmpty) ...[
                          const SectionTitle('All categories'),
                          AppCard(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                for (int i = 0; i < slices.length; i++) ...[
                                  if (i > 0) const Divider(height: 1, indent: 60, endIndent: 14),
                                  _categoryRow(slices[i], i),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _extremeLine(String label, String value, Color valueColor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor)),
          ),
        ],
      );

  Widget _categoryRow(CategorySlice s, int index) {
    // Same colours as the donut: top six get palette colours, the rest grey.
    final color = index < 6 ? AppColors.chartPalette[index % AppColors.chartPalette.length] : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(10)),
            child: Text(s.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (s.percent / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtMoney(s.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text('${s.percent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One half of the Income | Expense tab strip, with an underline indicator.
class _KindTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _KindTab({required this.label, required this.icon, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? color : Colors.transparent, width: 2.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? color : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: selected ? color : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buckets the period's transactions by day (weekly/monthly view) or by
/// month (annual view) and draws them as bars.
class _PeriodTrendChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> events;
  final DateTime start;
  final DateTime end;
  final StatsRange range;
  final Color color;

  const _PeriodTrendChart({
    required this.events,
    required this.start,
    required this.end,
    required this.range,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Reuse the month-summary bar chart for the annual view.
    if (range == StatsRange.annually) {
      final byMonth = List<double>.filled(13, 0);
      for (final e in events) {
        byMonth[e.key.month] += e.value;
      }
      final months = [
        for (int m = 1; m <= 12; m++) MonthSummary(year: start.year, month: m, income: 0, expense: byMonth[m])
      ];
      return SingleSeriesBarChart(months: months, color: color);
    }

    // Day buckets for weekly/monthly.
    final dayCount = end.difference(start).inDays + 1;
    final byDay = List<double>.filled(dayCount, 0);
    for (final e in events) {
      final idx = DateTime(e.key.year, e.key.month, e.key.day).difference(DateTime(start.year, start.month, start.day)).inDays;
      if (idx >= 0 && idx < dayCount) byDay[idx] += e.value;
    }

    final maxVal = byDay.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxVal == 0) {
      return const Center(child: Text('Nothing recorded for this period', style: TextStyle(color: Colors.grey, fontSize: 12)));
    }
    final maxY = maxVal * 1.2;
    // With ~30 day buckets, labelling every bar would overlap, so step.
    final labelEvery = dayCount > 15 ? 5 : 1;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final date = start.add(Duration(days: group.x));
              return BarTooltipItem(
                '${DateFormat('d MMM').format(date)}\n$kCurrencySymbol${rod.toY.toStringAsFixed(0)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                compactAmount(value),
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dayCount || i % labelEvery != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${start.add(Duration(days: i)).day}',
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < dayCount; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: byDay[i],
                  color: color,
                  width: dayCount > 15 ? 5 : 12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
