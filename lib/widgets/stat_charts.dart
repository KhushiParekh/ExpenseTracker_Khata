import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Formats large rupee figures compactly so axis labels never overflow
/// their allotted width (₹1,20,000 -> ₹1.2L).
String compactAmount(double v) {
  final abs = v.abs();
  if (abs >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (abs >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

/// A titled, fixed-height container. Every chart on the stats screens is
/// wrapped in one of these so charts can never push the layout around or
/// overflow — the height is decided here, not by the chart's contents.
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double height;
  final Widget child;
  final Widget? trailing;

  const ChartCard({
    super.key,
    required this.title,
    required this.height,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

/// Grouped income-vs-expense bars, one pair per month.
class IncomeExpenseBarChart extends StatelessWidget {
  final List<MonthSummary> months;
  const IncomeExpenseBarChart({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    final maxVal = months.fold<double>(
      0,
      (m, s) => [m, s.income, s.expense].reduce((a, b) => a > b ? a : b),
    );
    if (maxVal == 0) return const _EmptyChart();

    // Round the top of the axis up so bars never touch the ceiling.
    final maxY = maxVal * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 0 ? 'Income' : 'Expense';
              return BarTooltipItem(
                '$label\n$kCurrencySymbol${rod.toY.toStringAsFixed(0)}',
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
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat.MMM().format(DateTime(months[i].year, months[i].month)).substring(0, 1),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < months.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(toY: months[i].income, color: AppColors.incomeGreen, width: 5, borderRadius: BorderRadius.circular(2)),
                BarChartRodData(toY: months[i].expense, color: AppColors.expense, width: 5, borderRadius: BorderRadius.circular(2)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Single-series bars — used for "yearly-marked spend per month".
class SingleSeriesBarChart extends StatelessWidget {
  final List<MonthSummary> months;
  final Color color;
  const SingleSeriesBarChart({super.key, required this.months, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxVal = months.fold<double>(0, (m, s) => s.expense > m ? s.expense : m);
    if (maxVal == 0) return const _EmptyChart();
    final maxY = maxVal * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${DateFormat.MMM().format(DateTime(months[group.x].year, months[group.x].month))}\n'
              '$kCurrencySymbol${rod.toY.toStringAsFixed(0)}',
              const TextStyle(color: Colors.white, fontSize: 11),
            ),
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
              getTitlesWidget: (value, meta) => Text(compactAmount(value), style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat.MMM().format(DateTime(months[i].year, months[i].month)).substring(0, 1),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < months.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [BarChartRodData(toY: months[i].expense, color: color, width: 11, borderRadius: BorderRadius.circular(3))],
            ),
        ],
      ),
    );
  }
}

/// Cumulative spend across the year — makes the pace of spending visible
/// in a way month-by-month bars don't.
class CumulativeLineChart extends StatelessWidget {
  final List<MonthSummary> months;
  const CumulativeLineChart({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    double runningExpense = 0, runningIncome = 0;
    final expenseSpots = <FlSpot>[];
    final incomeSpots = <FlSpot>[];
    for (int i = 0; i < months.length; i++) {
      runningExpense += months[i].expense;
      runningIncome += months[i].income;
      expenseSpots.add(FlSpot(i.toDouble(), runningExpense));
      incomeSpots.add(FlSpot(i.toDouble(), runningIncome));
    }

    final maxVal = [runningExpense, runningIncome].reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return const _EmptyChart();
    final maxY = maxVal * 1.2;

    return LineChart(
      LineChartData(
        maxY: maxY,
        minY: 0,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '$kCurrencySymbol${s.y.toStringAsFixed(0)}',
                      TextStyle(color: s.barIndex == 0 ? AppColors.expense : AppColors.incomeGreen, fontSize: 11),
                    ))
                .toList(),
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
              getTitlesWidget: (value, meta) => Text(compactAmount(value), style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat.MMM().format(DateTime(months[i].year, months[i].month)).substring(0, 1),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: expenseSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppColors.expense,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.expense.withOpacity(0.12)),
          ),
          LineChartBarData(
            spots: incomeSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppColors.incomeGreen,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.incomeGreen.withOpacity(0.10)),
          ),
        ],
      ),
    );
  }
}

/// Donut + a scrollable legend, sized to fit inside a ChartCard.
class CompactCategoryDonut extends StatelessWidget {
  final List<CategorySlice> slices;
  const CompactCategoryDonut({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const _EmptyChart();

    // Only the top slices get their own colour/label; the rest are rolled
    // into "Other" so the donut stays readable.
    const maxSlices = 6;
    final shown = slices.take(maxSlices).toList();
    final otherTotal = slices.skip(maxSlices).fold(0.0, (a, b) => a + b.amount);
    final total = slices.fold(0.0, (a, b) => a + b.amount);

    final sections = <PieChartSectionData>[
      for (int i = 0; i < shown.length; i++)
        PieChartSectionData(
          value: shown[i].amount,
          title: '',
          color: AppColors.chartPalette[i % AppColors.chartPalette.length],
          radius: 26,
        ),
      if (otherTotal > 0)
        PieChartSectionData(value: otherTotal, title: '', color: Colors.grey.shade700, radius: 26),
    ];

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 28)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(compactAmount(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const Text('total', style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (int i = 0; i < shown.length; i++)
                _legendRow(
                  AppColors.chartPalette[i % AppColors.chartPalette.length],
                  '${shown[i].icon} ${shown[i].name}',
                  shown[i].amount,
                  shown[i].percent,
                ),
              if (otherTotal > 0)
                _legendRow(Colors.grey.shade700, 'Other', otherTotal, total == 0 ? 0 : otherTotal / total * 100),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label, double amount, double percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Text('${percent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 6),
          Text(
            '$kCurrencySymbol${compactAmount(amount)}',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Nothing recorded for this period', style: TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
}
