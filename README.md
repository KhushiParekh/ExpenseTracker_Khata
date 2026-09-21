# Expense Tracker — Flutter + Supabase

Offline-first personal expense tracker. Android + Web. One-time login
(email/password or Google) syncs your data across devices.

## Folder structure

```
expense_tracker/
├── pubspec.yaml
├── supabase/
│   └── schema.sql                  # run this in Supabase SQL editor first
└── lib/
    ├── main.dart                   # entry point, periodic sync timer
    ├── core/
    │   ├── constants.dart          # currency (₹), colors, Supabase URL/anon key
    │   └── theme.dart              # dark theme matching the reference UI
    ├── models/
    │   └── models.dart             # plain Dart models (Transaction, Account, Category, PeopleEntry, Budget, MonthSummary, CategorySlice)
    ├── data/
    │   ├── local/
    │   │   └── app_database.dart   # Drift (SQLite/IndexedDB) local schema — offline cache
    │   ├── remote/
    │   │   └── supabase_service.dart   # auth + generic upsert/fetch helpers
    │   └── repositories/
    │       ├── transaction_repository.dart      # expense/income CRUD + category breakdown
    │       ├── people_repository.dart           # borrowed/lent CRUD + settle logic
    │       ├── account_category_repository.dart # accounts + categories CRUD
    │       ├── home_totals_repository.dart      # Home tab aggregation rules (see below)
    │       └── sync_service.dart                # outbox push + LWW pull sync engine
    ├── providers/
    │   └── app_providers.dart      # Riverpod wiring: DB, repos, auth state, selected date/month
    ├── screens/
    │   ├── app_root.dart           # switches Login <-> 3-tab bottom nav shell
    │   ├── auth/
    │   │   └── login_screen.dart   # email/password + Google sign-in
    │   ├── home/                   # 1st bottom nav ("Trans.")
    │   │   ├── home_screen.dart    # top TabBar: Calendar | Monthly | Yearly | Total | People
    │   │   ├── calendar_tab.dart   # month grid, tap = add entry, long-press = day detail
    │   │   ├── monthly_tab.dart    # month-by-month list (matches reference screenshot)
    │   │   ├── yearly_tab.dart     # ONLY yearly-marked expenses, month-wise + pie chart
    │   │   ├── total_tab.dart      # budget setting + progress bar
    │   │   └── people_tab.dart     # this month's Borrowed/Lent, multi-select settle
    │   ├── statistics/
    │   │   └── statistics_screen.dart   # 2nd bottom nav — weekly/monthly/annual, INCLUDES yearly-marked
    │   └── accounts/
    │       └── accounts_screen.dart     # 3rd bottom nav — assets/liabilities by account type
    └── widgets/
        ├── add_transaction_modal.dart   # 3-way toggle Expense/Income/People + yearly checkbox
        ├── day_detail_sheet.dart        # long-press day view, per-entry delete
        └── category_pie_chart.dart      # shared fl_chart pie + legend
```

## Where the yearly-marked / statistics logic lives

This was the trickiest business rule, so it's centralized rather than
scattered across screens:

- `AppDatabase.transactionsBetween(includeYearly: false)` — used by every
  Home tab (Calendar, Monthly, Total). Yearly-marked rows never appear.
- `AppDatabase.yearlyMarkedTransactionsBetween(...)` — used **only** by
  the Home → Yearly tab. It is the opposite filter: *only* yearly-marked
  rows. Regular transactions never leak into this tab.
- `TransactionRepository.statsTransactionsBetween(...)` — used only by
  the Statistics screen. No filter — everything counts, including
  yearly-marked rows.
- `HomeTotalsRepository` — combines transactions with **settled**
  People (Borrowed/Lent) entries. A settled entry's signed delta
  (borrowed: +amount, lent: −amount) is folded into that month's expense
  figure based on `settledAt`, without mutating or duplicating the
  original People row (it stays visible, just faded, per your spec).

## Setup

1. **Supabase**: create a project, run `supabase/schema.sql` in the SQL
   editor. Enable Email and Google providers under
   Authentication → Providers. Add your redirect URL there too.
2. Fill in `lib/core/constants.dart` → `SupabaseConfig.url` / `anonKey`.
3. **Android deep link** (for Google sign-in): in
   `android/app/src/main/AndroidManifest.xml`, inside the main
   `<activity>`, add:
   ```xml
   <intent-filter>
     <action android:name="android.intent.action.VIEW" />
     <category android:name="android.intent.category.DEFAULT" />
     <category android:name="android.intent.category.BROWSABLE" />
     <data android:scheme="io.supabase.expensetracker" />
   </intent-filter>
   ```
4. `flutter pub get`
5. `flutter pub run build_runner build --delete-conflicting-outputs`
   (generates `app_database.g.dart` from the Drift schema)
6. `flutter run -d chrome` (web) or `flutter run` (Android device/emulator)

## What's implemented vs. what's next

**Implemented**: full offline-first read/write for transactions,
accounts, categories, people (borrowed/lent) and budgets via Drift;
push/pull sync engine; all 3 bottom-nav screens with the 5 Home
sub-tabs; the 3-way add-entry modal; day long-press detail view;
People settle flow; category pie charts; budget progress bar.

**Intentionally stubbed / next steps**:
- Category editing screen (add/rename/delete/reorder icons) — the
  repository methods exist (`CategoryRepository`), just needs a settings
  UI similar to your reference screenshot.
- Excel export button on the Total tab (repo layer would need a `csv`/
  `excel` package wired in).
- SMS-based UPI auto-entry via NLP — explicitly out of scope for now,
  kept for later; account/category schema already supports whatever
  fields it would need to populate.
- Google Sign-In on Web needs your OAuth client ID registered in the
  Supabase dashboard (Android just needs the deep link above).
- Sync conflict resolution is last-write-wins by `updated_at`. Fine for
  a single user across devices; if you ever add multi-user sharing,
  revisit this.
