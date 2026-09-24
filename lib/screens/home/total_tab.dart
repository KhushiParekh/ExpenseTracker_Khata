import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/home_totals_repository.dart';
import '../../widgets/stat_charts.dart';

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
            final budgetAmount = budgetSnap.data?.amount ?? 0;
            final pct = budgetAmount > 0 ? (totals.expense / budgetAmount * 100) : 0.0;
            final overBudget = pct > 100;

            return ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 90),
              children: [
                // ---- Summary cards ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    children: [
                      _StatCard(label: 'Income', value: totals.income, color: AppColors.incomeGreen, icon: Icons.arrow_downward_rounded),
                      _StatCard(label: 'Expenses', value: totals.expense, color: AppColors.expense, icon: Icons.arrow_upward_rounded),
                      _StatCard(
                        label: 'Net Total',
                        value: totals.total,
                        color: totals.total >= 0 ? AppColors.incomeGreen : AppColors.expense,
                        icon: Icons.account_balance_wallet_outlined,
                        showSign: true,
                      ),
                      _StatCard(
                        label: 'Budget used',
                        value: pct,
                        isPercent: true,
                        color: overBudget ? AppColors.expense : AppColors.accent,
                        icon: Icons.pie_chart_outline,
                      ),
                    ],
                  ),
                ),

                // ---- Budget card ----
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Monthly Budget', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          OutlinedButton.icon(
                            onPressed: () => _showBudgetDialog(context, ref, db, focused, budgetAmount),
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        budgetAmount > 0 ? '$kCurrencySymbol${totals.expense.toStringAsFixed(0)} of $kCurrencySymbol${budgetAmount.toStringAsFixed(0)}' : 'No budget set for this month',
                        style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: budgetAmount > 0 ? (pct / 100).clamp(0, 1).toDouble() : 0,
                          minHeight: 14,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(overBudget ? AppColors.expense : AppColors.accent),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        budgetAmount > 0
                            ? (overBudget
                                ? '${pct.toStringAsFixed(0)}% used — over by $kCurrencySymbol${(totals.expense - budgetAmount).toStringAsFixed(0)}'
                                : '${pct.toStringAsFixed(0)}% used — $kCurrencySymbol${(budgetAmount - totals.expense).toStringAsFixed(0)} left')
                            : 'Tap Edit to set a budget and track progress',
                        style: TextStyle(color: overBudget ? AppColors.expense : Colors.grey, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),

                // ---- Category breakdown for the month ----
                Consumer(builder: (context, ref, _) {
                  final txnRepo = ref.watch(transactionRepoProvider);
                  final categoriesAsync = ref.watch(allCategoriesProvider);
                  return categoriesAsync.when(
                    data: (categories) => StreamBuilder(
                      stream: txnRepo.watchHomeTransactionsBetween(
                        DateTime(focused.year, focused.month, 1),
                        DateTime(focused.year, focused.month + 1, 1).subtract(const Duration(milliseconds: 1)),
                      ),
                      builder: (context, rowsSnap) {
                        if (!rowsSnap.hasData) {
                          return const ChartCard(title: 'Where it went', height: 170, child: Center(child: CircularProgressIndicator()));
                        }
                        final rows = rowsSnap.data as List<Transaction>;
                        final slices = txnRepo.categoryBreakdown(rows, categories, kind: 'expense');
                        return ChartCard(
                          title: 'Where it went',
                          subtitle: DateFormat('MMMM yyyy').format(focused),
                          height: 170,
                          child: CompactCategoryDonut(slices: slices),
                        );
                      },
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => const SizedBox.shrink(),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showBudgetDialog(BuildContext context, WidgetRef ref, AppDatabase db, DateTime focused, double current) async {
    final ctrl = TextEditingController(text: current > 0 ? current.toStringAsFixed(0) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Monthly Budget'),
        content: TextField(
          controller: ctrl,
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

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool showSign;
  final bool isPercent;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.showSign = false,
    this.isPercent = false,
  });

  @override
  Widget build(BuildContext context) {
    final sign = showSign && value != 0 ? (value > 0 ? '+' : '-') : '';
    final text = isPercent ? '${value.toStringAsFixed(0)}%' : '$sign$kCurrencySymbol${compactAmount(value.abs())}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
