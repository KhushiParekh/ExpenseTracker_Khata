import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../models/models.dart';
import '../../widgets/stat_charts.dart';

enum StatsRange { weekly, monthly, annually }

final _statsRangeProvider = StateProvider<StatsRange>((ref) => StatsRange.monthly);
final _statsAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());
final _statsKindProvider = StateProvider<String>((ref) => 'expense'); // 'expense' | 'income'

/// Unlike the Home tabs, Statistics counts EVERYTHING — including entries
/// marked as a yearly expense — so this is the true picture of spending.
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
        return (start, end, DateFormat('MMMM yyyy').format(anchor));
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(_statsRangeProvider);
    final anchor = ref.watch(_statsAnchorProvider);
    final kind = ref.watch(_statsKindProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final (start, end, label) = _rangeFor(range, anchor);
    final isIncome = kind == 'income';

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<StatsRange>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: StatsRange.weekly, label: Text('Weekly')),
                ButtonSegment(value: StatsRange.monthly, label: Text('Monthly')),
                ButtonSegment(value: StatsRange.annually, label: Text('Annually')),
              ],
              selected: {range},
              onSelectionChanged: (s) {
                ref.read(_statsRangeProvider.notifier).state = s.first;
                ref.read(_statsAnchorProvider.notifier).state = DateTime.now();
              },
            ),
          ),

          // Period navigator, mirroring the Home screen's header.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(_statsAnchorProvider.notifier).state = _shift(range, anchor, -1),
              ),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ref.read(_statsAnchorProvider.notifier).state = _shift(range, anchor, 1),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.arrow_downward, size: 15)),
                ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward, size: 15)),
              ],
              selected: {kind},
              onSelectionChanged: (s) => ref.read(_statsKindProvider.notifier).state = s.first,
            ),
          ),
          const SizedBox(height: 6),

          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: txnRepo.watchStatsTransactionsBetween(start, end),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final rows = snap.data!;
                final matching = rows.where((r) => r.type == kind).toList();
                final total = matching.fold(0.0, (a, b) => a + b.amount);
                final yearlyPortion = matching.where((r) => r.isYearly).fold(0.0, (a, b) => a + b.amount);

                return categoriesAsync.when(
                  data: (categories) {
                    final slices = txnRepo.categoryBreakdown(rows, categories, kind: kind);

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // ---- Headline ----
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: (isIncome ? AppColors.incomeGreen : AppColors.expense).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: (isIncome ? AppColors.incomeGreen : AppColors.expense).withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Total ${isIncome ? 'income' : 'expense'}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$kCurrencySymbol${total.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: isIncome ? AppColors.incomeGreen : AppColors.expense,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 26,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${matching.length} transaction${matching.length == 1 ? '' : 's'}'
                                '${yearlyPortion > 0 ? ' · includes $kCurrencySymbol${yearlyPortion.toStringAsFixed(0)} yearly-marked' : ''}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        // ---- Category donut ----
                        ChartCard(
                          title: 'By category',
                          subtitle: label,
                          height: 180,
                          child: CompactCategoryDonut(slices: slices),
                        ),

                        // ---- Trend within the period ----
                        ChartCard(
                          title: range == StatsRange.annually ? 'Month by month' : 'Day by day',
                          subtitle: 'Trend across $label',
                          height: 170,
                          child: _PeriodTrendChart(
                            rows: matching,
                            start: start,
                            end: end,
                            range: range,
                            color: isIncome ? AppColors.incomeGreen : AppColors.expense,
                          ),
                        ),

                        // ---- Full category list ----
                        if (slices.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Text('All categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          const Divider(height: 1),
                          ...slices.map((s) => ListTile(
                                dense: true,
                                leading: Text(s.icon, style: const TextStyle(fontSize: 18)),
                                title: Text(s.name, style: const TextStyle(fontSize: 14)),
                                subtitle: LinearProgressIndicator(
                                  value: (s.percent / 100).clamp(0, 1),
                                  minHeight: 3,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation(isIncome ? AppColors.incomeGreen : AppColors.expense),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$kCurrencySymbol${s.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('${s.percent.toStringAsFixed(0)}%',
                                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              )),
                        ],
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Buckets the period's transactions by day (weekly/monthly view) or by
/// month (annual view) and draws them as bars.
class _PeriodTrendChart extends StatelessWidget {
  final List<Transaction> rows;
  final DateTime start;
  final DateTime end;
  final StatsRange range;
  final Color color;

  const _PeriodTrendChart({
    required this.rows,
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
      for (final r in rows) {
        byMonth[r.txnDate.month] += r.amount;
      }
      final months = [
        for (int m = 1; m <= 12; m++) MonthSummary(year: start.year, month: m, income: 0, expense: byMonth[m])
      ];
      return SingleSeriesBarChart(months: months, color: color);
    }

    // Day buckets for weekly/monthly.
    final dayCount = end.difference(start).inDays + 1;
    final byDay = List<double>.filled(dayCount, 0);
    for (final r in rows) {
      final idx = DateTime(r.txnDate.year, r.txnDate.month, r.txnDate.day).difference(DateTime(start.year, start.month, start.day)).inDays;
      if (idx >= 0 && idx < dayCount) byDay[idx] += r.amount;
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
