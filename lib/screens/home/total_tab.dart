import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/home_totals_repository.dart';

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

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Income', totals.income, AppColors.incomeGreen),
                    _stat('Expenses', totals.expense, AppColors.expense),
                    _stat('Total', totals.total, Colors.white),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Budget', style: TextStyle(fontWeight: FontWeight.bold)),
                    OutlinedButton(
                      onPressed: () => _showBudgetDialog(context, ref, db, focused, budgetAmount),
                      child: const Text('Budget Setting'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Total Budget: $kCurrencySymbol${budgetAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0, 1).toDouble(),
                    minHeight: 24,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(pct > 100 ? AppColors.expense : AppColors.accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  budgetAmount > 0
                      ? '${pct.toStringAsFixed(0)}% used — Excess $kCurrencySymbol${(totals.expense - budgetAmount).toStringAsFixed(2)}'
                      : 'Set a budget to track progress',
                  style: TextStyle(color: pct > 100 ? AppColors.expense : Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _kv('Expenses this month', '$kCurrencySymbol${totals.expense.toStringAsFixed(2)}'),
                _kv('Income this month', '$kCurrencySymbol${totals.income.toStringAsFixed(2)}'),
              ],
            );
          },
        );
      },
    );
  }

  Widget _stat(String label, double value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value.toStringAsFixed(2), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: const TextStyle(color: Colors.grey)), Text(v)]),
      );

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
