import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../models/models.dart';
import '../../data/local/app_database.dart';
import '../../widgets/stat_charts.dart';

final _heroKindProvider = StateProvider<String>((ref) => 'expense'); // 'income' | 'expense'

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
    final now = DateTime.now();

    return StreamBuilder<List<MonthSummary>>(
      stream: repo.watchMonthlySummaries(focused.year),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final months = snapshot.data!;

        final yearIncome = months.fold(0.0, (a, b) => a + b.income);
        final yearExpense = months.fold(0.0, (a, b) => a + b.expense);
        final busiest = months.isEmpty ? null : months.reduce((a, b) => a.expense >= b.expense ? a : b);

        // "This month" is always the real current month — kept pinned to
        // the top regardless of which year the list below is browsing.
        final otherMonths = months.reversed.where((m) => !(m.year == now.year && m.month == now.month)).toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            // ---- 1. This month, always on top ----
            _CurrentMonthHero(),

            // ---- 2. Month by month (rest of the focused year) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${focused.year}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    'In $kCurrencySymbol${compactAmount(yearIncome)}  ·  Out $kCurrencySymbol${compactAmount(yearExpense)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  for (final m in otherMonths) ...[
                    _MonthRow(summary: m, onTap: () => ref.read(focusedMonthProvider.notifier).state = DateTime(m.year, m.month)),
                    if (m != otherMonths.last) const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                  if (otherMonths.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No other months yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                ],
              ),
            ),

            if (busiest != null && busiest.expense > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _InsightTile(
                  label: 'Biggest month of ${focused.year}',
                  value: '${DateFormat.MMMM().format(DateTime(busiest.year, busiest.month))} · $kCurrencySymbol${compactAmount(busiest.expense)}',
                  icon: Icons.arrow_upward,
                ),
              ),

            // ---- 3. Charts ----
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
          ],
        );
      },
    );
  }
}

/// Pinned "this month" spotlight card: an Income/Expense toggle plus its
/// own category breakdown, so the person sees where they stand right now
/// before ever scrolling.
class _CurrentMonthHero extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final kind = ref.watch(_heroKindProvider);
    final isIncome = kind == 'income';
    final totalsRepo = ref.watch(homeTotalsRepoProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat.MMMM().format(now), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              SegmentedButton<String>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 'income', icon: Icon(Icons.arrow_downward, size: 14), label: Text('Income')),
                  ButtonSegment(value: 'expense', icon: Icon(Icons.arrow_upward, size: 14), label: Text('Expense')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => ref.read(_heroKindProvider.notifier).state = s.first,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('By category', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: StreamBuilder<List<Transaction>>(
              stream: txnRepo.watchHomeTransactionsBetween(DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1))),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                return categoriesAsync.when(
                  data: (categories) {
                    final slices = txnRepo.categoryBreakdown(snap.data!, categories, kind: kind);
                    return CompactCategoryDonut(slices: slices);
                  },
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => Text('$e'),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder(
            stream: totalsRepo.watchTotalsForMonth(now.year, now.month),
            builder: (context, snap) {
              final t = snap.data;
              final value = t == null ? 0.0 : (isIncome ? t.income : t.expense);
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total $kCurrencySymbol${value.toStringAsFixed(0)}',
                  style: TextStyle(color: isIncome ? AppColors.incomeGreen : AppColors.expense, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  final MonthSummary summary;
  final VoidCallback onTap;
  const _MonthRow({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat.MMMM().format(DateTime(summary.year, summary.month));
    final isEmpty = summary.income == 0 && summary.expense == 0;
    return Opacity(
      opacity: isEmpty ? 0.45 : 1,
      child: ListTile(
        dense: true,
        title: Text(monthName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          'In $kCurrencySymbol${summary.income.toStringAsFixed(0)}  ·  Out $kCurrencySymbol${summary.expense.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          '${summary.total >= 0 ? '+' : '-'}$kCurrencySymbol${summary.total.abs().toStringAsFixed(0)}',
          style: TextStyle(color: summary.total >= 0 ? AppColors.incomeGreen : AppColors.expense, fontWeight: FontWeight.bold),
        ),
        onTap: onTap,
      ),
    );
  }
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
