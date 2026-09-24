import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/local/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_providers.dart';
import '../categories/category_management_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _busy = false;

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.expense : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast('Something went wrong: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
        final result = await ref.read(backupServiceProvider).pickAndImport();
        if (result == null) return; // user cancelled the picker
        if (result.errors.isNotEmpty && result.imported == 0) {
          _toast(result.errors.first, isError: true);
        } else {
          _toast('Import complete — ${result.summary}');
        }
      });

  Future<void> _exportJson() => _run(() async {
        await ref.read(backupServiceProvider).exportJson();
        _toast('Backup saved as JSON.');
      });

  Future<void> _exportCsv() => _run(() async {
        await ref.read(backupServiceProvider).exportCsv();
        _toast('Transactions saved as CSV.');
      });

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
          'This permanently deletes every transaction, borrowed/lent entry, '
          'budget and category on this device. It cannot be undone.\n\n'
          'Export a backup first if you might want this data later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase everything', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final db = ref.read(appDatabaseProvider);
      await db.eraseAllData();
      // Re-seed so the app isn't left with no categories or accounts,
      // which would make it impossible to add a transaction.
      await db.seedDefaultsIfEmpty();
      _toast('All data erased. Defaults restored.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text('Import / Export', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Bring in a CSV backup or back up your data.',
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 24),

                // ---- Import ----
                _Card(
                  title: 'Import Transactions',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Import a CSV or JSON file of transactions — for example, the one you '
                        'exported from your previous data. Expected columns: date, description, '
                        'category, subcategory, type, amount. Unknown categories are created '
                        'automatically.',
                        style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      _WideButton(label: 'Choose file to import', onPressed: _busy ? null : _import),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Export ----
                _Card(
                  title: 'Export / Backup',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Download all your data as a backup, or to move it to another device. '
                        'JSON keeps everything (accounts, categories, people entries, budgets); '
                        'CSV holds just your transactions for use in a spreadsheet.',
                        style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: _WideButton(label: 'Export as JSON', onPressed: _busy ? null : _exportJson)),
                          const SizedBox(width: 12),
                          Expanded(child: _WideButton(label: 'Export as CSV', onPressed: _busy ? null : _exportCsv)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Categories shortcut ----
                _Card(
                  title: 'Categories',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Rename, re-icon, reorder or remove your expense and income categories.',
                        style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _WideButton(
                              label: 'Expense categories',
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const CategoryManagementScreen(kind: 'expense'),
                              )),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _WideButton(
                              label: 'Income categories',
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const CategoryManagementScreen(kind: 'income'),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Recurring transactions ----
                _RecurringCard(),
                const SizedBox(height: 16),

                // ---- Danger zone ----
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.expense.withOpacity(0.8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Danger Zone', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text(
                        'This permanently erases every transaction and category stored on this device.',
                        style: TextStyle(color: AppColors.expense, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _eraseAll,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.expense),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Erase all data',
                            style: TextStyle(color: AppColors.expense, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'All your data stays on this device. Nothing is sent anywhere.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('$kAppName · v1.0.0', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _WideButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white.withOpacity(0.03),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Lists every recurring series that still has occurrences ahead of it,
/// with a "Stop" action that cancels everything from today onward while
/// leaving whatever it already created in place.
class _RecurringCard extends ConsumerWidget {
  const _RecurringCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final seriesAsync = ref.watch(_activeRecurringProvider);

    return _Card(
      title: 'Recurring Transactions',
      child: seriesAsync.when(
        data: (series) {
          if (series.isEmpty) {
            return const Text(
              'Nothing repeating right now. Turn on the repeat icon while adding an '
              'expense or income to schedule one.',
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.45),
            );
          }
          final categories = categoriesAsync.value ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in series) ...[
                _RecurringRow(info: s, categories: categories),
                if (s != series.last) const Divider(height: 20, color: Colors.white10),
              ],
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.expense)),
      ),
    );
  }
}

final _activeRecurringProvider = StreamProvider<List<RecurringSeriesInfo>>(
  (ref) => ref.watch(transactionRepoProvider).watchActiveRecurringSeries(),
);

class _RecurringRow extends ConsumerWidget {
  final RecurringSeriesInfo info;
  final List<Category> categories;
  const _RecurringRow({required this.info, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = info.categoryId == null ? const <Category>[] : categories.where((c) => c.id == info.categoryId).toList();
    final cat = matches.isEmpty ? null : matches.first;
    final isExpense = info.type == 'expense';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(cat?.icon ?? (isExpense ? '💸' : '➕'), style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.remark.isEmpty ? (cat?.name ?? (isExpense ? 'Expense' : 'Income')) : info.remark,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                'Every ${info.frequency.substring(0, info.frequency.length - 2)} · next ${DateFormat('d MMM').format(info.nextDate)} '
                '· ${info.remainingCount} left of ${info.totalCount}',
                style: const TextStyle(color: Colors.grey, fontSize: 11.5),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$kCurrencySymbol${info.amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isExpense ? AppColors.expense : AppColors.incomeGreen,
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Stop this series?'),
                    content: Text(
                      'This cancels the ${info.remainingCount} occurrence${info.remainingCount == 1 ? '' : 's'} '
                      'still ahead. What already happened stays in your ledger.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Stop', style: TextStyle(color: AppColors.expense)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final cancelled = await ref.read(transactionRepoProvider).stopRecurring(info.groupId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Stopped — $cancelled upcoming occurrence${cancelled == 1 ? '' : 's'} cancelled.')),
                    );
                  }
                }
              },
              child: const Text('Stop', style: TextStyle(color: AppColors.expense, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }
}
