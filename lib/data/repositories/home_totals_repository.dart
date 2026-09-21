import 'package:rxdart/rxdart.dart';
import '../local/app_database.dart';
import '../../models/models.dart';
import 'transaction_repository.dart';
import 'people_repository.dart';

/// A single day/period's figures as shown on the Home screen
/// (Calendar / Monthly / Yearly / Total tabs).
class PeriodTotals {
  final double income;
  final double expense; // already includes People fold-ins, see below
  PeriodTotals({required this.income, required this.expense});
  double get total => income - expense;
  static final zero = PeriodTotals(income: 0, expense: 0);
}

/// Combines transactions + People (Borrowed/Lent) entries into the figures
/// the Home tabs display. Everything here is a *reactive stream* (backed
/// by Drift's `.watch()`), so any add/edit/delete/settle anywhere in the
/// app is reflected instantly, with each period computed from exactly
/// three underlying queries no matter how many days/months it spans —
/// this is what fixes the "takes forever to show up" bug (the old code
/// re-queried the whole People table once per calendar day).
///
/// Business rules baked in here:
///  - `is_yearly` transactions are EXCLUDED everywhere on Home.
///  - LENT entries count as an expense from the moment they're created
///    (money already left your hand) — regardless of settled status.
///  - BORROWED entries do NOT affect expense while unsettled.
///  - Settling EITHER kind adds a one-time delta on the settle date:
///    borrowed -> +amount (paying it back), lent -> -amount (got it back).
class HomeTotalsRepository {
  final AppDatabase db;
  final TransactionRepository transactionRepo;
  final PeopleRepository peopleRepo;

  HomeTotalsRepository(this.db, this.transactionRepo, this.peopleRepo);

  Stream<PeriodTotals> watchTotalsBetween(DateTime start, DateTime end) {
    return Rx.combineLatest3(
      db.watchTransactionsBetween(start, end, includeYearly: false),
      db.watchPeopleEntriesByEntryDate(start, end),
      db.watchSettledPeopleEntriesBySettleDate(start, end),
      (List<Transaction> txns, List<PeopleEntry> lentRows, List<PeopleEntry> settledRows) {
        double income = 0, expense = 0;
        for (final t in txns) {
          if (t.type == 'income') {
            income += t.amount;
          } else {
            expense += t.amount;
          }
        }
        for (final p in lentRows) {
          if (p.type == 'lent') expense += p.amount;
        }
        for (final p in settledRows) {
          expense += p.type == 'borrowed' ? p.amount : -p.amount;
        }
        return PeriodTotals(income: income, expense: expense);
      },
    );
  }

  Stream<PeriodTotals> watchTotalsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return watchTotalsBetween(start, end);
  }

  Stream<PeriodTotals> watchTotalsForMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
    return watchTotalsBetween(start, end);
  }

  Stream<PeriodTotals> watchTotalsForYear(int year) {
    return watchTotalsBetween(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59, 59));
  }

  /// Per-day breakdown for the whole month in ONE combined query set —
  /// powers the Calendar tab's day cells.
  Stream<Map<int, PeriodTotals>> watchDailyTotalsForMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
    final daysInMonth = DateTime(year, month + 1, 0).day;

    return Rx.combineLatest3(
      db.watchTransactionsBetween(start, end, includeYearly: false),
      db.watchPeopleEntriesByEntryDate(start, end),
      db.watchSettledPeopleEntriesBySettleDate(start, end),
      (List<Transaction> txns, List<PeopleEntry> lentRows, List<PeopleEntry> settledRows) {
        final income = List<double>.filled(daysInMonth + 1, 0);
        final expense = List<double>.filled(daysInMonth + 1, 0);
        for (final t in txns) {
          final d = t.txnDate.day;
          if (t.type == 'income') {
            income[d] += t.amount;
          } else {
            expense[d] += t.amount;
          }
        }
        for (final p in lentRows) {
          if (p.type == 'lent') expense[p.entryDate.day] += p.amount;
        }
        for (final p in settledRows) {
          final d = p.settledAt!.day;
          expense[d] += p.type == 'borrowed' ? p.amount : -p.amount;
        }
        return {
          for (int d = 1; d <= daysInMonth; d++) d: PeriodTotals(income: income[d], expense: expense[d]),
        };
      },
    );
  }

  /// Net UNSETTLED borrowed/lent amount per day (borrowed:+, lent:-) —
  /// drives the blue marker on the Calendar. Settled entries are excluded
  /// since their value has already moved into `expense` above.
  Stream<Map<int, double>> watchPendingPeopleNetForMonth(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return db.watchPeopleEntriesForMonth(year, month).map((rows) {
      final net = List<double>.filled(daysInMonth + 1, 0);
      for (final r in rows.where((r) => !r.settled)) {
        net[r.entryDate.day] += r.type == 'borrowed' ? r.amount : -r.amount;
      }
      return {for (int d = 1; d <= daysInMonth; d++) d: net[d]};
    });
  }

  /// Month-by-month rollup for the Monthly tab (excludes yearly-marked).
  Stream<List<MonthSummary>> watchMonthlySummaries(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31, 23, 59, 59);
    return Rx.combineLatest3(
      db.watchTransactionsBetween(start, end, includeYearly: false),
      db.watchPeopleEntriesByEntryDate(start, end),
      db.watchSettledPeopleEntriesBySettleDate(start, end),
      (List<Transaction> txns, List<PeopleEntry> lentRows, List<PeopleEntry> settledRows) {
        final income = List<double>.filled(13, 0);
        final expense = List<double>.filled(13, 0);
        for (final t in txns) {
          final m = t.txnDate.month;
          if (t.type == 'income') {
            income[m] += t.amount;
          } else {
            expense[m] += t.amount;
          }
        }
        for (final p in lentRows) {
          if (p.type == 'lent') expense[p.entryDate.month] += p.amount;
        }
        for (final p in settledRows) {
          expense[p.settledAt!.month] += p.type == 'borrowed' ? p.amount : -p.amount;
        }
        return [for (int m = 1; m <= 12; m++) MonthSummary(year: year, month: m, income: income[m], expense: expense[m])];
      },
    );
  }

  /// Month-by-month rollup of ONLY yearly-marked expenses — exclusively
  /// for the Home → Yearly tab (see transactionRepo.watchYearlyMarkedBetween).
  Stream<List<MonthSummary>> watchYearlyTabMonthlySummaries(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31, 23, 59, 59);
    return transactionRepo.watchYearlyMarkedBetween(start, end).map((rows) {
      final expense = List<double>.filled(13, 0);
      for (final r in rows) {
        expense[r.txnDate.month] += r.amount;
      }
      return [for (int m = 1; m <= 12; m++) MonthSummary(year: year, month: m, income: 0, expense: expense[m])];
    });
  }
}
