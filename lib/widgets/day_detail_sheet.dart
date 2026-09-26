import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../data/local/app_database.dart';
import '../data/repositories/home_totals_repository.dart';
import '../providers/app_providers.dart';
import 'add_transaction_modal.dart';
import 'ui_kit.dart';

Future<void> showDayDetailSheet(BuildContext context, WidgetRef ref, DateTime day) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => DayDetailSheet(day: day),
  );
}

/// Everything that happened on one calendar day: normal income/expense
/// entries AND People (borrowed / lent) entries, the latter in blue.
class DayDetailSheet extends ConsumerWidget {
  final DateTime day;
  const DayDetailSheet({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnRepo = ref.watch(transactionRepoProvider);
    final db = ref.watch(appDatabaseProvider);
    final categories = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    final accounts = ref.watch(allAccountsProvider).valueOrNull ?? const <Account>[];
    final catsById = {for (final c in categories) c.id: c};
    final accsById = {for (final a in accounts) a.id: a};

    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    final isToday = DateUtils.isSameDay(day, DateTime.now());

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
            ),

            // ---- Header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('EEEE').format(day), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text(DateFormat('d MMMM yyyy').format(day), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (isToday) const MiniTag('TODAY', color: AppColors.accent),
                ],
              ),
            ),
            _DayTotalsRow(day: day),
            const SizedBox(height: 10),
            const Divider(height: 1),

            // ---- Entries ----
            Expanded(
              child: StreamBuilder<List<Transaction>>(
                stream: txnRepo.watchDay(day),
                builder: (context, txnSnap) {
                  return StreamBuilder<List<PeopleEntry>>(
                    stream: db.watchPeopleEntriesByEntryDate(start, end),
                    builder: (context, peopleSnap) {
                      final txns = txnSnap.data ?? const <Transaction>[];
                      final people = peopleSnap.data ?? const <PeopleEntry>[];

                      if (txns.isEmpty && people.isEmpty) {
                        return ListView(
                          controller: scrollController,
                          children: const [
                            SizedBox(height: 40),
                            EmptyState(icon: Icons.event_available_outlined, message: 'Nothing recorded on this day'),
                          ],
                        );
                      }

                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        children: [
                          if (txns.isNotEmpty) _label('Transactions', txns.length),
                          for (final t in txns)
                            _txnTile(
                              context, ref, t,
                              t.categoryId == null ? null : catsById[t.categoryId],
                              t.accountId == null ? null : accsById[t.accountId],
                            ),
                          if (people.isNotEmpty) _label('People', people.length),
                          for (final p in people) _peopleTile(context, ref, p, p.accountId == null ? null : accsById[p.accountId]),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            // ---- Add ----
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                    onPressed: () {
                      Navigator.pop(context);
                      showAddTransactionModal(context, ref, day);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add entry for this day', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(String text, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        child: Text(
          '${text.toUpperCase()}  ·  $count',
          style: const TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
      );

  // ---------------------------------------------------------------------
  // Normal transaction row
  // ---------------------------------------------------------------------
  Widget _txnTile(BuildContext context, WidgetRef ref, Transaction t, Category? cat, Account? acc) {
    final isIncome = t.type == 'income';
    final color = isIncome ? AppColors.incomeGreen : AppColors.expense;
    final hasRemark = t.remark.trim().isNotEmpty;
    final catName = cat?.name ?? 'Uncategorized';

    final title = hasRemark ? t.remark.trim() : catName;
    final subtitle = [if (hasRemark) catName, if (acc != null) acc.name].join('  ·  ');

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      onTap: () => showEditTransactionModal(context, ref, t),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
            child: Text(cat?.icon ?? (isIncome ? '💰' : '🧾'), style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ],
                if (t.isYearly) ...[
                  const SizedBox(height: 4),
                  const MiniTag('YEARLY', color: Colors.amber),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${isIncome ? '+' : '-'}${fmtMoney(t.amount, decimals: t.amount % 1 != 0)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconAction(Icons.edit_outlined, 'Edit', () => showEditTransactionModal(context, ref, t)),
                  _iconAction(Icons.delete_outline, 'Delete', () async {
                    final ok = await _confirm(context, 'Delete this entry?');
                    if (ok) await ref.read(transactionRepoProvider).deleteTransaction(t.id);
                  }),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // People (borrowed / lent) row — always blue
  // ---------------------------------------------------------------------
  Widget _peopleTile(BuildContext context, WidgetRef ref, PeopleEntry p, Account? acc) {
    const color = AppColors.borrowedLent;
    final borrowed = p.type == 'borrowed';
    final sign = borrowed ? '+' : '-';
    final typeLabel = borrowed ? 'Borrowed' : 'Lent';
    final title = p.personName.trim().isEmpty ? typeLabel : p.personName.trim();
    final subtitle = [
      if (p.personName.trim().isNotEmpty) typeLabel,
      if (p.remark.trim().isNotEmpty) p.remark.trim(),
      if (acc != null) acc.name,
    ].join('  ·  ');
    final peopleRepo = ref.read(peopleRepoProvider);

    return Opacity(
      opacity: p.settled ? 0.55 : 1,
      child: AppCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 2, 8),
        borderColor: color.withOpacity(0.35),
        color: color.withOpacity(0.07),
        onTap: () => showEditPeopleEntryModal(context, ref, p),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
              child: Icon(borrowed ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                  if (p.settled) ...[
                    const SizedBox(height: 4),
                    const MiniTag('SETTLED', color: color),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign${fmtMoney(p.amount, decimals: p.amount % 1 != 0)}',
              style: const TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
              onSelected: (v) async {
                if (v == 'edit') {
                  showEditPeopleEntryModal(context, ref, p);
                } else if (v == 'settle') {
                  await peopleRepo.settleEntries([p]);
                } else if (v == 'unsettle') {
                  await peopleRepo.unsettleEntry(p);
                } else if (v == 'delete') {
                  final ok = await _confirm(context, 'Delete this entry?', body: 'This reverses any balance/expense effect it had.');
                  if (ok) await peopleRepo.deleteEntry(p);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: p.settled ? 'unsettle' : 'settle', child: Text(p.settled ? 'Mark as unsettled' : 'Mark as settled')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 19, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String title, {String? body}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return res == true;
  }
}

/// Income / Expense / People for the day — same Income & Expense numbers
/// the calendar cell shows, with a People chip (net borrowed − lent,
/// blue) sitting beside Expense in place of a plain Net figure.
class _DayTotalsRow extends ConsumerWidget {
  final DateTime day;
  const _DayTotalsRow({required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(homeTotalsRepoProvider);
    final db = ref.watch(appDatabaseProvider);
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

    return StreamBuilder<PeriodTotals>(
      stream: repo.watchTotalsForDay(day),
      builder: (context, totalsSnap) {
        final t = totalsSnap.data ?? PeriodTotals.zero;

        return StreamBuilder<List<PeopleEntry>>(
          stream: db.watchPeopleEntriesByEntryDate(start, end),
          builder: (context, peopleSnap) {
            final people = peopleSnap.data ?? const <PeopleEntry>[];
            final peopleNet = people.fold(0.0, (sum, p) => sum + (p.type == 'borrowed' ? p.amount : -p.amount));

            Widget chip(String label, String value, Color color) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
                        ),
                      ],
                    ),
                  ),
                );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  chip('Income', fmtMoney(t.income), AppColors.incomeGreen),
                  const SizedBox(width: 8),
                  chip('Expense', fmtMoney(t.expense), AppColors.expense),
                  const SizedBox(width: 8),
                  chip('People', people.isEmpty ? '—' : fmtSigned(peopleNet), AppColors.borrowedLent),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
