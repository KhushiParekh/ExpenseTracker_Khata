import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/day_detail_sheet.dart';
import '../../data/repositories/home_totals_repository.dart';
import '../../data/local/app_database.dart';
import '../../widgets/stat_charts.dart';

class CalendarTab extends ConsumerWidget {
  const CalendarTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedMonthProvider);
    final selected = ref.watch(selectedDateProvider);
    final totalsRepo = ref.watch(homeTotalsRepoProvider);
    final peopleRepo = ref.watch(peopleRepoProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        // ---- 1. Income + Expense cards ----
StreamBuilder<PeriodTotals>(
  stream: totalsRepo.watchTotalsForMonth(
    focused.year,
    focused.month,
  ),
  builder: (context, totalsSnap) {
    final t = totalsSnap.data ?? PeriodTotals.zero;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'Income',
              value: t.income,
              color: AppColors.incomeGreen,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              label: 'Expense',
              value: t.expense,
              color: AppColors.expense,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  },
),

// ---- 2. Legend ----
Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
  child: Wrap(
    spacing: 16,
    runSpacing: 4,
    children: [
      _legendDot(AppColors.incomeGreen, 'Income'),
      _legendDot(AppColors.expense, 'Expense'),
      _legendDot(AppColors.borrowedLent, 'Borrowed / Lent'),
    ],
  ),
),

// ---- 3. Calendar grid ----
Container(
  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  decoration: BoxDecoration(
    color: AppColors.surface.withOpacity(0.5),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white10),
  ),
  padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
  child: StreamBuilder<Map<int, PeriodTotals>>(
    stream: totalsRepo.watchDailyTotalsForMonth(
      focused.year,
      focused.month,
    ),
    builder: (context, dailySnap) {
      return StreamBuilder<Map<int, double>>(
        stream: totalsRepo.watchPendingPeopleNetForMonth(
          focused.year,
          focused.month,
        ),
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
            rowHeight: 76,
            daysOfWeekHeight: 26,
            headerVisible: false,
            sixWeekMonthsEnforced: false,
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: true,
              cellMargin: EdgeInsets.all(2),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
              weekendStyle: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            onPageChanged: (focusedDay) {
              ref.read(focusedMonthProvider.notifier).state =
                  DateTime(focusedDay.year, focusedDay.month);
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
                    const [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ][day.weekday - 1],
                    style: TextStyle(
                      color: isSunday
                          ? const Color(0xFFFF5A6E)
                          : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                );
              },
              defaultBuilder: (context, day, focusedDay) =>
                  _dayCell(
                context,
                ref,
                day,
                dayTotals[day.day],
                pending[day.day] ?? 0,
              ),
              todayBuilder: (context, day, focusedDay) =>
                  _dayCell(
                context,
                ref,
                day,
                dayTotals[day.day],
                pending[day.day] ?? 0,
                isToday: true,
              ),
              selectedBuilder: (context, day, focusedDay) =>
                  _dayCell(
                context,
                ref,
                day,
                dayTotals[day.day],
                pending[day.day] ?? 0,
                isSelected: true,
              ),
              outsideBuilder: (context, day, focusedDay) =>
                  _dayCell(
                context,
                ref,
                day,
                null,
                0,
                isOutside: true,
              ),
            ),
          );
        },
      );
    },
  ),
),

// ---- 4. Net Savings + Savings Rate ----
StreamBuilder<PeriodTotals>(
  stream: totalsRepo.watchTotalsForMonth(
    focused.year,
    focused.month,
  ),
  builder: (context, totalsSnap) {
    final t = totalsSnap.data ?? PeriodTotals.zero;

    final savingsRate = t.income > 0
        ? (t.total / t.income) * 100
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'Net Savings',
              value: t.total,
              color: t.total >= 0
                  ? AppColors.incomeGreen
                  : AppColors.expense,
              icon: Icons.savings_outlined,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PercentageCard(
              label: 'Savings Rate',
              value: savingsRate,
              icon: Icons.trending_up_rounded,
              color: savingsRate >= 0
                  ? AppColors.incomeGreen
                  : AppColors.expense,
            ),
          ),
        ],
      ),
    );
  },
),

// ---- 5. Lent + Borrowed ----
StreamBuilder<List<PeopleEntry>>(
  stream: peopleRepo.watchEntriesForMonth(
    focused.year,
    focused.month,
  ),
  builder: (context, peopleSnap) {
    final entries = peopleSnap.data ?? [];

    final borrowed = entries
        .where((e) => e.type == 'borrowed' && !e.settled)
        .fold<double>(0.0, (sum, e) => sum + e.amount);

    final lent = entries
        .where((e) => e.type == 'lent' && !e.settled)
        .fold<double>(0.0, (sum, e) => sum + e.amount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'Lent',
              value: lent,
              color: AppColors.borrowedLent,
              icon: Icons.arrow_outward_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              label: 'Borrowed',
              value: borrowed,
              color: AppColors.borrowedLent,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
        ],
      ),
    );
  },
),

      ]
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
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
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppColors.accent, width: 1.4)
              : Border.all(color: Colors.white10, width: 0.5),
          color: isSelected
              ? Colors.white10
              : (isToday ? AppColors.accent.withOpacity(0.12) : null),
        ),
        padding: const EdgeInsets.fromLTRB(5, 3, 2, 2),
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: isToday ? const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent) : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(fontSize: 12, color: isToday ? Colors.white : dayNumberColor, fontWeight: FontWeight.w700),
                ),
              ),
              if (hasIncome)
                Text(
                  '+${compactAmount(totals!.income)}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.incomeGreen, fontWeight: FontWeight.w600),
                ),
              if (hasExpense)
                Text(
                  '-${compactAmount(totals!.expense)}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.expense, fontWeight: FontWeight.w600),
                ),
              if (pending != 0)
                Text(
                  pending > 0 ? '+${compactAmount(pending)}' : '-${compactAmount(pending.abs())}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.borrowedLent, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool showSign;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    final sign = showSign && value != 0 ? (value > 0 ? '+' : '-') : '';
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
                Text(
                  '$sign$kCurrencySymbol${compactAmount(value.abs())}',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _PercentageCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _PercentageCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}