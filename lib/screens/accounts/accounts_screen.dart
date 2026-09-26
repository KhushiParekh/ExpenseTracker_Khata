import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/account_category_repository.dart';
import '../../widgets/ui_kit.dart';

/// Lifetime income vs expense volumes per account, purely for the small
/// colour indicator on each row (see _IncomeExpenseBars) — not a report,
/// so it's intentionally not date-scoped.
final _incomeExpenseByAccountProvider = StreamProvider<Map<String, ({double income, double expense})>>(
  (ref) => ref.watch(transactionRepoProvider).watchIncomeExpenseByAccount(),
);

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  // Display order + look of each account type.
  static const _types = <String, ({String label, IconData icon})>{
    'cash': (label: 'Cash', icon: Icons.payments_outlined),
    'bank': (label: 'Bank Accounts', icon: Icons.account_balance_outlined),
    'upi': (label: 'UPI', icon: Icons.qr_code_2_rounded),
    'card': (label: 'Cards', icon: Icons.credit_card_outlined),
    'other': (label: 'Others', icon: Icons.account_balance_wallet_outlined),
  };

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

          // Group by type, in the fixed display order above.
          final grouped = <String, List<Account>>{};
          for (final a in accounts) {
            final key = _types.containsKey(a.type) ? a.type : 'other';
            grouped.putIfAbsent(key, () => []).add(a);
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              // ---- Net balance hero ----
              AppCard(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                padding: const EdgeInsets.all(18),
                borderColor: (net >= 0 ? AppColors.incomeGreen : AppColors.expense).withOpacity(0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Net balance', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fmtMoney(net, decimals: true),
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: net >= 0 ? Colors.white : AppColors.expense),
                      ),
                    ),
                  ],
                ),
              ),
              TwoUp(
                left: StatCard(
                  label: 'Assets',
                  value: fmtMoney(assets),
                  color: AppColors.incomeGreen,
                  icon: Icons.trending_up_rounded,
                ),
                right: StatCard(
                  label: 'Liabilities',
                  value: fmtMoney(liabilities),
                  color: AppColors.expense,
                  icon: Icons.trending_down_rounded,
                ),
              ),

              if (accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No accounts yet.\nTap + to add your first one.'),
                ),

              // ---- Groups ----
              for (final entry in _types.entries)
                if (grouped[entry.key] != null) ...[
                  SectionTitle(
                    entry.value.label,
                    trailing: Text(
                      fmtMoney(grouped[entry.key]!.fold(0.0, (s, a) => s + (a.isLiability ? -a.balance : a.balance))),
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        for (int i = 0; i < grouped[entry.key]!.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 62, endIndent: 14),
                          _accountRow(context, ref, accountsRepo, grouped[entry.key]![i], entry.value.icon),
                        ],
                      ],
                    ),
                  ),
                ],
              if (accounts.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Long-press an account to archive it', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
            ],
          );
        },
      ),
      // Same placement and style as the FAB on the Transactions screen.
      floatingActionButton: FloatingActionButton(
        heroTag: 'accounts_fab', // unique tag: several FABs live in the same IndexedStack
        tooltip: 'Add account',
        onPressed: () => _showAddAccountSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _accountRow(BuildContext context, WidgetRef ref, AccountRepository accountsRepo, Account a, IconData icon) {
    final color = a.isLiability ? AppColors.expense : AppColors.incomeGreen;
    final ieMap = ref.watch(_incomeExpenseByAccountProvider).value ?? const {};
    final ie = ieMap[a.id];

    return InkWell(
      onLongPress: () => _confirmArchive(context, accountsRepo, a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  if (a.isLiability) ...[
                    const SizedBox(height: 3),
                    const MiniTag('LIABILITY', color: AppColors.expense),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fmtMoney(a.balance, decimals: true),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: a.isLiability ? AppColors.expense : Colors.white),
            ),
            const SizedBox(width: 10),
            _IncomeExpenseBars(income: ie?.income ?? 0, expense: ie?.expense ?? 0),
            PopupMenuButton<String>(
              tooltip: 'More',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
              onSelected: (_) => _confirmArchive(context, accountsRepo, a),
              itemBuilder: (_) => const [PopupMenuItem(value: 'archive', child: Text('Archive'))],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, AccountRepository accountsRepo, Account a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Archive ${a.name}?'),
        content: const Text('It will be hidden from the app. Existing transactions are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirm == true) await accountsRepo.archive(a.id);
  }

  Future<void> _showAddAccountSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => const _AddAccountSheet(),
    );
  }
}

/// Two thin bars stacked vertically — income on top, expense below —
/// whose widths encode the relative split between the two, next to the
/// kebab menu. Colour only, deliberately no numbers.
class _IncomeExpenseBars extends StatelessWidget {
  final double income;
  final double expense;
  const _IncomeExpenseBars({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color color, double value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(
              fmtMoney(value),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          row(Icons.arrow_upward_rounded, AppColors.incomeGreen, income),
          const SizedBox(height: 2),
          row(Icons.arrow_downward_rounded, AppColors.expense, expense),
        ],
      ),
    );
  }
}
class _AddAccountSheet extends ConsumerStatefulWidget {
  const _AddAccountSheet();

  @override
  ConsumerState<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends ConsumerState<_AddAccountSheet> {
  final _nameCtrl = TextEditingController();
  String _type = 'upi';
  bool _isLiability = false;
  bool _showError = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    await ref.read(accountRepoProvider).addAccount(name: name, type: _type, isLiability: _isLiability);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lift the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Add account', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_showError) setState(() => _showError = false);
                },
                decoration: InputDecoration(
                  labelText: 'Account name',
                  hintText: 'e.g. HDFC Savings',
                  border: const OutlineInputBorder(),
                  errorText: _showError ? 'Please enter a name' : null,
                ),
              ),
              const SizedBox(height: 18),
              const Text('Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in AccountsScreen._types.entries)
                    ChoiceChip(
                      avatar: Icon(t.value.icon, size: 17, color: _type == t.key ? AppColors.accent : Colors.grey),
                      label: Text(t.key == 'bank' ? 'Bank' : (t.key == 'card' ? 'Card' : t.value.label)),
                      selected: _type == t.key,
                      showCheckmark: false,
                      selectedColor: AppColors.accent.withOpacity(0.18),
                      side: BorderSide(color: _type == t.key ? AppColors.accent : Colors.grey.shade700),
                      onSelected: (_) => setState(() => _type = t.key),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isLiability,
                title: const Text('This is a liability', style: TextStyle(fontSize: 14.5)),
                subtitle: const Text('e.g. a credit card — spending increases what you owe', style: TextStyle(fontSize: 11.5)),
                onChanged: (v) => setState(() => _isLiability = v),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))),
                  onPressed: _save,
                  child: const Text('Add account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}