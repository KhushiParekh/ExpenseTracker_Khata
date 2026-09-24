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
  /// `recurringGroupId` links this row to the batch it was generated with
  /// (see `_AddTransactionSheetState._save` for how a series is created),
  /// so the whole series can later be found and its future occurrences
  /// stopped from the More screen.
  Future<void> addTransaction({
    required String type, // 'expense' | 'income'
    required double amount,
    required DateTime date,
    String? accountId,
    String? categoryId,
    String remark = '',
    bool isYearly = false,
    String? recurringGroupId,
  }) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: _uuid.v4(),
          type: type,
          amount: amount,
          txnDate: date,
          accountId: Value(accountId),
          categoryId: Value(categoryId),
          remark: Value(remark),
          isYearly: Value(isYearly),
          recurringGroupId: Value(recurringGroupId),
          updatedAt: DateTime.now(),
          pendingSync: const Value(true),
        ));

    if (accountId != null) {
      final acc = await accountRepo.getById(accountId);
      await accountRepo.adjustBalance(accountId, _signedDelta(type, amount, acc));
    }
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

  // -------------------------------------------------------------------
  // Recurring series management (More screen -> "Manage recurring")
  // -------------------------------------------------------------------

  /// One row per distinct recurring series still holding at least one
  /// future occurrence, used to populate the "active recurring" list.
  Stream<List<RecurringSeriesInfo>> watchActiveRecurringSeries() {
    return db.watchAllTransactions().map((rows) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final byGroup = <String, List<Transaction>>{};
      for (final r in rows) {
        if (r.recurringGroupId == null) continue;
        byGroup.putIfAbsent(r.recurringGroupId!, () => []).add(r);
      }

      final result = <RecurringSeriesInfo>[];
      byGroup.forEach((groupId, entries) {
        entries.sort((a, b) => a.txnDate.compareTo(b.txnDate));
        final future = entries.where((e) => !e.txnDate.isBefore(todayStart)).toList();
        if (future.isEmpty) return; // series has already fully lapsed

        // Frequency isn't stored explicitly, so it's inferred from the gap
        // between two occurrences — only needed for a friendly label.
        String frequency = 'monthly';
        if (entries.length >= 2) {
          final gapDays = entries[1].txnDate.difference(entries[0].txnDate).inDays;
          if (gapDays <= 10) {
            frequency = 'weekly';
          } else if (gapDays >= 300) {
            frequency = 'annually';
          }
        }

        final first = entries.first;
        result.add(RecurringSeriesInfo(
          groupId: groupId,
          type: first.type,
          amount: first.amount,
          remark: first.remark,
          categoryId: first.categoryId,
          frequency: frequency,
          nextDate: future.first.txnDate,
          remainingCount: future.length,
          totalCount: entries.length,
        ));
      });

      result.sort((a, b) => a.nextDate.compareTo(b.nextDate));
      return result;
    });
  }

  /// Cancels everything still ahead in a recurring series (today included),
  /// leaving past occurrences untouched — "stopping" a recurring entry
  /// should not erase the history it already created.
  Future<int> stopRecurring(String groupId) async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    final rows = await (db.select(db.transactions)
          ..where((t) => t.recurringGroupId.equals(groupId))
          ..where((t) => t.deleted.equals(false))
          ..where((t) => t.txnDate.isBiggerOrEqualValue(todayStart)))
        .get();

    for (final r in rows) {
      await deleteTransaction(r.id);
    }
    return rows.length;
  }

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
}
