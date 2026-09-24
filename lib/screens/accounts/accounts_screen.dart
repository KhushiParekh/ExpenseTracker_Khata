import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/account_category_repository.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsRepo = ref.watch(accountRepoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: StreamBuilder<List<Account>>(
        stream: accountsRepo.watchAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final accounts = snapshot.data!;
          final assets = accounts.where((a) => !a.isLiability).fold(0.0, (a, b) => a + b.balance);
          final liabilities = accounts.where((a) => a.isLiability).fold(0.0, (a, b) => a + b.balance);
          final net = assets - liabilities;

          final grouped = <String, List<Account>>{};
          for (final a in accounts) {
            grouped.putIfAbsent(_typeLabel(a.type), () => []).add(a);
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              // ---- Summary cards ----
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _SummaryCard(label: 'Assets', value: assets, color: AppColors.incomeGreen, icon: Icons.account_balance_wallet_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _SummaryCard(label: 'Liabilities', value: liabilities, color: AppColors.expense, icon: Icons.credit_card_outlined)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SummaryCard(
                      label: 'Net Worth',
                      value: net,
                      color: net >= 0 ? AppColors.incomeGreen : AppColors.expense,
                      icon: Icons.trending_up,
                      wide: true,
                    ),
                  ],
                ),
              ),

              // ---- Grouped account list ----
              if (accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No accounts yet — tap + to add one', style: TextStyle(color: Colors.grey))),
                ),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text(entry.key, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < entry.value.length; i++) ...[
                        _accountTile(context, ref, accountsRepo, entry.value[i]),
                        if (i < entry.value.length - 1) const Divider(height: 1, indent: 56, endIndent: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAccountDialog(context, ref),
        tooltip: 'Add account',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _accountTile(BuildContext context, WidgetRef ref, AccountRepository accountsRepo, Account a) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: (a.isLiability ? AppColors.expense : AppColors.accent).withOpacity(0.12),
        child: Icon(_typeIcon(a.type), size: 18, color: a.isLiability ? AppColors.expense : AppColors.accent),
      ),
      title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: a.isLiability ? const Text('Liability', style: TextStyle(fontSize: 11, color: Colors.grey)) : null,
      trailing: Text(
        '$kCurrencySymbol ${a.balance.toStringAsFixed(2)}',
        style: TextStyle(color: a.isLiability ? AppColors.expense : Colors.white, fontWeight: FontWeight.bold),
      ),
      onLongPress: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Archive ${a.name}?'),
            content: const Text('It will stop appearing in pickers, but its transaction history stays intact.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive')),
            ],
          ),
        );
        if (confirm == true) await accountsRepo.archive(a.id);
      },
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'card':
        return Icons.credit_card;
      case 'upi':
        return Icons.qr_code_scanner;
      default:
        return Icons.wallet_outlined;
    }
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

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool wide;

  const _SummaryCard({required this.label, required this.value, required this.color, required this.icon, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '$kCurrencySymbol${value.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return wide ? SizedBox(width: double.infinity, child: card) : card;
  }
}
