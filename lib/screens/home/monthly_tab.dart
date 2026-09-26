import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../models/models.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../widgets/stat_charts.dart';
import '../../widgets/ui_kit.dart';

/// Month-by-month view of the focused year. Yearly-marked expenses are
/// deliberately excluded here (they live in the Yearly tab), so these
/// figures reflect regular, recurring monthly spending only.
///
/// Layout (top → bottom):
///   1. The "featured" month (this month for the current year) with
///      Income / Expense cards and a category donut.
///   2. Earlier months, newest first.
///   3. Year at a glance (totals + insights).
///   4. Charts: Income vs Expense, Cumulative, Where it went.
class MonthlyTab extends ConsumerStatefulWidget {
  const MonthlyTab({super.key});

  @override
  ConsumerState<MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends ConsumerState<MonthlyTab> {
  /// Which side of the featured month the donut is showing.
  String _kind = 'expense';

  void _openMonth(int year, int month) {
    ref.read(focusedMonthProvider.notifier).state = DateTime(year, month);
    ref.read(homeTabIndexProvider.notifier).state = 0; // jump to Calendar
  }

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(focusedMonthProvider);
    final repo = ref.watch(homeTotalsRepoProvider);
    final txnRepo = ref.watch(transactionRepoProvider);
    final db = ref.watch(appDatabaseProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final year = focused.year;

    return StreamBuilder<List<MonthSummary>>(
      stream: repo.watchMonthlySummaries(year),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final months = snapshot.data!;

        final yearIncome = months.fold(0.0, (a, b) => a + b.income);
        final yearExpense = months.fold(0.0, (a, b) => a + b.expense);
        final monthsWithSpend = months.where((m) => m.expense > 0).length;
        final avgSpend = monthsWithSpend == 0 ? 0.0 : yearExpense / monthsWithSpend;
        final busiest = months.isEmpty ? null : months.reduce((a, b) => a.expense >= b.expense ? a : b);

        // The "current" month is always pinned on top. For any other year
        // the latest month (December) takes that place.
        final now = DateTime.now();
        final isCurrentYear = year == now.year;
        final featuredMonth = isCurrentYear ? now.month : 12;
        final featured = months[featuredMonth - 1];
        final earlier = months.where((m) => m.month < featuredMonth).toList().reversed.toList();

        return StreamBuilder<List<PeopleEntry>>(
          stream: db.watchPeopleEntriesByEntryDate(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59)),
          builder: (context, peopleSnap) {
            final people = peopleSnap.data ?? const <PeopleEntry>[];

            return StreamBuilder<List<PeopleEntry>>(
              stream: db.watchSettledPeopleEntriesBySettleDate(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59)),
              builder: (context, settledSnap) {
                final peopleSettled = settledSnap.data ?? const <PeopleEntry>[];
                int settleLeft(int month) => people.where((p) => !p.settled && p.entryDate.month == month).length;

                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    // ---- 1. Featured month ----
                    _featuredCard(
                      featured: featured,
                      isCurrent: isCurrentYear,
                      settleLeft: settleLeft(featured.month),
                      categoriesAsync: categoriesAsync,
                      txnRepo: txnRepo,
                      people: people,
                      peopleSettled: peopleSettled,
                    ),

                    // ---- 2. Earlier months ----
                    if (earlier.isNotEmpty) SectionTitle('Earlier in $year'),
                    ...earlier.map((m) => _monthRow(m, settleLeft(m.month))),

                    // ---- 3. Year at a glance ----
                    SectionTitle('$year at a glance'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _headerStat('Income', yearIncome, AppColors.incomeGreen),
                          _headerStat('Expenses', yearExpense, AppColors.expense),
                          _headerStat('Net', yearIncome - yearExpense, yearIncome - yearExpense >= 0 ? AppColors.incomeGreen : AppColors.expense),
                        ],
                      ),
                    ),
                    TwoUp(
                      left: _InsightTile(
                        label: 'Avg / active month',
                        value: fmtMoney(avgSpend),
                        icon: Icons.trending_flat,
                      ),
                      right: _InsightTile(
                        label: 'Highest month',
                        value: busiest == null || busiest.expense == 0
                            ? '—'
                            : '${DateFormat.MMM().format(DateTime(busiest.year, busiest.month))} · ${fmtMoney(busiest.expense)}',
                        icon: Icons.arrow_upward,
                      ),
                    ),

                    // ---- 4. Charts ----
                    ChartCard(
                      title: 'Income vs Expense',
                      subtitle: 'Each month of $year',
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
                          DateTime(year, 1, 1),
                          DateTime(year, 12, 31, 23, 59, 59),
                        ),
                        builder: (context, rowsSnap) {
                          if (!rowsSnap.hasData) {
                            return const ChartCard(title: 'Where it went', height: 170, child: Center(child: CircularProgressIndicator()));
                          }
                          final slices = txnRepo.categoryBreakdownWithPeople(
                            rowsSnap.data!, people, peopleSettled, categories, kind: 'expense',
                          );
                          return ChartCard(
                            title: 'Where it went',
                            subtitle: 'Expenses by category, $year',
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
          },
        );
      },
    );
  }
  

