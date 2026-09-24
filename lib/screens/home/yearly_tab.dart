import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../models/models.dart';
import '../../data/local/app_database.dart';
import '../../widgets/stat_charts.dart';

/// A DEDICATED ledger for entries ticked "Mark as yearly expense" in the
/// add-entry modal (shoes, clothes, courses, insurance...). Regular
/// day-to-day transactions never appear here — those live in the
/// Calendar / Monthly / Total tabs.
class YearlyTab extends ConsumerWidget {
  const YearlyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final year = focused.year;
    final totalsRepo = ref.watch(homeTotalsRepoProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);

    return StreamBuilder<List<MonthSummary>>(
      stream: totalsRepo.watchYearlyTabMonthlySummaries(year),
      builder: (context, monthSnap) {
        if (!monthSnap.hasData) return const Center(child: CircularProgressIndicator());
        final months = monthSnap.data!;
        final yearTotal = months.fold(0.0, (a, b) => a + b.expense);
        final activeMonths = months.where((m) => m.expense > 0).length;
        final biggest = months.isEmpty ? null : months.reduce((a, b) => a.expense >= b.expense ? a : b);

        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            // ---- Summary ----
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.expense.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.expense.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Yearly-marked spend', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        '$kCurrencySymbol${yearTotal.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeMonths == 0
                        ? 'Nothing marked as a yearly expense in $year yet.'
                        : 'Across $activeMonths month${activeMonths == 1 ? '' : 's'} of $year. '
                            'These are kept out of your monthly totals on purpose.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                  ),
                ],
              ),
            ),

            if (biggest != null && biggest.expense > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Biggest month',
                        value: '${DateFormat.MMM().format(DateTime(biggest.year, biggest.month))} · $kCurrencySymbol${compactAmount(biggest.expense)}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'Total Expense',
                        value: '$kCurrencySymbol${compactAmount(yearTotal)}',
                      ),
                    ),
                  ],
                ),
              ),

            // ---- Month-by-month rows (only months with yearly-marked spend) ----
            if (activeMonths > 0) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Builder(builder: (context) {
                  final activeMonths = months.where((m) => m.expense > 0).toList().reversed.toList();
                  return Column(
                    children: [
                      for (int i = 0; i < activeMonths.length; i++) ...[
                        ListTile(
                          dense: true,
                          title: Text(DateFormat.MMMM().format(DateTime(activeMonths[i].year, activeMonths[i].month)), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          trailing: Text(
                            '$kCurrencySymbol${activeMonths[i].expense.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold),
                          ),
                          onTap: () => ref.read(focusedMonthProvider.notifier).state = DateTime(activeMonths[i].year, activeMonths[i].month),
                        ),
                        if (i < activeMonths.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
                      ],
                    ],
                  );
                }),
              ),
            ],

            // ---- Charts ----
            ChartCard(
              title: 'Yearly expenses by month',
              subtitle: 'When the big one-off spends landed',
              height: 175,
              child: SingleSeriesBarChart(months: months, color: AppColors.expense),
            ),
            categoriesAsync.when(
              data: (categories) => StreamBuilder<List<Transaction>>(
                stream: txnRepo.watchYearlyMarkedBetween(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59)),
                builder: (context, rowsSnap) {
                  if (!rowsSnap.hasData) {
                    return const ChartCard(title: 'By category', height: 170, child: Center(child: CircularProgressIndicator()));
                  }
                  final slices = txnRepo.categoryBreakdown(rowsSnap.data!, categories, kind: 'expense');
                  return ChartCard(
                    title: 'By categories',
                    subtitle: 'Yearly-marked spend, $year',
                    height: 170,
                    child: CompactCategoryDonut(slices: slices),
                  );
                },
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),

            // ---- Individual entries ----
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Entries', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const Divider(height: 1),
            categoriesAsync.when(
              data: (categories) {
                final catsById = {for (final c in categories) c.id: c};
                return StreamBuilder<List<Transaction>>(
                  stream: txnRepo.watchYearlyMarkedBetween(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59)),
                  builder: (context, rowsSnap) {
                    final rows = (rowsSnap.data ?? [])..sort((a, b) => b.txnDate.compareTo(a.txnDate));
                    if (rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: Text(
                            'Tick "Mark as yearly expense" when adding a transaction\nand it will show up here.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: rows.map((t) {
                        final cat = t.categoryId == null ? null : catsById[t.categoryId];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.expense.withOpacity(0.12),
                            child: Text(cat?.icon ?? '📁', style: const TextStyle(fontSize: 15)),
                          ),
                          title: Text(
                            t.remark.isEmpty ? (cat?.name ?? 'Yearly expense') : t.remark,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${DateFormat('d MMM yyyy').format(t.txnDate)}${cat == null ? '' : ' · ${cat.name}'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            '$kCurrencySymbol${t.amount.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
            ),
          ],
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
