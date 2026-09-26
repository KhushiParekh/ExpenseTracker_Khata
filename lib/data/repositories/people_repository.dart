import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import 'account_category_repository.dart';

const _uuid = Uuid();

class PeopleRepository {
  final AppDatabase db;
  final AccountRepository accountRepo;
  PeopleRepository(this.db, this.accountRepo);

  /// Cash-account effect of a People entry:
  /// - borrowed (money received): account balance goes UP.
  /// - lent (money handed out):   account balance goes DOWN.
  double _creationDelta(String type, double amount) => type == 'borrowed' ? amount : -amount;

  Future<void> addEntry({
    required String type, // 'borrowed' | 'lent'
    required double amount,
    required DateTime date,
    String personName = '',
    String? accountId,
    String remark = '',
  }) async {
    await db.into(db.peopleEntries).insert(PeopleEntriesCompanion.insert(
          id: _uuid.v4(),
          type: type,
          amount: amount,
          entryDate: date,
          personName: Value(personName),
          accountId: Value(accountId),
          remark: Value(remark),
          updatedAt: DateTime.now(),
          pendingSync: const Value(true),
        ));

    if (accountId != null) {
      await accountRepo.adjustBalance(accountId, _creationDelta(type, amount));
    }
  }

  /// Edits an existing entry in place. Reverses whatever cash-account
  /// effect the OLD values had (its creation delta, and — if it was
  /// already settled — the reversal that settling applied on top, which
  /// nets to zero), then re-applies the same combination for the NEW
  /// values on the (possibly different) account. `settled`/`settledAt`
  /// are untouched: editing details doesn't change settlement status.
  Future<void> updateEntry(
    PeopleEntry existing, {
    required String type,
    required double amount,
    required DateTime date,
    String personName = '',
    String? accountId,
    String remark = '',
  }) async {
    if (existing.accountId != null) {
      await accountRepo.adjustBalance(existing.accountId, -_creationDelta(existing.type, existing.amount));
      if (existing.settled) {
        await accountRepo.adjustBalance(existing.accountId, _creationDelta(existing.type, existing.amount));
      }
    }

    await (db.update(db.peopleEntries)..where((r) => r.id.equals(existing.id))).write(
      PeopleEntriesCompanion(
        type: Value(type),
        amount: Value(amount),
        entryDate: Value(date),
        personName: Value(personName),
        accountId: Value(accountId),
        remark: Value(remark),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );

    if (accountId != null) {
      await accountRepo.adjustBalance(accountId, _creationDelta(type, amount));
      if (existing.settled) {
        await accountRepo.adjustBalance(accountId, -_creationDelta(type, amount));
      }
    }
  }

  Future<List<PeopleEntry>> entriesForMonth(int year, int month) => db.peopleEntriesForMonth(year, month);
  Stream<List<PeopleEntry>> watchEntriesForMonth(int year, int month) => db.watchPeopleEntriesForMonth(year, month);

  /// Settle one or more Borrowed/Lent entries.
  ///
  /// Business rule (confirmed with product owner):
  ///  - Lent money is already counted as an expense from the moment it's
  ///    created (handing cash to someone = it left your pocket), shown in
  ///    blue to mark it as "recoverable". Settling a lent entry means the
  ///    money came BACK, so it REDUCES that month's expense.
  ///  - Borrowed money is NOT counted as an expense when received (it's
  ///    money in temporarily, not spent). Settling a borrowed entry means
  ///    you're paying it back, so it ADDS to that month's expense.
  ///
  /// Entries are NOT deleted — they're marked `settled = true` (with a
  /// timestamp) so the UI can render them faded/struck-through, per spec.
  /// The Home aggregation (see `HomeTotalsRepository`) folds every
  /// settled entry's signed delta (borrowed: +amount, lent: -amount)
  /// straight into that month's expense figure, based on `settledAt`.
  /// This keeps People entries as the single source of truth and avoids
  /// double counting or polluting category/income statistics.
  Future<void> settleEntries(List<PeopleEntry> entries) async {
    final now = DateTime.now();
    for (final e in entries) {
      if (e.settled) continue;
      await (db.update(db.peopleEntries)..where((r) => r.id.equals(e.id))).write(
        PeopleEntriesCompanion(
          settled: const Value(true),
          settledAt: Value(now),
          updatedAt: Value(now),
          pendingSync: const Value(true),
        ),
      );

      // Cash-account effect of settling: reverse of the creation delta —
      // paying back a borrowed loan reduces your cash; getting lent money
      // back increases it.
      if (e.accountId != null) {
        await accountRepo.adjustBalance(e.accountId, -_creationDelta(e.type, e.amount));
      }
    }
  }

  Future<void> unsettleEntry(PeopleEntry e) async {
    await (db.update(db.peopleEntries)..where((r) => r.id.equals(e.id))).write(
      PeopleEntriesCompanion(
        settled: const Value(false),
        settledAt: const Value(null),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
    if (e.accountId != null) {
      await accountRepo.adjustBalance(e.accountId, _creationDelta(e.type, e.amount));
    }
  }

  Future<void> deleteEntry(PeopleEntry e) async {
    await (db.update(db.peopleEntries)..where((r) => r.id.equals(e.id))).write(
      PeopleEntriesCompanion(deleted: const Value(true), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
    );
    if (e.accountId == null) return;
    // Reverse whatever effect(s) this entry had applied so far.
    await accountRepo.adjustBalance(e.accountId, -_creationDelta(e.type, e.amount));
    if (e.settled) {
      await accountRepo.adjustBalance(e.accountId, _creationDelta(e.type, e.amount));
    }
  }
}