  // -------------------------------------------------------------------------
  // Featured (current) month
  // -------------------------------------------------------------------------
  Widget _featuredCard({
    required MonthSummary featured,
    required bool isCurrent,
    required int settleLeft,
    required AsyncValue<List<Category>> categoriesAsync,
    required TransactionRepository txnRepo,
    required List<PeopleEntry> people,
    required List<PeopleEntry> peopleSettled,
  }) {
    final date = DateTime(featured.year, featured.month);
    final start = DateTime(featured.year, featured.month, 1);
    final end = DateTime(featured.year, featured.month + 1, 1).subtract(const Duration(milliseconds: 1));
    final isIncome = _kind == 'income';
    final net = featured.total;

    final monthPeople = people.where((p) =>
        !p.entryDate.isBefore(start) && !p.entryDate.isAfter(end)).toList();
    final monthSettled = peopleSettled.where((p) =>
        p.settledAt != null && !p.settledAt!.isBefore(start) && !p.settledAt!.isAfter(end)).toList();

    return AppCard(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      borderColor: AppColors.accent.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(DateFormat.MMMM().format(date), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        if (isCurrent) const MiniTag('THIS MONTH', color: AppColors.accent),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${featured.year}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _openMonth(featured.year, featured.month),
                icon: const Text('Open'),
                label: const Icon(Icons.chevron_right, size: 18),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Income',
                    value: fmtMoney(featured.income),
                    color: AppColors.incomeGreen,
                    icon: Icons.arrow_downward_rounded,
                    selected: isIncome,
                    onTap: () => setState(() => _kind = 'income'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    label: 'Expense',
                    value: fmtMoney(featured.expense),
                    color: AppColors.expense,
                    icon: Icons.arrow_upward_rounded,
                    selected: !isIncome,
                    onTap: () => setState(() => _kind = 'expense'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Net savings', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              Text(
                fmtMoney(net),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: net >= 0 ? AppColors.incomeGreen : AppColors.expense),
              ),
            ],
          ),
          if (settleLeft > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 13, color: AppColors.borrowedLent),
                const SizedBox(width: 5),
                Text(
                  '$settleLeft people transaction${settleLeft == 1 ? '' : 's'} left to settle',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.borrowedLent),
                ),
              ],
            ),
          ],
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
          Text(
            'By category · ${isIncome ? 'Income' : 'Expense'}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: categoriesAsync.when(
              data: (categories) => StreamBuilder<List<Transaction>>(
                stream: txnRepo.watchHomeTransactionsBetween(start, end),
                builder: (context, rowsSnap) {
                  if (!rowsSnap.hasData) return const Center(child: CircularProgressIndicator());
                  final slices = isIncome
                      ? txnRepo.categoryBreakdown(rowsSnap.data!, categories, kind: 'income')
                      : txnRepo.categoryBreakdownWithPeople(rowsSnap.data!, monthPeople, monthSettled, categories, kind: 'expense');
                  return CompactCategoryDonut(slices: slices);
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // One earlier month
  // -------------------------------------------------------------------------
  Widget _monthRow(MonthSummary m, int settleLeft) {
    final name = DateFormat.MMMM().format(DateTime(m.year, m.month));
    final isEmpty = m.income == 0 && m.expense == 0 && settleLeft == 0;

    String subtitle;
    Color subtitleColor = Colors.grey;
    if (settleLeft > 0) {
      subtitle = '$settleLeft people transaction${settleLeft == 1 ? '' : 's'} left to settle';
      subtitleColor = AppColors.borrowedLent;
    } else if (isEmpty) {
      subtitle = 'No activity';
    } else {
      subtitle = 'Net ${fmtMoney(m.total)}';
    }

    return Opacity(
      opacity: isEmpty ? 0.5 : 1,
      child: AppCard(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _openMonth(m.year, m.month),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: subtitleColor)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${fmtMoney(m.income)}', style: const TextStyle(color: AppColors.incomeGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text('-${fmtMoney(m.expense)}', style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, double value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 3),
          Text(fmtMoney(value), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
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
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
