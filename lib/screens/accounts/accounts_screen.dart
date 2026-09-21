import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsRepo = ref.watch(accountRepoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddAccountDialog(context, ref))],
      ),
      body: StreamBuilder<List<Account>>(
        stream: accountsRepo.watchAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final accounts = snapshot.data!;
          final assets = accounts.where((a) => !a.isLiability).fold(0.0, (a, b) => a + b.balance);
          final liabilities = accounts.where((a) => a.isLiability).fold(0.0, (a, b) => a + b.balance);

          final grouped = <String, List<Account>>{};
          for (final a in accounts) {
            grouped.putIfAbsent(_typeLabel(a.type), () => []).add(a);
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summary('Assets', assets, AppColors.incomeGreen),
                    _summary('Liabilities', liabilities, AppColors.expense),
                    _summary('Total', assets - liabilities, Colors.white),
                  ],
                ),
              ),
              const Divider(),
              ...grouped.entries.map((entry) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(entry.key, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                      ...entry.value.map((a) => ListTile(
                            title: Text(a.name),
                            trailing: Text(
                              '$kCurrencySymbol ${a.balance.toStringAsFixed(2)}',
                              style: TextStyle(color: a.isLiability ? AppColors.expense : Colors.white, fontWeight: FontWeight.bold),
                            ),
                            onLongPress: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Text('Archive ${a.name}?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive')),
                                  ],
                                ),
                              );
                              if (confirm == true) await accountsRepo.archive(a.id);
                            },
                          )),
                    ],
                  )),
            ],
          );
        },
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'cash':
        return 'Cash';
      case 'bank':
        return 'Bank Accounts';
      case 'card':
        return 'Cards';
      case 'upi':
        return 'UPI';
      default:
        return 'Others';
    }
  }

  Widget _summary(String label, double value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value.toStringAsFixed(2), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      );

  Future<void> _showAddAccountDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    String type = 'upi';
    bool isLiability = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Account name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'cash'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isLiability,
                title: const Text('Is a liability (e.g. credit card)'),
                onChanged: (v) => setState(() => isLiability = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await ref.read(accountRepoProvider).addAccount(name: nameCtrl.text.trim(), type: type, isLiability: isLiability);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
