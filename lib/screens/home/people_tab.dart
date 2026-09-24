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
        final allUnsettledIds = unsettled.map((e) => e.id).toSet();
        final allSelected = unsettled.isNotEmpty && allUnsettledIds.every(_selected.contains);

        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            // ---- Borrowed / Lent summary cards ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _PeopleCard(
                      label: 'Borrowed (outstanding)',
                      value: borrowedOutstanding,
                      sign: '+',
                      icon: Icons.call_received,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PeopleCard(
                      label: 'Lent (outstanding)',
                      value: lentOutstanding,
                      sign: '-',
                      icon: Icons.call_made,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Lent money already counts as an expense from the day you gave it. '
                'Settling adds Borrowed back into expense, and removes Lent from it.',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
              ),
            ),

            // ---- Yet to settle ----
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Yet to settle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  if (unsettled.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: allSelected,
                            onChanged: (v) => setState(() {
                              _selectMode = true;
                              if (v == true) {
                                _selected.addAll(allUnsettledIds);
                              } else {
                                _selected.removeAll(allUnsettledIds);
                              }
                            }),
                          ),
                          const Text('Select all', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                          const Spacer(),
                          if (_selected.isNotEmpty) ...[
                            FilledButton.icon(
                              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                              icon: const Icon(Icons.check, size: 16),
                              label: Text('Settle (${_selected.length})', style: const TextStyle(fontSize: 12.5)),
                              onPressed: () async {
                                final toSettle = entries.where((e) => _selected.contains(e.id)).toList();
                                await repo.settleEntries(toSettle);
                                setState(() {
                                  _selected.clear();
                                  _selectMode = false;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                _selected.clear();
                                _selectMode = false;
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (unsettled.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Nothing outstanding this month 🎉', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  for (int i = 0; i < unsettled.length; i++) ...[
                    _entryTile(unsettled[i], repo, selectable: true),
                    if (i < unsettled.length - 1) const Divider(height: 1, indent: 56, endIndent: 16),
                  ],
                ],
              ),
            ),

            // ---- Settled ----
            if (settled.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                child: Text('Settled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < settled.length; i++) ...[
                      _entryTile(settled[i], repo, selectable: false),
                      if (i < settled.length - 1) const Divider(height: 1, indent: 56, endIndent: 16),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _entryTile(PeopleEntry e, PeopleRepository repo, {required bool selectable}) {
    final isSelected = _selected.contains(e.id);
    final sign = e.type == 'borrowed' ? '+' : '-';
    final content = ListTile(
      dense: true,
      leading: selectable
          ? Checkbox(
              value: isSelected,
              onChanged: (v) => setState(() {
                _selectMode = true;
                if (v == true) {
                  _selected.add(e.id);
                } else {
                  _selected.remove(e.id);
                }
              }),
            )
          : CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.borrowedLent.withOpacity(0.12),
              child: Icon(e.type == 'borrowed' ? Icons.call_received : Icons.call_made, color: AppColors.borrowedLent, size: 16),
            ),
      title: Text(
        e.remark.isEmpty ? (e.personName.isEmpty ? (e.type == 'borrowed' ? 'Borrowed' : 'Lent') : e.personName) : e.remark,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${e.personName.isNotEmpty && e.remark.isNotEmpty ? '${e.personName} · ' : ''}${DateFormat('d MMM').format(e.entryDate)}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Text('$sign$kCurrencySymbol${e.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.borrowedLent, fontWeight: FontWeight.bold)),
      onTap: selectable
          ? () => setState(() {
                _selectMode = true;
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

    if (selectable) return content;
    // Faded but still visible, per spec.
    return Opacity(opacity: 0.45, child: content);
  }
}

class _PeopleCard extends StatelessWidget {
  final String label;
  final double value;
  final String sign;
  final IconData icon;
  const _PeopleCard({required this.label, required this.value, required this.sign, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.borrowedLent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borrowedLent.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.borrowedLent),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$sign$kCurrencySymbol${value.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.borrowedLent),
          ),
        ],
      ),
    );
  }
}
