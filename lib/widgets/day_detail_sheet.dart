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

/// One row in the merged day timeline — either a real Transaction or a
/// People (borrowed/lent) entry, normalised just enough to render and sort
/// them together.
class _DayItem {
  final String id;
  final bool isPeople;
  final String label; // category name, remark, or person name
  final String? categoryIcon;
  final double amount;
  final bool isIncomeColored; // income transactions AND lent-settled read as green-ish; kept simple below
  final Color color;
  final String? sign; // '+' / '-' for people entries
  final bool isYearly;
  final Transaction? txn;
  final PeopleEntry? people;

  _DayItem.fromTxn(Transaction t, String label, String? icon)
      : id = t.id,
        isPeople = false,
        label = label,
        categoryIcon = icon,
        amount = t.amount,
        isIncomeColored = t.type == 'income',
        color = t.type == 'income' ? AppColors.incomeGreen : AppColors.expense,
        sign = null,
        isYearly = t.isYearly,
        txn = t,
        people = null;

  _DayItem.fromPeople(PeopleEntry p)
      : id = p.id,
        isPeople = true,
        label = p.personName.isEmpty ? (p.type == 'borrowed' ? 'Borrowed' : 'Lent') : p.personName,
        categoryIcon = null,
        amount = p.amount,
        isIncomeColored = false,
        color = AppColors.borrowedLent,
        sign = p.type == 'borrowed' ? '+' : '-',
        isYearly = false,
        txn = null,
        people = p;
}

class DayDetailSheet extends ConsumerWidget {
  final DateTime day;
  const DayDetailSheet({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnRepo = ref.watch(transactionRepoProvider);
    final db = ref.watch(appDatabaseProvider);
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<Transaction>>(
          stream: txnRepo.watchDay(day),
          builder: (context, txnSnap) {
            return StreamBuilder<List<Category>>(
              stream: db.watchAllCategories(),
              builder: (context, catSnap) {
                return StreamBuilder<List<PeopleEntry>>(
                  stream: db.watchPeopleEntriesByEntryDate(dayStart, dayEnd),
                  builder: (context, peopleSnap) {
                    final txns = txnSnap.data ?? [];
                    final categories = {for (final c in catSnap.data ?? <Category>[]) c.id: c};
                    final people = peopleSnap.data ?? [];

                    final income = txns.where((t) => t.type == 'income').fold(0.0, (a, b) => a + b.amount);
                    final expense = txns.where((t) => t.type == 'expense').fold(0.0, (a, b) => a + b.amount);
                    final borrowed = people.where((p) => p.type == 'borrowed').fold(0.0, (a, b) => a + b.amount);
                    final lent = people.where((p) => p.type == 'lent').fold(0.0, (a, b) => a + b.amount);

                    final items = <_DayItem>[
                      for (final t in txns) _DayItem.fromTxn(t, t.remark.isEmpty ? (categories[t.categoryId]?.name ?? (t.type == 'income' ? 'Income' : 'Expense')) : t.remark, categories[t.categoryId]?.icon),
                      for (final p in people) _DayItem.fromPeople(p),
                    ];

                    return Column(
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(DateFormat('EEEE, d MMMM yyyy').format(day), style: Theme.of(context).textTheme.titleMedium),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              if (income > 0) _summaryPill('Income', income, AppColors.incomeGreen),
                              if (expense > 0) _summaryPill('Expense', expense, AppColors.expense),
                              if (borrowed > 0) _summaryPill('Borrowed', borrowed, AppColors.borrowedLent, sign: '+'),
                              if (lent > 0) _summaryPill('Lent', lent, AppColors.borrowedLent, sign: '-'),
                            ],
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 8), child: Divider(height: 1)),
                        Expanded(
                          child: items.isEmpty
                              ? const Center(child: Text('No entries for this day', style: TextStyle(color: Colors.grey)))
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                                  itemBuilder: (context, i) => _itemTile(context, ref, items[i]),
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
          },
        );
      },
    );
  }

  Widget _summaryPill(String label, double amount, Color color, {String? sign}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(
          '$label ${sign ?? ''}$kCurrencySymbol${amount.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _itemTile(BuildContext context, WidgetRef ref, _DayItem item) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: item.color.withOpacity(0.15),
        child: item.isPeople
            ? Icon(item.sign == '+' ? Icons.call_received : Icons.call_made, color: item.color, size: 18)
            : Text(item.categoryIcon ?? (item.isIncomeColored ? '➕' : '💸'), style: const TextStyle(fontSize: 16)),
      ),
      title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.isYearly
          ? const Text('Yearly expense', style: TextStyle(fontSize: 11, color: Colors.amber))
          : item.isPeople
              ? Text(item.people!.settled ? 'Settled' : 'Outstanding', style: TextStyle(fontSize: 11, color: item.people!.settled ? Colors.grey : AppColors.borrowedLent))
              : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.isPeople ? item.sign : (item.isIncomeColored ? '+' : '-')}$kCurrencySymbol${item.amount.toStringAsFixed(2)}',
            style: TextStyle(color: item.color, fontWeight: FontWeight.bold),
          ),
          if (!item.isPeople) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: 'Edit',
              onPressed: () => showEditTransactionModal(context, ref, item.txn!),
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
                  await ref.read(transactionRepoProvider).deleteTransaction(item.txn!.id);
                }
              },
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              tooltip: 'Open People tab to manage',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Manage borrowed/lent entries from the People tab')),
                );
              },
            ),
        ],
      ),
      onTap: item.isPeople ? null : () => showEditTransactionModal(context, ref, item.txn!),
    );
  }
}
