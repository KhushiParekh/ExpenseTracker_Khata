import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/app_database.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/repositories/people_repository.dart';
import '../data/repositories/home_totals_repository.dart';
import '../data/repositories/account_category_repository.dart';
import '../services/backup_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final accountRepoProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

final categoryRepoProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);

final transactionRepoProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider), ref.watch(accountRepoProvider)),
);

final peopleRepoProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(ref.watch(appDatabaseProvider), ref.watch(accountRepoProvider)),
);

final homeTotalsRepoProvider = Provider<HomeTotalsRepository>(
  (ref) => HomeTotalsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(transactionRepoProvider),
    ref.watch(peopleRepoProvider),
  ),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(appDatabaseProvider)),
);

/// Currently focused date on the Calendar tab (defaults to today).
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Currently focused month/year for Monthly/Yearly/Total/People tabs.
final focusedMonthProvider = StateProvider<DateTime>((ref) => DateTime(DateTime.now().year, DateTime.now().month));

/// Which of the 5 Home sub-tabs is active: 0 Calendar, 1 Monthly, 2 Yearly, 3 People, 4 Total
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

// ---- Shared lookup streams (used by search, modal, stats) ----------
final allAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllAccounts(),
);

final allCategoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllCategories(),
);

final allTransactionsProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllTransactions(),
);
