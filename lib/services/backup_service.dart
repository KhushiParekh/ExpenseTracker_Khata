import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import 'file_export.dart';

const _uuid = Uuid();
final _dateFmt = DateFormat('yyyy-MM-dd');

/// Result of an import run, surfaced to the user as a summary.
class ImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  final int categoriesCreated;

  ImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
    required this.categoriesCreated,
  });

  String get summary {
    final parts = <String>['$imported imported'];
    if (categoriesCreated > 0) parts.add('$categoriesCreated new categories');
    if (skipped > 0) parts.add('$skipped skipped');
    return parts.join(' · ');
  }
}

/// Handles reading and writing backup files. Everything happens on-device:
/// exports go straight to the user's Downloads/share sheet, and imports are
/// read from a file they pick. Nothing is uploaded anywhere.
class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  // =================================================================
  // EXPORT
  // =================================================================

  /// Full backup of every table, as JSON. This is the format to use when
  /// moving to another device — it round-trips losslessly.
  /// Returns where the file was saved.
  Future<String> exportJson() async {
    final payload = {
      'app': 'Khaata',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': (await db.allAccounts())
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'type': a.type,
                'isLiability': a.isLiability,
                'balance': a.balance,
                'archived': a.archived,
              })
          .toList(),
      'categories': (await db.allCategories())
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'icon': c.icon,
                'kind': c.kind,
                'parentId': c.parentId,
                'sortOrder': c.sortOrder,
              })
          .toList(),
      'transactions': (await db.allTransactionsForExport())
          .map((t) => {
                'id': t.id,
                'type': t.type,
                'accountId': t.accountId,
                'categoryId': t.categoryId,
                'amount': t.amount,
                'remark': t.remark,
                'date': _dateFmt.format(t.txnDate),
                'isYearly': t.isYearly,
              })
          .toList(),
      'peopleEntries': (await db.allPeopleEntriesForExport())
          .map((p) => {
                'id': p.id,
                'type': p.type,
                'personName': p.personName,
                'accountId': p.accountId,
                'amount': p.amount,
                'remark': p.remark,
                'date': _dateFmt.format(p.entryDate),
                'settled': p.settled,
                'settledAt': p.settledAt?.toIso8601String(),
              })
          .toList(),
      'budgets': (await db.allBudgets())
          .map((b) => {
                'id': b.id,
                'year': b.year,
                'month': b.month,
                'amount': b.amount,
              })
          .toList(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    return saveTextFile('khaata-backup-${_fileStamp()}.json', jsonStr, 'application/json');
  }

  /// Spreadsheet-friendly export of transactions only. Columns match what
  /// the importer expects, so a CSV export can be re-imported directly.
  /// Returns where the file was saved.
  Future<String> exportCsv() async {
    final txns = await db.allTransactionsForExport();
    final cats = {for (final c in await db.allCategories()) c.id: c};
    final accs = {for (final a in await db.allAccounts()) a.id: a};

    final rows = <List<dynamic>>[
      ['date', 'description', 'category', 'subcategory', 'type', 'amount', 'account', 'is_yearly'],
      ...txns.map((t) => [
            _dateFmt.format(t.txnDate),
            t.remark,
            t.categoryId == null ? '' : (cats[t.categoryId]?.name ?? ''),
            '',
            t.type,
            t.amount.toStringAsFixed(2),
            t.accountId == null ? '' : (accs[t.accountId]?.name ?? ''),
            t.isYearly ? 'yes' : 'no',
          ]),
    ];

    final csvStr = const ListToCsvConverter(eol: '\n').convert(rows);
    return saveTextFile('khaata-transactions-${_fileStamp()}.csv', csvStr, 'text/csv');
  }

  String _fileStamp() => DateFormat('yyyyMMdd-HHmm').format(DateTime.now());

  // =================================================================
  // IMPORT
  // =================================================================

  /// Lets the user pick a .csv or .json file and imports the transactions
  /// it contains. Returns null if they cancelled the picker.
  Future<ImportResult?> pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
      withData: true, // needed on web, harmless on Android
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      return ImportResult(imported: 0, skipped: 0, categoriesCreated: 0, errors: ['Could not read that file.']);
    }

    final content = utf8.decode(bytes, allowMalformed: true);
    final isJson = (file.extension ?? '').toLowerCase() == 'json' || content.trimLeft().startsWith('{');

    return isJson ? _importJson(content) : _importCsv(content);
  }

  Future<ImportResult> _importJson(String content) async {
    final errors = <String>[];
    int imported = 0, skipped = 0, categoriesCreated = 0;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return ImportResult(imported: 0, skipped: 0, categoriesCreated: 0, errors: ['That file is not valid JSON.']);
    }

    // Restore categories/accounts first so transactions can reference them.
    final existingCatIds = {for (final c in await db.allCategories()) c.id};
    for (final raw in (payload['categories'] as List? ?? [])) {
      final c = raw as Map<String, dynamic>;
      if (existingCatIds.contains(c['id'])) continue;
      await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion.insert(
            id: c['id'] as String,
            name: c['name'] as String,
            kind: c['kind'] as String,
            icon: Value((c['icon'] as String?) ?? '📁'),
            parentId: Value(c['parentId'] as String?),
            sortOrder: Value((c['sortOrder'] as num?)?.toInt() ?? 0),
            updatedAt: DateTime.now(),
            pendingSync: const Value(false),
          ));
      categoriesCreated++;
    }

    final existingAccIds = {for (final a in await db.allAccounts()) a.id};
    for (final raw in (payload['accounts'] as List? ?? [])) {
      final a = raw as Map<String, dynamic>;
      if (existingAccIds.contains(a['id'])) continue;
      await db.into(db.accounts).insertOnConflictUpdate(AccountsCompanion.insert(
            id: a['id'] as String,
            name: a['name'] as String,
            type: a['type'] as String,
            isLiability: Value((a['isLiability'] as bool?) ?? false),
            balance: Value((a['balance'] as num?)?.toDouble() ?? 0),
            archived: Value((a['archived'] as bool?) ?? false),
            updatedAt: DateTime.now(),
            pendingSync: const Value(false),
          ));
    }

    final existingTxnIds = {for (final t in await db.allTransactionsForExport()) t.id};
    for (final raw in (payload['transactions'] as List? ?? [])) {
      try {
        final t = raw as Map<String, dynamic>;
        final id = (t['id'] as String?) ?? _uuid.v4();
        if (existingTxnIds.contains(id)) {
          skipped++;
          continue;
        }
        await db.into(db.transactions).insertOnConflictUpdate(TransactionsCompanion.insert(
              id: id,
              type: (t['type'] as String?) ?? 'expense',
              amount: (t['amount'] as num).toDouble(),
              txnDate: DateTime.parse(t['date'] as String),
              accountId: Value(t['accountId'] as String?),
              categoryId: Value(t['categoryId'] as String?),
              remark: Value((t['remark'] as String?) ?? ''),
              isYearly: Value((t['isYearly'] as bool?) ?? false),
              updatedAt: DateTime.now(),
              pendingSync: const Value(false),
            ));
        imported++;
      } catch (e) {
        skipped++;
        if (errors.length < 5) errors.add('$e');
      }
    }

    for (final raw in (payload['peopleEntries'] as List? ?? [])) {
      try {
        final p = raw as Map<String, dynamic>;
        await db.into(db.peopleEntries).insertOnConflictUpdate(PeopleEntriesCompanion.insert(
              id: (p['id'] as String?) ?? _uuid.v4(),
              type: p['type'] as String,
              amount: (p['amount'] as num).toDouble(),
              entryDate: DateTime.parse(p['date'] as String),
              personName: Value((p['personName'] as String?) ?? ''),
              accountId: Value(p['accountId'] as String?),
              remark: Value((p['remark'] as String?) ?? ''),
              settled: Value((p['settled'] as bool?) ?? false),
              settledAt: Value(p['settledAt'] == null ? null : DateTime.parse(p['settledAt'] as String)),
              updatedAt: DateTime.now(),
              pendingSync: const Value(false),
            ));
      } catch (_) {
        skipped++;
      }
    }

    for (final raw in (payload['budgets'] as List? ?? [])) {
      try {
        final b = raw as Map<String, dynamic>;
        await db.into(db.budgets).insertOnConflictUpdate(BudgetsCompanion.insert(
              id: (b['id'] as String?) ?? _uuid.v4(),
              year: (b['year'] as num).toInt(),
              month: (b['month'] as num).toInt(),
              amount: Value((b['amount'] as num?)?.toDouble() ?? 0),
              updatedAt: DateTime.now(),
              pendingSync: const Value(false),
            ));
      } catch (_) {/* budgets are non-critical */}
    }

    return ImportResult(imported: imported, skipped: skipped, errors: errors, categoriesCreated: categoriesCreated);
  }

  Future<ImportResult> _importCsv(String content) async {
    final errors = <String>[];
    int imported = 0, skipped = 0, categoriesCreated = 0;

    // Normalise CRLF/CR to LF first: files exported from Excel, Google
    // Sheets and most banks use \r\n, and parsing those with eol '\n'
    // leaves a stray \r glued to the last column of every row.
    final normalised = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(normalised);
    if (rows.isEmpty) {
      return ImportResult(imported: 0, skipped: 0, categoriesCreated: 0, errors: ['That file is empty.']);
    }

    // Header row drives column mapping, so column order doesn't matter and
    // extra columns are ignored.
    final header = rows.first.map((c) => c.toString().trim().toLowerCase()).toList();
    int col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i != -1) return i;
      }
      return -1;
    }

    final iDate = col(['date', 'txn_date', 'transaction date']);
    final iDesc = col(['description', 'remark', 'note', 'details']);
    final iCat = col(['category']);
    final iSub = col(['subcategory', 'sub category']);
    final iType = col(['type']);
    final iAmount = col(['amount', 'value']);
    final iAccount = col(['account']);
    final iYearly = col(['is_yearly', 'yearly']);

    if (iDate == -1 || iAmount == -1) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        categoriesCreated: 0,
        errors: ['Could not find a "date" and "amount" column in that CSV.'],
      );
    }

    // Look up by lowercase name so imports match existing categories and
    // accounts regardless of casing.
    final catsByName = {for (final c in await db.allCategories()) c.name.toLowerCase(): c};
    final accsByName = {for (final a in await db.allAccounts()) a.name.toLowerCase(): a};

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

      try {
        if (row.every((c) => c.toString().trim().isEmpty)) continue;

        final amount = double.tryParse(cell(iAmount).replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (amount == null) {
          skipped++;
          continue;
        }

        final date = _parseFlexibleDate(cell(iDate));
        if (date == null) {
          skipped++;
          if (errors.length < 5) errors.add('Row ${r + 1}: unrecognised date "${cell(iDate)}"');
          continue;
        }

        // Work out expense vs income. An explicit type column always wins.
        // Failing that, fall back to the sign of the amount, which is the
        // usual bank-statement convention (debits negative, credits
        // positive). A bare positive number with no type column is the
        // ambiguous case, and "expense" is the safer default for a
        // spending tracker.
        String type = cell(iType).toLowerCase();
        if (type == 'debit' || type == 'dr' || type == 'withdrawal') type = 'expense';
        if (type == 'credit' || type == 'cr' || type == 'deposit') type = 'income';
        if (type != 'income' && type != 'expense') {
          type = amount < 0 ? 'expense' : (iType == -1 ? 'expense' : 'income');
        }

        // Prefer subcategory when present, since it's the more specific label.
        final catName = cell(iSub).isNotEmpty ? cell(iSub) : cell(iCat);
        String? categoryId;
        if (catName.isNotEmpty) {
          final existing = catsByName[catName.toLowerCase()];
          if (existing != null) {
            categoryId = existing.id;
          } else {
            // Unknown categories are created automatically rather than
            // dropping the row's classification.
            final newId = _uuid.v4();
            await db.into(db.categories).insert(CategoriesCompanion.insert(
                  id: newId,
                  name: catName,
                  kind: type,
                  icon: const Value('📁'),
                  sortOrder: Value(900 + categoriesCreated),
                  updatedAt: DateTime.now(),
                  pendingSync: const Value(false),
                ));
            final created = await (db.select(db.categories)..where((c) => c.id.equals(newId))).getSingle();
            catsByName[catName.toLowerCase()] = created;
            categoryId = newId;
            categoriesCreated++;
          }
        }

        final accName = cell(iAccount);
        final accountId = accName.isEmpty ? null : accsByName[accName.toLowerCase()]?.id;

        final yearlyCell = cell(iYearly).toLowerCase();
        final isYearly = yearlyCell == 'yes' || yearlyCell == 'true' || yearlyCell == '1';

        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: _uuid.v4(),
              type: type,
              amount: amount.abs(),
              txnDate: date,
              accountId: Value(accountId),
              categoryId: Value(categoryId),
              remark: Value(cell(iDesc)),
              isYearly: Value(isYearly),
              updatedAt: DateTime.now(),
              pendingSync: const Value(false),
            ));
        imported++;
      } catch (e) {
        skipped++;
        if (errors.length < 5) errors.add('Row ${r + 1}: $e');
      }
    }

    return ImportResult(imported: imported, skipped: skipped, errors: errors, categoriesCreated: categoriesCreated);
  }

  /// Accepts the date formats that show up in real exports, rather than
  /// forcing the user to reformat their file first.
  DateTime? _parseFlexibleDate(String raw) {
    if (raw.isEmpty) return null;
    final patterns = [
      'yyyy-MM-dd',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'MM/dd/yyyy',
      'yyyy/MM/dd',
      'd MMM yyyy',
      'dd MMM yyyy',
      'MMM d, yyyy',
    ];
    for (final p in patterns) {
      try {
        return DateFormat(p).parseStrict(raw);
      } catch (_) {/* try the next pattern */}
    }
    return DateTime.tryParse(raw);
  }
}
