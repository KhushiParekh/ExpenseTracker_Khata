import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../../models/models.dart';
import 'account_category_repository.dart';

const _uuid = Uuid();

class TransactionRepository {
  final AppDatabase db;
  final AccountRepository accountRepo;
  TransactionRepository(this.db, this.accountRepo);

  /// Signed balance delta for a transaction of [type] and [amount] against
  /// [account]. Normal (asset) accounts: expense subtracts, income adds.
  /// Liability accounts (credit card): expense adds to what you owe,
  /// income (a payment) subtracts from it.
  double _signedDelta(String type, double amount, Account? account) {
    final isLiability = account?.isLiability ?? false;
    final isExpense = type == 'expense';
    if (isLiability) {
      return isExpense ? amount : -amount;
    }
    return isExpense ? -amount : amount;
  }

  /// Add a new expense/income entry.
  /// `isYearly` entries are written exactly like any other transaction —
  /// the *filtering* (hiding them from Home tabs) happens at query time,
  /// not at write time, so Statistics can still include them.
  Future<String> addTransaction({
    required String type, // 'expense' | 'income'
    required double amount,
    required DateTime date,
    String? accountId,
    String? categoryId,
    String remark = '',
    bool isYearly = false,
    String? recurringGroupId,
    String? recurringFrequency,
  }) async {
    final id = _uuid.v4();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          type: type,
          amount: amount,
          txnDate: date,
          accountId: Value(accountId),
          categoryId: Value(categoryId),
          remark: Value(remark),
          isYearly: Value(isYearly),
          recurringGroupId: Value(recurringGroupId),
          recurringFrequency: Value(recurringFrequency),
          updatedAt: DateTime.now(),
          pendingSync: const Value(true),
        ));

    if (accountId != null) {
      final acc = await accountRepo.getById(accountId);
      await accountRepo.adjustBalance(accountId, _signedDelta(type, amount, acc));
    }
    return id;
  }

  /// Edits an existing transaction in place, correctly reversing the old
  /// account-balance effect and applying the new one (handles the account
  /// itself changing too, e.g. moving an expense from Cash to a Card).
  Future<void> updateTransaction(
    Transaction existing, {
    required String type,
    required double amount,
    required DateTime date,
    String? accountId,
    String? categoryId,
    String remark = '',
    bool isYearly = false,
  }) async {
    // Reverse the old effect on its original account.
    if (existing.accountId != null) {
      final oldAcc = await accountRepo.getById(existing.accountId!);
      await accountRepo.adjustBalance(existing.accountId, -_signedDelta(existing.type, existing.amount, oldAcc));
    }

    await (db.update(db.transactions)..where((t) => t.id.equals(existing.id))).write(
      TransactionsCompanion(
        type: Value(type),
        amount: Value(amount),
        txnDate: Value(date),
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        remark: Value(remark),
        isYearly: Value(isYearly),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );

    // Apply the new effect on the (possibly different) new account.
    if (accountId != null) {
      final newAcc = await accountRepo.getById(accountId);
      await accountRepo.adjustBalance(accountId, _signedDelta(type, amount, newAcc));
    }
  }

  Future<void> deleteTransaction(String id) async {
    final existing = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return;

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(deleted: const Value(true), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
    );

    // Reverse its balance effect.
    if (existing.accountId != null) {
      final acc = await accountRepo.getById(existing.accountId!);
      await accountRepo.adjustBalance(existing.accountId, -_signedDelta(existing.type, existing.amount, acc));
    }
  }

  Stream<List<Transaction>> watchDay(DateTime day) => db.watchTransactionsForDay(day);

  /// Home tab queries — ALWAYS exclude `isYearly == true` rows,
  /// per spec: yearly-marked expenses never show on Calendar/Monthly/
  /// Yearly/Total, only in Statistics.
  Future<List<Transaction>> homeTransactionsBetween(DateTime start, DateTime end) {
    return db.transactionsBetween(start, end, includeYearly: false);
  }

  Stream<List<Transaction>> watchHomeTransactionsBetween(DateTime start, DateTime end) {
    return db.watchTransactionsBetween(start, end, includeYearly: false);
  }

  /// Statistics queries — INCLUDE yearly-marked rows.
  Future<List<Transaction>> statsTransactionsBetween(DateTime start, DateTime end) {
    return db.transactionsBetween(start, end, includeYearly: true);
  }

  Stream<List<Transaction>> watchStatsTransactionsBetween(DateTime start, DateTime end) {
    return db.watchTransactionsBetween(start, end, includeYearly: true);
  }

  /// Home → Yearly tab queries — ONLY yearly-marked rows. This tab is a
  /// dedicated ledger for "count as yearly expense" items (shoes, clothes,
  /// classes, etc.) and never shows regular day-to-day transactions.
  Future<List<Transaction>> yearlyMarkedBetween(DateTime start, DateTime end) {
    return db.yearlyMarkedTransactionsBetween(start, end);
  }

  Stream<List<Transaction>> watchYearlyMarkedBetween(DateTime start, DateTime end) {
    return db.watchYearlyMarkedTransactionsBetween(start, end);
  }

  // ---- Recurring series --------------------------------------------
  // A series is just N ordinary Transaction rows that share one
  // `recurringGroupId` (assigned once, when they're all created together
  // — see AddTransactionSheet._save). There's no separate "series" table:
  // membership, frequency, and how many are left are all derived here from
  // the rows themselves, so a stopped/edited/deleted row is automatically
  // reflected with no extra bookkeeping.

  /// Every recurring series that still has at least one occurrence dated
  /// today or later, newest-next first. Powers the "Recurring Transactions"
  /// card in More, where each series can be reviewed and stopped.
  Stream<List<RecurringSeriesInfo>> watchActiveRecurringSeries() {
    return db.watchRecurringTransactions().map((rows) {
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);

      final byGroup = <String, List<Transaction>>{};
      for (final r in rows) {
        final gid = r.recurringGroupId;
        if (gid == null) continue;
        byGroup.putIfAbsent(gid, () => []).add(r);
      }

      final result = <RecurringSeriesInfo>[];
      for (final entry in byGroup.entries) {
        final series = entry.value..sort((a, b) => a.txnDate.compareTo(b.txnDate));
        final upcoming = series.where((r) => !r.txnDate.isBefore(startOfToday)).toList();
        if (upcoming.isEmpty) continue; // fully in the past, or fully stopped
        final first = series.first;
        result.add(RecurringSeriesInfo(
          groupId: entry.key,
          type: first.type,
          categoryId: first.categoryId,
          remark: first.remark,
          frequency: first.recurringFrequency ?? 'monthly',
          nextDate: upcoming.first.txnDate,
          remainingCount: upcoming.length,
          totalCount: series.length,
          amount: first.amount,
        ));
      }
      result.sort((a, b) => a.nextDate.compareTo(b.nextDate));
      return result;
    });
  }

  /// Cancels every occurrence of series [groupId] dated today or later.
  /// Occurrences already in the past are untouched — they already
  /// happened and stay in the ledger. Returns how many were cancelled.
  Future<int> stopRecurring(String groupId) async {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final upcoming = await (db.select(db.transactions)
          ..where((t) => t.recurringGroupId.equals(groupId))
          ..where((t) => t.deleted.equals(false))
          ..where((t) => t.txnDate.isBiggerOrEqualValue(startOfToday)))
        .get();
    for (final row in upcoming) {
      await deleteTransaction(row.id); // soft-delete + reverse its balance effect
    }
    return upcoming.length;
  }

  List<CategorySlice> categoryBreakdown(
    List<Transaction> rows,
    List<Category> categories, {
    required String kind, // 'expense' or 'income'
  }) {
    final byCategory = <String, double>{};
    for (final r in rows.where((r) => r.type == kind)) {
      final key = r.categoryId ?? 'uncategorized';
      byCategory[key] = (byCategory[key] ?? 0) + r.amount;
    }
    final total = byCategory.values.fold(0.0, (a, b) => a + b);
    final slices = byCategory.entries.map((e) {
      final cat = categories.where((c) => c.id == e.key).toList();
      final name = cat.isNotEmpty ? cat.first.name : 'Uncategorized';
      final icon = cat.isNotEmpty ? cat.first.icon : '❓';
      final slice = CategorySlice(categoryId: e.key, name: name, icon: icon, amount: e.value);
      slice.percent = total == 0 ? 0 : (e.value / total) * 100;
      return slice;
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return slices;
  }
    /// Lifetime income vs expense totals per account, keyed by accountId.
  /// Powers the small colour indicator on the Accounts screen (see
  /// AccountsScreen._IncomeExpenseBars) — deliberately not date-scoped,
  /// it's an at-a-glance signal, not a report.
  Stream<Map<String, ({double income, double expense})>> watchIncomeExpenseByAccount() {
    return db.watchAllTransactions().map((rows) {
      final map = <String, ({double income, double expense})>{};
      for (final r in rows) {
        final accId = r.accountId;
        if (accId == null) continue;
        final cur = map[accId] ?? (income: 0.0, expense: 0.0);
        if (r.type == 'income') {
          map[accId] = (income: cur.income + r.amount, expense: cur.expense);
        } else if (r.type == 'expense') {
          map[accId] = (income: cur.income, expense: cur.expense + r.amount);
        }
      }
      return map;
    });
  }

  /// Same as [categoryBreakdown], but also folds in People (borrowed/lent)
/// entries using the same signed-delta rules as the expense totals:
///  - `peopleByEntryDate`: ALL entries (settled or not) whose entryDate
///    falls in the queried range — from `watchPeopleEntriesByEntryDate`.
///    Only `lent` entries contribute here (they count as expense from
///    creation).
///  - `peopleSettledInRange`: entries whose settledAt falls in the
///    queried range — from `watchSettledPeopleEntriesBySettleDate`.
///    Borrowed adds, lent subtracts (reversing its creation-month effect).
/// Entries with no categoryId are ignored (nothing to attribute).
List<CategorySlice> categoryBreakdownWithPeople(
  List<Transaction> transactions,
  List<PeopleEntry> peopleByEntryDate,
  List<PeopleEntry> peopleSettledInRange, // now only used for lent's reversal
  List<Category> categories, {
  required String kind,
}) {
  final byCategory = <String, double>{};

  for (final r in transactions.where((r) => r.type == kind)) {
    final key = r.categoryId ?? 'uncategorized';
    byCategory[key] = (byCategory[key] ?? 0) + r.amount;
  }

  if (kind == 'expense') {
    for (final p in peopleByEntryDate.where((p) => p.categoryId != null)) {
      final counts = (p.type == 'lent' && !p.settled) || (p.type == 'borrowed' && p.settled);
      if (!counts) continue;
      final key = p.categoryId!;
      byCategory[key] = (byCategory[key] ?? 0) + p.amount;
    }
  }

  final positive = Map.fromEntries(byCategory.entries.where((e) => e.value > 0));
  final total = positive.values.fold(0.0, (a, b) => a + b);
  final slices = positive.entries.map((e) {
    final cat = categories.where((c) => c.id == e.key).toList();
    final name = cat.isNotEmpty ? cat.first.name : 'Uncategorized';
    final icon = cat.isNotEmpty ? cat.first.icon : '❓';
    final slice = CategorySlice(categoryId: e.key, name: name, icon: icon, amount: e.value);
    slice.percent = total == 0 ? 0 : (e.value / total) * 100;
    return slice;
  }).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return slices;
}
}




