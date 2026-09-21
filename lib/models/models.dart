// Plain immutable models used across the app (UI + repositories).
// The Drift-generated local tables map to/from these via `toRow`/`fromRow`
// helpers declared alongside each repository.

class AccountModel {
  final String id;
  final String name;
  final String type; // cash, bank, card, upi, other
  final bool isLiability;
  final double balance;
  final bool archived;

  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.isLiability,
    required this.balance,
    this.archived = false,
  });

  AccountModel copyWith({double? balance, bool? archived}) => AccountModel(
        id: id,
        name: name,
        type: type,
        isLiability: isLiability,
        balance: balance ?? this.balance,
        archived: archived ?? this.archived,
      );
}

class CategoryModel {
  final String id;
  final String name;
  final String icon;
  final String kind; // expense, income
  final String? parentId;
  final int sortOrder;

  CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    this.parentId,
    this.sortOrder = 0,
  });
}

class TransactionModel {
  final String id;
  final String type; // expense, income
  final String? accountId;
  final String? categoryId;
  final double amount;
  final String remark;
  final DateTime txnDate;
  final bool isYearly;
  final DateTime updatedAt;
  final bool deleted;
  final bool pendingSync;

  TransactionModel({
    required this.id,
    required this.type,
    this.accountId,
    this.categoryId,
    required this.amount,
    this.remark = '',
    required this.txnDate,
    this.isYearly = false,
    DateTime? updatedAt,
    this.deleted = false,
    this.pendingSync = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  TransactionModel copyWith({
    double? amount,
    String? remark,
    bool? isYearly,
    bool? deleted,
    bool? pendingSync,
    DateTime? updatedAt,
  }) =>
      TransactionModel(
        id: id,
        type: type,
        accountId: accountId,
        categoryId: categoryId,
        amount: amount ?? this.amount,
        remark: remark ?? this.remark,
        txnDate: txnDate,
        isYearly: isYearly ?? this.isYearly,
        updatedAt: updatedAt ?? DateTime.now(),
        deleted: deleted ?? this.deleted,
        pendingSync: pendingSync ?? this.pendingSync,
      );
}

class PeopleEntryModel {
  final String id;
  final String type; // borrowed, lent
  final String personName;
  final String? accountId;
  final double amount;
  final String remark;
  final DateTime entryDate;
  final bool settled;
  final DateTime? settledAt;
  final DateTime updatedAt;
  final bool deleted;
  final bool pendingSync;

  PeopleEntryModel({
    required this.id,
    required this.type,
    this.personName = '',
    this.accountId,
    required this.amount,
    this.remark = '',
    required this.entryDate,
    this.settled = false,
    this.settledAt,
    DateTime? updatedAt,
    this.deleted = false,
    this.pendingSync = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  PeopleEntryModel copyWith({bool? settled, DateTime? settledAt, bool? pendingSync}) =>
      PeopleEntryModel(
        id: id,
        type: type,
        personName: personName,
        accountId: accountId,
        amount: amount,
        remark: remark,
        entryDate: entryDate,
        settled: settled ?? this.settled,
        settledAt: settledAt ?? this.settledAt,
        updatedAt: DateTime.now(),
        deleted: deleted,
        pendingSync: pendingSync ?? this.pendingSync,
      );

  /// Signed contribution to expense totals once settled:
  /// borrowed -> +amount (adds to expense), lent -> -amount (reduces expense)
  double get settleDelta => type == 'borrowed' ? amount : -amount;
}

class BudgetModel {
  final String id;
  final int year;
  final int month;
  final double amount;

  BudgetModel({required this.id, required this.year, required this.month, required this.amount});
}

/// Aggregated bucket used by the Monthly/Yearly tabs.
class MonthSummary {
  final int year;
  final int month;
  final double income;
  final double expense;
  double get total => income - expense;
  MonthSummary({required this.year, required this.month, required this.income, required this.expense});
}

class CategorySlice {
  final String categoryId;
  final String name;
  final String icon;
  final double amount;
  double percent = 0;
  CategorySlice({required this.categoryId, required this.name, required this.icon, required this.amount});
}
