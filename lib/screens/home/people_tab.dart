import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/people_repository.dart';

class PeopleTab extends ConsumerStatefulWidget {
  const PeopleTab({super.key});

  @override
  ConsumerState<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<PeopleTab> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(focusedMonthProvider);
    final repo = ref.watch(peopleRepoProvider);

    return StreamBuilder<List<PeopleEntry>>(
      stream: repo.watchEntriesForMonth(focused.year, focused.month),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final entries = snapshot.data!..sort((a, b) => b.entryDate.compareTo(a.entryDate));
        final unsettled = entries.where((e) => !e.settled).toList();
        final settled = entries.where((e) => e.settled).toList();

        final borrowedOutstanding = unsettled.where((e) => e.type == 'borrowed').fold(0.0, (a, b) => a + b.amount);
        final lentOutstanding = unsettled.where((e) => e.type == 'lent').fold(0.0, (a, b) => a + b.amount);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Borrowed (outstanding)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('+$kCurrencySymbol${borrowedOutstanding.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.bold)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Lent (outstanding)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('-$kCurrencySymbol${lentOutstanding.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Lent money already counts as an expense from the day you gave it. '
                'Settling adds Borrowed back into expense, and removes Lent from it.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            if (unsettled.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectMode = !_selectMode),
                      child: Text(_selectMode ? 'Cancel' : 'Select to settle'),
                    ),
                    if (_selectMode && _selected.isNotEmpty)
                      FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: Text('Settle (${_selected.length})'),
                        onPressed: () async {
                          final toSettle = entries.where((e) => _selected.contains(e.id)).toList();
                          await repo.settleEntries(toSettle);
                          setState(() {
                            _selected.clear();
                            _selectMode = false;
                          });
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No borrowed/lent entries this month', style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: [
                        ...unsettled.map((e) => _entryTile(e, repo)),
                        if (settled.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text('Settled', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                          ),
                          ...settled.map((e) => _entryTile(e, repo)),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _entryTile(PeopleEntry e, PeopleRepository repo) {
    final isSelected = _selected.contains(e.id);
    final sign = e.type == 'borrowed' ? '+' : '-';
    final content = ListTile(
      leading: _selectMode && !e.settled
          ? Checkbox(
              value: isSelected,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(e.id);
                } else {
                  _selected.remove(e.id);
                }
              }),
            )
          : Icon(e.type == 'borrowed' ? Icons.arrow_downward : Icons.arrow_upward, color: AppColors.borrowedLent),
      title: Text(e.personName.isEmpty ? (e.type == 'borrowed' ? 'Borrowed' : 'Lent') : e.personName),
      subtitle: Text('${DateFormat('d MMM').format(e.entryDate)}${e.remark.isEmpty ? '' : ' · ${e.remark}'}'),
      trailing: Text('$sign$kCurrencySymbol${e.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.bold)),
      onTap: _selectMode && !e.settled
          ? () => setState(() {
                if (isSelected) {
                  _selected.remove(e.id);
                } else {
                  _selected.add(e.id);
                }
              })
          : null,
      onLongPress: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete this entry?'),
            content: const Text('This reverses any balance/expense effect it had.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (confirm == true) {
          await repo.deleteEntry(e);
        }
      },
    );

    if (!e.settled) return content;

    // Faded but still visible, per spec.
    return Opacity(opacity: 0.4, child: content);
  }
}
