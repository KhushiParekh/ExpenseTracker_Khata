import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/local/app_database.dart';
import '../../providers/app_providers.dart';
import '../../widgets/add_transaction_modal.dart';

/// Searches every transaction in the ledger — not just the month currently
/// on screen — matching against remark, amount, category name, account
/// name, type and date. Tapping a result opens it for editing.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  // Optional filters, so a broad text match can be narrowed down.
  String _typeFilter = 'all'; // all | expense | income
  bool _yearlyOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(allTransactionsProvider);
    final catsAsync = ref.watch(allCategoriesProvider);
    final accsAsync = ref.watch(allAccountsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search amount, note, category, account…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ---- Filter chips ----
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _chip('All', _typeFilter == 'all', () => setState(() => _typeFilter = 'all')),
                const SizedBox(width: 8),
                _chip('Expense', _typeFilter == 'expense', () => setState(() => _typeFilter = 'expense')),
                const SizedBox(width: 8),
                _chip('Income', _typeFilter == 'income', () => setState(() => _typeFilter = 'income')),
                const SizedBox(width: 8),
                _chip('Yearly only', _yearlyOnly, () => setState(() => _yearlyOnly = !_yearlyOnly)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: txnsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (txns) {
                final cats = {for (final c in catsAsync.value ?? <Category>[]) c.id: c};
                final accs = {for (final a in accsAsync.value ?? <Account>[]) a.id: a};

                final results = txns.where((t) {
                  if (_typeFilter != 'all' && t.type != _typeFilter) return false;
                  if (_yearlyOnly && !t.isYearly) return false;
                  if (_query.isEmpty) return true;

                  final cat = t.categoryId == null ? null : cats[t.categoryId];
                  final acc = t.accountId == null ? null : accs[t.accountId];
                  // One haystack of every user-visible field, so a single
                  // query box can match any of them.
                  final haystack = [
                    t.remark,
                    t.amount.toStringAsFixed(2),
                    t.amount.toStringAsFixed(0),
                    t.type,
                    cat?.name ?? '',
                    acc?.name ?? '',
                    DateFormat('d MMM yyyy').format(t.txnDate),
                    DateFormat('dd/MM/yyyy').format(t.txnDate),
                    t.isYearly ? 'yearly' : '',
                  ].join(' ').toLowerCase();

                  return haystack.contains(_query);
                }).toList();

                if (results.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.isEmpty ? 'Start typing to search your transactions.' : 'No transactions match "$_query".',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final matchedTotal = results.fold(0.0, (sum, t) => sum + (t.type == 'expense' ? t.amount : -t.amount));

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${results.length} result${results.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            'Net $kCurrencySymbol${matchedTotal.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: matchedTotal >= 0 ? AppColors.expense : AppColors.incomeGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = results[i];
                          final cat = t.categoryId == null ? null : cats[t.categoryId];
                          final acc = t.accountId == null ? null : accs[t.accountId];
                          final isIncome = t.type == 'income';
                          final color = isIncome ? AppColors.incomeGreen : AppColors.expense;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withOpacity(0.15),
                              child: Text(cat?.icon ?? (isIncome ? '➕' : '💸'), style: const TextStyle(fontSize: 16)),
                            ),
                            title: Text(
                              t.remark.isEmpty ? (cat?.name ?? (isIncome ? 'Income' : 'Expense')) : t.remark,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                DateFormat('d MMM yyyy').format(t.txnDate),
                                if (cat != null) cat.name,
                                if (acc != null) acc.name,
                                if (t.isYearly) 'Yearly',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '${isIncome ? '+' : '-'}$kCurrencySymbol${t.amount.toStringAsFixed(2)}',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold),
                            ),
                            onTap: () => showEditTransactionModal(context, ref, t),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.18) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? AppColors.accent : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
