import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/home_totals_repository.dart';
import '../../widgets/ui_kit.dart';

const _uuid = Uuid();

class TotalTab extends ConsumerWidget {
  const TotalTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final db = ref.watch(appDatabaseProvider);
    final totalsRepo = ref.watch(homeTotalsRepoProvider);

    return StreamBuilder<PeriodTotals>(
      stream: totalsRepo.watchTotalsForMonth(focused.year, focused.month),
      builder: (context, totalsSnap) {
        final totals = totalsSnap.data ?? PeriodTotals.zero;

        return StreamBuilder<Budget?>(
          stream: (db.select(db.budgets)..where((b) => b.year.equals(focused.year) & b.month.equals(focused.month))).watchSingleOrNull(),
          builder: (context, budgetSnap) {
            final budget = budgetSnap.data?.amount ?? 0;
            final spent = totals.expense;
            final pct = budget > 0 ? (spent / budget * 100) : 0.0;
            final remaining = budget - spent;

            // Days left / elapsed only make sense relative to today.
            final now = DateTime.now();
            final daysInMonth = DateUtils.getDaysInMonth(focused.year, focused.month);
            final isCurrent = focused.year == now.year && focused.month == now.month;
            final isPast = DateTime(focused.year, focused.month).isBefore(DateTime(now.year, now.month));
            final daysElapsed = isCurrent ? now.day : (isPast ? daysInMonth : 0);
            final daysLeft = isCurrent ? daysInMonth - now.day + 1 : 0;

            final Color barColor = pct > 100
                ? AppColors.expense
                : (pct >= 75 ? const Color(0xFFFFB84D) : AppColors.incomeGreen);

            final savingsRate = totals.income > 0 ? totals.total / totals.income * 100 : null;
            final avgDaily = daysElapsed > 0 ? spent / daysElapsed : null;

            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // ---- Summary cards ----
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TwoUp(
                    left: StatCard(label: 'Income', value: fmtMoney(totals.income), color: AppColors.incomeGreen, icon: Icons.arrow_downward_rounded),
                    right: StatCard(label: 'Expenses', value: fmtMoney(spent), color: AppColors.expense, icon: Icons.arrow_upward_rounded),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: StatCard(
                    label: 'Total (Income - Expenses)',
                    value: fmtMoney(totals.total),
                    color: totals.total >= 0 ? AppColors.incomeGreen : AppColors.expense,
                    icon: Icons.account_balance_wallet_outlined,
                    subtitle: savingsRate == null ? null : '${savingsRate.round()}% of income saved',
                  ),
                ),

                // ---- Budget ----
                SectionTitle(
                  'Budget',
                  trailing: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _showBudgetDialog(context, db, focused, budget),
                    icon: Icon(budget > 0 ? Icons.edit_outlined : Icons.add, size: 16),
                    label: Text(budget > 0 ? 'Edit budget' : 'Set budget'),
                  ),
                ),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: budget <= 0
                      ? const EmptyState(icon: Icons.flag_outlined, message: 'Set a monthly budget to track how much you can still spend')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(fmtMoney(spent), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: barColor)),
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text('of ${fmtMoney(budget)}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                ),
                                const Spacer(),
                                Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: barColor)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: (pct / 100).clamp(0.0, 1.0),
                                minHeight: 14,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation(barColor),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              remaining >= 0 ? '${fmtMoney(remaining)} left to spend' : 'Over budget by ${fmtMoney(-remaining)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: remaining >= 0 ? Colors.white : AppColors.expense),
                            ),
                            if (isCurrent && remaining > 0 && daysLeft > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'About ${fmtMoney(remaining / daysLeft)} a day for the next $daysLeft day${daysLeft == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                ),

                // ---- This month breakdown ----
                const SectionTitle('This month'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      _kv('Income', fmtMoney(totals.income, decimals: true), AppColors.incomeGreen),
                      _kv('Expenses', fmtMoney(spent, decimals: true), AppColors.expense),
                      _kv('Net savings', fmtMoney(totals.total, decimals: true), totals.total >= 0 ? AppColors.incomeGreen : AppColors.expense),
                      _kv('Savings rate', savingsRate == null ? '—' : '${savingsRate.toStringAsFixed(0)}%', null),
                      _kv('Avg. daily spend', avgDaily == null ? '—' : fmtMoney(avgDaily), null, last: true),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _kv(String k, String v, Color? valueColor, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Colors.white10))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: valueColor)),
          ],
        ),
      );

  Future<void> _showBudgetDialog(BuildContext context, AppDatabase db, DateTime focused, double current) async {
    final ctrl = TextEditingController(text: current > 0 ? current.toStringAsFixed(0) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Monthly Budget'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '$kCurrencySymbol '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text) ?? 0), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;

    final existing = await (db.select(db.budgets)..where((b) => b.year.equals(focused.year) & b.month.equals(focused.month))).getSingleOrNull();
    if (existing != null) {
      await (db.update(db.budgets)..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(amount: drift.Value(result), updatedAt: drift.Value(DateTime.now()), pendingSync: const drift.Value(true)),
      );
    } else {
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            id: _uuid.v4(),
            year: focused.year,
            month: focused.month,
            amount: drift.Value(result),
            updatedAt: DateTime.now(),
            pendingSync: const drift.Value(true),
          ));
    }
  }
}
