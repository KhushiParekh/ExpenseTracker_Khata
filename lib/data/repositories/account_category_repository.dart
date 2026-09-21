import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';

const _uuid = Uuid();

class AccountRepository {
  final AppDatabase db;
  AccountRepository(this.db);

  Stream<List<Account>> watchAll() =>
      (db.select(db.accounts)..where((a) => a.archived.equals(false))).watch();

  Future<Account?> getById(String id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Best-effort lookup of the account named "UPI" (seeded by default on
  /// signup) — used to preselect it in the Add Entry modal, per spec.
  Future<Account?> getDefaultAccount() async {
    final upi = await (db.select(db.accounts)..where((a) => a.type.equals('upi') & a.archived.equals(false))).getSingleOrNull();
    if (upi != null) return upi;
    return (db.select(db.accounts)..where((a) => a.archived.equals(false))).getSingleOrNull();
  }

  Future<void> addAccount({required String name, required String type, bool isLiability = false}) async {
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: _uuid.v4(),
          name: name,
          type: type,
          isLiability: Value(isLiability),
          updatedAt: DateTime.now(),
          pendingSync: const Value(true),
        ));
  }

  /// Applies a raw signed delta to an account's balance. Callers decide the
  /// sign: for a normal (asset) account, spending money should pass a
  /// negative delta; for a liability account (credit card), spending money
  /// increases what you owe, so callers should pass a positive delta there
  /// instead. See `TransactionRepository._signedBalanceDelta`.
  Future<void> adjustBalance(String? accountId, double delta) async {
    if (accountId == null || delta == 0) return;
    final acc = await getById(accountId);
    if (acc == null) return;
    await (db.update(db.accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(
        balance: Value(acc.balance + delta),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<void> archive(String id) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
    );
  }
}

class CategoryRepository {
  final AppDatabase db;
  CategoryRepository(this.db);

  Stream<List<Category>> watchByKind(String kind) =>
      (db.select(db.categories)
            ..where((c) => c.kind.equals(kind))
            ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
          .watch();

  Future<void> addCategory({required String name, required String icon, required String kind, String? parentId}) async {
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: _uuid.v4(),
          name: name,
          kind: kind,
          icon: Value(icon),
          parentId: Value(parentId),
          updatedAt: DateTime.now(),
          pendingSync: const Value(true),
        ));
  }

  Future<void> renameCategory(String id, String newName) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(name: Value(newName), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
    );
  }

  Future<void> updateIcon(String id, String newIcon) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(icon: Value(newIcon), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
    );
  }

  /// Persists a new drag-and-drop order for a kind's category list —
  /// `orderedIds` is the full list of category ids in their new order.
  Future<void> reorder(List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      await (db.update(db.categories)..where((c) => c.id.equals(orderedIds[i]))).write(
        CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(DateTime.now()), pendingSync: const Value(true)),
      );
    }
  }

  Future<void> deleteCategory(String id) async {
    await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
  }
}
