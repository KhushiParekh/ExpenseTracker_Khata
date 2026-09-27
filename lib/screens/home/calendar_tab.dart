import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/day_detail_sheet.dart';
import '../../widgets/stat_charts.dart' show compactAmount;
import '../../widgets/ui_kit.dart';
import '../../data/repositories/home_totals_repository.dart';
import '../../data/local/app_database.dart';

class CalendarTab extends ConsumerWidget {
  const CalendarTab({super.key});

  static const _sundayRed = Color(0xFFFF5A6E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final selected = ref.watch(selectedDateProvider);
    final totalsRepo = ref.watch(homeTotalsRepoProvider);
    final peopleRepo = ref.watch(peopleRepoProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      children: [
        // ---- 1. Four summary cards: Income, Expense, Net savings, People ----
        StreamBuilder<PeriodTotals>(
          stream: totalsRepo.watchTotalsForMonth(focused.year, focused.month),
          builder: (context, totalsSnap) {
            final t = totalsSnap.data ?? PeriodTotals.zero;
            return StreamBuilder<List<PeopleEntry>>(
              stream: peopleRepo.watchEntriesForMonth(focused.year, focused.month),
              builder: (context, peopleSnap) {
                final entries = peopleSnap.data ?? const <PeopleEntry>[];
                final borrowedOut = entries.where((e) => e.type == 'borrowed' && !e.settled).fold(0.0, (a, b) => a + b.amount);
                final lentOut = entries.where((e) => e.type == 'lent' && !e.settled).fold(0.0, (a, b) => a + b.amount);
                final net = t.total;
                final rate = t.income > 0 ? '${(net / t.income * 100).round()}% of income' : 'Income - Expense';

                return Column(
                  children: [
                    TwoUp(
                      left: StatCard(
                        label: 'Income',
                        value: fmtMoney(t.income),
                        color: AppColors.incomeGreen,
                        icon: Icons.arrow_downward_rounded,
                      ),
                      right: StatCard(
                        label: 'Expense',
                        value: fmtMoney(t.expense),
                        color: AppColors.expense,
                        icon: Icons.arrow_upward_rounded,
                      ),
                    ),
                    TwoUp(
                      left: StatCard(
                        label: 'Net savings',
                        value: fmtMoney(net),
                        color: net >= 0 ? AppColors.incomeGreen : AppColors.expense,
                        icon: Icons.savings_outlined,
                        subtitle: rate,
                      ),
                      right: StatCard(
                        label: 'Borrowed / Lent',
                        value: fmtSigned(borrowedOut - lentOut),
                        color: AppColors.borrowedLent,
                        icon: Icons.people_alt_outlined,
                        subtitle: 'In ${compactAmount(borrowedOut)} · Out ${compactAmount(lentOut)}',
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),

        const SizedBox(height: 6),

        // ---- 2. Calendar grid ----
        AppCard(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Column(
            children: [
              StreamBuilder<Map<int, PeriodTotals>>(
                stream: totalsRepo.watchDailyTotalsForMonth(focused.year, focused.month),
                builder: (context, dailySnap) {
                  return StreamBuilder<Map<int, double>>(
                    stream: totalsRepo.watchPendingPeopleNetForMonth(focused.year, focused.month),
                    builder: (context, pendingSnap) {
                      final dayTotals = dailySnap.data ?? {};
                      final pending = pendingSnap.data ?? {};
                      final now = DateTime.now();

                      return TableCalendar(
                        firstDay: DateTime(2015, 1, 1),
                        lastDay: DateTime(2100, 12, 31),
                        focusedDay: focused,
                        currentDay: now,
                        selectedDayPredicate: (d) => isSameDay(d, selected),
                        calendarFormat: CalendarFormat.month,
                        rowHeight: 74,
                        daysOfWeekHeight: 28,
                        headerVisible: false, // shared nav lives in HomeScreen's AppBar
                        sixWeekMonthsEnforced: false,
                        calendarStyle: const CalendarStyle(outsideDaysVisible: true),
                        onPageChanged: (focusedDay) {
                          ref.read(focusedMonthProvider.notifier).state = DateTime(focusedDay.year, focusedDay.month);
                        },
                        onDaySelected: (selectedDay, focusedDay) {
                          ref.read(selectedDateProvider.notifier).state = selectedDay;
                          showAddTransactionModal(context, ref, selectedDay);
                        },
                        calendarBuilders: CalendarBuilders(
                          dowBuilder: (context, day) {
                            final isSunday = day.weekday == DateTime.sunday;
                            return Center(
                              child: Text(
                                const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1],
                                style: TextStyle(
                                  color: isSunday ? _sundayRed : Colors.grey.shade400,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                          defaultBuilder: (context, day, _) =>
                              _dayCell(context, ref, day, dayTotals[day.day], pending[day.day] ?? 0),
                          todayBuilder: (context, day, _) =>
                              _dayCell(context, ref, day, dayTotals[day.day], pending[day.day] ?? 0, isToday: true),
                          // A selected day that is ALSO today keeps its "today" ring.
                          selectedBuilder: (context, day, _) => _dayCell(
                            context, ref, day, dayTotals[day.day], pending[day.day] ?? 0,
                            isSelected: true,
                            isToday: isSameDay(day, now),
                          ),
                          outsideBuilder: (context, day, _) => _dayCell(context, ref, day, null, 0, isOutside: true),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(color: AppColors.incomeGreen, label: 'Income'),
                  SizedBox(width: 14),
                  _LegendDot(color: AppColors.expense, label: 'Expense'),
                  SizedBox(width: 14),
                  _LegendDot(color: AppColors.borrowedLent, label: 'People'),
                ],
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Tap a date to add  ·  Long-press to see its entries',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    PeriodTotals? totals,
    double pending, {
    bool isToday = false,
    bool isSelected = false,
    bool isOutside = false,
  }) {
    final isSunday = day.weekday == DateTime.sunday;
    final hasIncome = totals != null && totals.income != 0;
    // A day whose only activity is a lent entry settling back nets to a
    // negative expense — that's a reversal, not a real expense on this
    // day, so it's deliberately not shown (matches "once settled, gone").
    final hasExpense = totals != null && totals.expense != 0;

    Color numberColor;
    if (isOutside) {
      numberColor = Colors.grey.shade700;
    } else if (isSunday) {
      numberColor = _sundayRed;
    } else {
      numberColor = Colors.white;
    }

    Color? bg;
    BoxBorder? border;
    if (isOutside) {
      bg = null;
    } else if (isToday) {
      bg = AppColors.accent.withOpacity(isSelected ? 0.22 : 0.13);
      border = Border.all(color: AppColors.accent, width: 1.5);
    } else if (isSelected) {
      bg = Colors.white.withOpacity(0.10);
      border = Border.all(color: Colors.white38);
    } else {
      bg = Colors.white.withOpacity(0.03);
    }

    Widget amountLine(String text, Color color) => Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700, height: 1.15),
          ),
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: isOutside ? null : () => showDayDetailSheet(context, ref, day),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.fromLTRB(4, 3, 2, 2),
        alignment: Alignment.topLeft,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9), border: border),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: isToday ? const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent) : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isToday ? Colors.white : numberColor,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (hasIncome) amountLine(compactAmount(totals.income), AppColors.incomeGreen),
              if (hasExpense) amountLine('-${compactAmount(totals.expense)}', AppColors.expense),
              if (pending != 0) amountLine(pending > 0 ? '+${compactAmount(pending)}' : compactAmount(pending), AppColors.borrowedLent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
      ],
    );
  }
}
