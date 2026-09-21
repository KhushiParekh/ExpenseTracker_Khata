import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../data/local/app_database.dart';
import '../providers/app_providers.dart';
import 'add_transaction_modal.dart';

Future<void> showDayDetailSheet(BuildContext context, WidgetRef ref, DateTime day) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DayDetailSheet(day: day),
  );
}

class DayDetailSheet extends ConsumerWidget {
  final DateTime day;
  const DayDetailSheet({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnRepo = ref.watch(transactionRepoProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<Transaction>>(
          stream: txnRepo.watchDay(day),
          builder: (context, snapshot) {
            final txns = snapshot.data ?? [];
            final income = txns.where((t) => t.type == 'income').fold(0.0, (a, b) => a + b.amount);
            final expense = txns.where((t) => t.type == 'expense').fold(0.0, (a, b) => a + b.amount);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(DateFormat('d MMM yyyy, EEE').format(day), style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text('$kCurrencySymbol${income.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.incomeGreen)),
                      const SizedBox(width: 8),
                      Text('$kCurrencySymbol${expense.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.expense)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: txns.isEmpty
                      ? const Center(child: Text('No entries for this day', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: txns.length,
                          itemBuilder: (context, i) {
                            final t = txns[i];
                            final color = t.type == 'income' ? AppColors.incomeGreen : AppColors.expense;
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(t.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward, color: color, size: 18)),
                              title: Text(t.remark.isEmpty ? (t.type == 'income' ? 'Income' : 'Expense') : t.remark),
                              subtitle: t.isYearly ? const Text('Yearly expense', style: TextStyle(fontSize: 11, color: Colors.amber)) : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$kCurrencySymbol${t.amount.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    tooltip: 'Edit',
                                    onPressed: () => showEditTransactionModal(context, ref, t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                    tooltip: 'Delete',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Delete entry?'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await ref.read(transactionRepoProvider).deleteTransaction(t.id);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => showEditTransactionModal(context, ref, t),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showAddTransactionModal(context, ref, day);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add entry for this day'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
