import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/day_detail_sheet.dart';
import '../../data/repositories/home_totals_repository.dart';
import '../../data/local/app_database.dart';

class CalendarTab extends ConsumerWidget {
  const CalendarTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final selected = ref.watch(selectedDateProvider);
    final totalsRepo = ref.watch(homeTotalsRepoProvider);
    final peopleRepo = ref.watch(peopleRepoProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Income & Expense summary bar moved to the TOP
        StreamBuilder<PeriodTotals>(
          stream: totalsRepo.watchTotalsForMonth(focused.year, focused.month),
          builder: (context, snap) {
            final t = snap.data ?? PeriodTotals.zero;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('Income', t.income, AppColors.incomeGreen),
                  _statChip('Expense', t.expense, AppColors.expense),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),

        // 2. Main Calendar Grid
        StreamBuilder<Map<int, PeriodTotals>>(
          stream: totalsRepo.watchDailyTotalsForMonth(focused.year, focused.month),
          builder: (context, dailySnap) {
            return StreamBuilder<Map<int, double>>(
              stream: totalsRepo.watchPendingPeopleNetForMonth(focused.year, focused.month),
              builder: (context, pendingSnap) {
                final dayTotals = dailySnap.data ?? {};
                final pending = pendingSnap.data ?? {};

                return TableCalendar(
                  firstDay: DateTime(2015, 1, 1),
                  lastDay: DateTime(2100, 12, 31),
                  focusedDay: focused,
                  currentDay: DateTime.now(),
                  selectedDayPredicate: (d) => isSameDay(d, selected),
                  calendarFormat: CalendarFormat.month,
                  rowHeight: 78,
                  daysOfWeekHeight: 28,
                  headerVisible: false, // shared nav lives in HomeScreen's AppBar
                  sixWeekMonthsEnforced: false,
                  calendarStyle: const CalendarStyle(outsideDaysVisible: true),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    dowTextFormatter: (date, locale) => const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][date.weekday % 7],
                    weekdayStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    weekendStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
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
                          style: TextStyle(color: isSunday ? const Color(0xFFFF5A6E) : Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      );
                    },
                    defaultBuilder: (context, day, focusedDay) => _dayCell(context, ref, day, dayTotals[day.day], pending[day.day] ?? 0),
                    todayBuilder: (context, day, focusedDay) => _dayCell(context, ref, day, dayTotals[day.day], pending[day.day] ?? 0, isToday: true),
                    selectedBuilder: (context, day, focusedDay) => _dayCell(context, ref, day, dayTotals[day.day], pending[day.day] ?? 0, isSelected: true),
                    outsideBuilder: (context, day, focusedDay) => _dayCell(context, ref, day, null, 0, isOutside: true),
                  ),
                );
              },
            );
          },
        ),
        const Divider(height: 1),

        // 3. Borrowed / Lent outstanding totals bar at the bottom
        StreamBuilder<List<PeopleEntry>>(
          stream: peopleRepo.watchEntriesForMonth(focused.year, focused.month),
          builder: (context, snap) {
            final entries = snap.data ?? [];
            final borrowedOut = entries.where((e) => e.type == 'borrowed' && !e.settled).fold(0.0, (a, b) => a + b.amount);
            final lentOut = entries.where((e) => e.type == 'lent' && !e.settled).fold(0.0, (a, b) => a + b.amount);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _pill('Borrowed', borrowedOut, '+'),
                  _pill('Lent', lentOut, '-'),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _pill(String label, double amount, String sign) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.borrowedLent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borrowedLent.withOpacity(0.4)),
      ),
      child: Text(
        '$label: $sign$kCurrencySymbol${amount.toStringAsFixed(0)}',
        style: const TextStyle(color: AppColors.borrowedLent, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _dayCell(BuildContext context, WidgetRef ref, DateTime day, PeriodTotals? totals, double pending, {bool isToday = false, bool isSelected = false, bool isOutside = false}) {
    final isSunday = day.weekday == DateTime.sunday;
    final hasIncome = totals != null && totals.income != 0;
    final hasExpense = totals != null && totals.expense != 0;

    Color dayNumberColor;
    if (isOutside) {
      dayNumberColor = Colors.grey.shade700;
    } else if (isSunday) {
      dayNumberColor = const Color(0xFFFF5A6E);
    } else {
      dayNumberColor = Colors.white;
    }

    return GestureDetector(
      onLongPress: isOutside ? null : () => showDayDetailSheet(context, ref, day),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12, width: 0.5),
          color: isSelected ? Colors.white10 : (isToday ? AppColors.accent.withOpacity(0.08) : null),
        ),
        padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: isToday ? const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent) : null,
                padding: isToday ? const EdgeInsets.all(3) : EdgeInsets.zero,
                child: Text(
                  '${day.day}',
                  style: TextStyle(fontSize: 12, color: isToday ? Colors.white : dayNumberColor, fontWeight: FontWeight.w600),
                ),
              ),
              if (hasIncome)
                Text(
                  totals.income.toStringAsFixed(0),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 10, color: AppColors.incomeGreen, fontWeight: FontWeight.w600),
                ),
              if (hasExpense)
                Text(
                  '-${totals.expense.toStringAsFixed(0)}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 10, color: AppColors.expense, fontWeight: FontWeight.w600),
                ),
              if (pending != 0)
                Text(
                  pending > 0 ? '+${pending.toStringAsFixed(0)}' : pending.toStringAsFixed(0),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 10, color: AppColors.borrowedLent, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, double value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text('$kCurrencySymbol${value.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}