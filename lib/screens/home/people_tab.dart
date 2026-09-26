import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/people_repository.dart';
import '../../widgets/ui_kit.dart';

class PeopleTab extends ConsumerStatefulWidget {
  const PeopleTab({super.key});

  @override
  ConsumerState<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<PeopleTab> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(focusedMonthProvider);
    final repo = ref.watch(peopleRepoProvider);

    return StreamBuilder<List<PeopleEntry>>(
      stream: repo.watchEntriesForMonth(focused.year, focused.month),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final entries = List<PeopleEntry>.from(snapshot.data!)..sort((a, b) => b.entryDate.compareTo(a.entryDate));
        final unsettled = entries.where((e) => !e.settled).toList();
        final settled = entries.where((e) => e.settled).toList();

        final borrowedOutstanding = unsettled.where((e) => e.type == 'borrowed').fold(0.0, (a, b) => a + b.amount);
        final lentOutstanding = unsettled.where((e) => e.type == 'lent').fold(0.0, (a, b) => a + b.amount);

        // Drop selections that no longer exist (deleted / settled / month changed).
        final unsettledIds = unsettled.map((e) => e.id).toSet();
        final selected = _selected.where(unsettledIds.contains).toSet();
        final allSelected = unsettled.isNotEmpty && selected.length == unsettled.length;

        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // ---- Borrowed / Lent cards ----
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TwoUp(
                left: StatCard(
                  label: 'Borrowed',
                  value: '+$kCurrencySymbol${_n(borrowedOutstanding)}',
                  color: AppColors.borrowedLent,
                  icon: Icons.arrow_downward_rounded,
                  subtitle: 'Outstanding',
                ),
                right: StatCard(
                  label: 'Lent',
                  value: '-$kCurrencySymbol${_n(lentOutstanding)}',
                  color: AppColors.borrowedLent,
                  icon: Icons.arrow_upward_rounded,
                  subtitle: 'Outstanding',
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Text(
                'Lent money already counts as an expense from the day you gave it. '
                'Settling adds Borrowed back into expense, and removes Lent from it.',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
              ),
            ),

            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(icon: Icons.people_outline, message: 'No borrowed / lent entries this month'),
              )
            else ...[
              // ---- Yet to settle ----
              SectionTitle('Yet to settle', trailing: Text('${unsettled.length}', style: const TextStyle(color: Colors.grey, fontSize: 12))),
              AppCard(
                padding: EdgeInsets.zero,
                child: unsettled.isEmpty
                    ? const EmptyState(icon: Icons.check_circle_outline, message: 'All settled for this month')
                    : Column(
                        children: [
                          // Select-all + settle action bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                            child: Row(
                              children: [
                                Checkbox(
                                  tristate: true,
                                  value: allSelected ? true : (selected.isEmpty ? false : null),
                                  onChanged: (_) => setState(() {
                                    if (allSelected) {
                                      _selected.clear();
                                    } else {
                                      _selected
                                        ..clear()
                                        ..addAll(unsettledIds);
                                    }
                                  }),
                                ),
                                Text(selected.isEmpty ? 'Select all' : '${selected.length} selected', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                const Spacer(),
                                if (selected.isNotEmpty) ...[
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: AppColors.borrowedLent,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.check, size: 17),
                                    label: Text('Settle (${selected.length})'),
                                    onPressed: () async {
                                      final toSettle = unsettled.where((e) => selected.contains(e.id)).toList();
                                      await repo.settleEntries(toSettle);
                                      if (mounted) setState(_selected.clear);
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Clear selection',
                                    icon: const Icon(Icons.close, size: 20),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(_selected.clear),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          for (int i = 0; i < unsettled.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 56),
                            _unsettledRow(unsettled[i], selected.contains(unsettled[i].id), repo),
                          ],
                        ],
                      ),
              ),

              // ---- Settled ----
              if (settled.isNotEmpty) ...[
                SectionTitle('Settled', trailing: Text('${settled.length}', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (int i = 0; i < settled.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        _settledRow(settled[i], repo),
                      ],
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Long-press an entry to delete it', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ],
          ],
        );
      },
    );
  }

  String _n(double v) => fmtMoney(v, decimals: v % 1 != 0).replaceFirst(kCurrencySymbol, '');

  String _title(PeopleEntry e) => e.remark.trim().isNotEmpty ? e.remark.trim() : (e.type == 'borrowed' ? 'Borrowed' : 'Lent');

  String _subtitle(PeopleEntry e, {bool showSettleDate = false}) {
    final parts = <String>[
      if (e.personName.trim().isNotEmpty) e.personName.trim(),
      DateFormat('d MMM').format(e.entryDate),
      if (showSettleDate && e.settledAt != null) 'settled ${DateFormat('d MMM').format(e.settledAt!)}',
    ];
    return parts.join(' · ');
  }

  String _amount(PeopleEntry e) => '${e.type == 'borrowed' ? '+' : '-'}${fmtMoney(e.amount, decimals: e.amount % 1 != 0)}';

  Widget _unsettledRow(PeopleEntry e, bool isSelected, PeopleRepository repo) {
    void toggle() => setState(() {
          if (isSelected) {
            _selected.remove(e.id);
          } else {
            _selected.add(e.id);
          }
        });

    return InkWell(
      onTap: toggle,
      onLongPress: () => _confirmDelete(e, repo),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        child: Row(
          children: [
            Checkbox(value: isSelected, onChanged: (_) => toggle()),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_subtitle(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_amount(e), style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.w800, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }

  Widget _settledRow(PeopleEntry e, PeopleRepository repo) {
    return InkWell(
      onLongPress: () => _confirmDelete(e, repo),
      child: Opacity(
        opacity: 0.55,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 22, color: AppColors.borrowedLent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, decoration: TextDecoration.lineThrough),
                    ),
                    const SizedBox(height: 2),
                    Text(_subtitle(e, showSettleDate: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_amount(e), style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.w800, fontSize: 14.5)),
              IconButton(
                tooltip: 'Mark as unsettled',
                icon: const Icon(Icons.undo, size: 19),
                visualDensity: VisualDensity.compact,
                onPressed: () => repo.unsettleEntry(e),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PeopleEntry e, PeopleRepository repo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This reverses any balance/expense effect it had.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) await repo.deleteEntry(e);
  }
}
