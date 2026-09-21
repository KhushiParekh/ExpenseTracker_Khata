import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../models/models.dart';
import '../../data/local/app_database.dart';
import '../../widgets/stat_charts.dart';

/// Month-by-month view of the focused year. Yearly-marked expenses are
/// deliberately excluded here (they live in the Yearly tab), so these
/// figures reflect regular, recurring monthly spending only.
class MonthlyTab extends ConsumerWidget {
  const MonthlyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final repo = ref.watch(homeTotalsRepoProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);

    return StreamBuilder<List<MonthSummary>>(
      stream: repo.watchMonthlySummaries(focused.year),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final months = snapshot.data!;

        final yearIncome = months.fold(0.0, (a, b) => a + b.income);
        final yearExpense = months.fold(0.0, (a, b) => a + b.expense);
        final monthsWithSpend = months.where((m) => m.expense > 0).length;
        final avgSpend = monthsWithSpend == 0 ? 0.0 : yearExpense / monthsWithSpend;
        final busiest = months.isEmpty
            ? null
            : months.reduce((a, b) => a.expense >= b.expense ? a : b);

        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            // ---- Year summary strip ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _headerStat('Income', yearIncome, AppColors.incomeGreen),
                  _headerStat('Expenses', yearExpense, AppColors.expense),
                  _headerStat('Net', yearIncome - yearExpense, Colors.white),
                ],
              ),
            ),
            const Divider(height: 1),

            // ---- Insight chips ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
              child: Row(
                children: [
                  Expanded(
                    child: _InsightTile(
                      label: 'Avg / active month',
                      value: '$kCurrencySymbol${compactAmount(avgSpend)}',
                      icon: Icons.trending_flat,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InsightTile(
                      label: 'Highest month',
                      value: busiest == null || busiest.expense == 0
                          ? '—'
                          : '${DateFormat.MMM().format(DateTime(busiest.year, busiest.month))} · $kCurrencySymbol${compactAmount(busiest.expense)}',
                      icon: Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
            ),

            // ---- Charts ----
            ChartCard(
              title: 'Income vs Expense',
              subtitle: 'Each month of ${focused.year}',
              height: 180,
              child: IncomeExpenseBarChart(months: months),
            ),
            ChartCard(
              title: 'Cumulative through the year',
              subtitle: 'How spending and income build up',
              height: 170,
              child: CumulativeLineChart(months: months),
            ),
            categoriesAsync.when(
              data: (categories) => StreamBuilder<List<Transaction>>(
                stream: txnRepo.watchHomeTransactionsBetween(
                  DateTime(focused.year, 1, 1),
                  DateTime(focused.year, 12, 31, 23, 59, 59),
                ),
                builder: (context, rowsSnap) {
                  if (!rowsSnap.hasData) {
                    return const ChartCard(title: 'Where it went', height: 170, child: Center(child: CircularProgressIndicator()));
                  }
                  final slices = txnRepo.categoryBreakdown(rowsSnap.data!, categories, kind: 'expense');
                  return ChartCard(
                    title: 'Where it went',
                    subtitle: 'Expenses by category, ${focused.year}',
                    height: 170,
                    child: CompactCategoryDonut(slices: slices),
                  );
                },
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),

            // ---- Month list ----
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Month by month', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const Divider(height: 1),
            ...months.reversed.map((m) {
              final monthName = DateFormat.MMMM().format(DateTime(m.year, m.month));
              final isEmpty = m.income == 0 && m.expense == 0;
              return Opacity(
                opacity: isEmpty ? 0.45 : 1,
                child: ListTile(
                  dense: true,
                  title: Text(monthName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    'In $kCurrencySymbol${m.income.toStringAsFixed(0)}  ·  Out $kCurrencySymbol${m.expense.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    '${m.total >= 0 ? '+' : '-'}$kCurrencySymbol${m.total.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                      color: m.total >= 0 ? AppColors.incomeGreen : AppColors.expense,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => ref.read(focusedMonthProvider.notifier).state = DateTime(m.year, m.month),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _headerStat(String label, double value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            '$kCurrencySymbol${value.toStringAsFixed(0)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      );
}

class _InsightTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InsightTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
