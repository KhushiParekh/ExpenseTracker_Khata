import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../models/models.dart';
import '../../data/local/app_database.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/stat_charts.dart';
import '../../widgets/ui_kit.dart';

/// A DEDICATED ledger for entries ticked "Mark as yearly expense" in the
/// add-entry modal (shoes, clothes, courses, insurance...). Regular
/// day-to-day transactions never appear here — those live in the
/// Calendar / Monthly / Total tabs.
///
/// Layout: Biggest month + Total cards → month list → chart → categories
/// donut → individual entries.
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
        final hasData = yearTotal > 0;

        // Months that actually have yearly spend, biggest first.
        final ranked = months.where((m) => m.expense > 0).toList()..sort((a, b) => b.expense.compareTo(a.expense));
        final maxMonth = ranked.isEmpty ? 1.0 : ranked.first.expense;

        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // ---- Summary cards ----
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: TwoUp(
                left: StatCard(
                  label: 'Biggest month',
                  value: hasData && biggest != null
                      ? '${DateFormat.MMM().format(DateTime(biggest.year, biggest.month))} · ${fmtMoney(biggest.expense)}'
                      : '—',
                  color: AppColors.accent,
                  icon: Icons.local_fire_department_outlined,
                  subtitle: hasData ? 'Highest yearly spend' : 'Nothing yet',
                ),
                right: StatCard(
                  label: 'Total expense',
                  value: fmtMoney(yearTotal),
                  color: AppColors.expense,
                  icon: Icons.event_repeat_outlined,
                  subtitle: hasData
                      ? 'Avg ${fmtMoney(yearTotal / activeMonths)} · $activeMonths month${activeMonths == 1 ? '' : 's'}'
                      : 'Yearly-marked spend',
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
              child: Text(
                'These are kept out of your monthly totals on purpose.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),

            if (!hasData)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: Icons.event_repeat_outlined,
                  message: 'Tick "Mark as yearly expense" when adding a transaction\nand it will show up here.',
                ),
              )
            else ...[
              // ---- Month list ----
              const SectionTitle('By month'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  children: [
                    for (final m in ranked)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                DateFormat.MMM().format(DateTime(m.year, m.month)),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (m.expense / maxMonth).clamp(0.0, 1.0),
                                  minHeight: 7,
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.expense),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 78,
                              child: Text(
                                fmtMoney(m.expense),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.expense),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

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
                      return const ChartCard(title: 'By categories', height: 170, child: Center(child: CircularProgressIndicator()));
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
              const SectionTitle('Entries'),
              categoriesAsync.when(
                data: (categories) {
                  final catsById = {for (final c in categories) c.id: c};
                  return StreamBuilder<List<Transaction>>(
                    stream: txnRepo.watchYearlyMarkedBetween(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59)),
                    builder: (context, rowsSnap) {
                      final rows = List<Transaction>.from(rowsSnap.data ?? const <Transaction>[])
                        ..sort((a, b) => b.txnDate.compareTo(a.txnDate));
                      if (rows.isEmpty) return const SizedBox.shrink();
                      return AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (int i = 0; i < rows.length; i++) ...[
                              if (i > 0) const Divider(height: 1, indent: 66, endIndent: 14),
                              _entryRow(context, ref, rows[i], rows[i].categoryId == null ? null : catsById[rows[i].categoryId]),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _entryRow(BuildContext context, WidgetRef ref, Transaction t, Category? cat) {
    final hasRemark = t.remark.trim().isNotEmpty;
    return InkWell(
      onTap: () => showEditTransactionModal(context, ref, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.expense.withOpacity(0.13), borderRadius: BorderRadius.circular(11)),
              child: Text(cat?.icon ?? '📁', style: const TextStyle(fontSize: 19)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRemark ? t.remark.trim() : (cat?.name ?? 'Yearly expense'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('d MMM yyyy').format(t.txnDate)}${cat == null ? '' : ' · ${cat.name}'}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fmtMoney(t.amount, decimals: t.amount % 1 != 0),
              style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
