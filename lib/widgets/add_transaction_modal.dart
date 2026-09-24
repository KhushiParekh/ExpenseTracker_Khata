import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../data/local/app_database.dart';
import '../providers/app_providers.dart';
import '../screens/categories/category_management_screen.dart';

const _uuid = Uuid();

Future<void> showAddTransactionModal(BuildContext context, WidgetRef ref, DateTime initialDate) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => AddTransactionSheet(initialDate: initialDate),
  );
}

Future<void> showEditTransactionModal(BuildContext context, WidgetRef ref, Transaction existing) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => AddTransactionSheet(initialDate: existing.txnDate, existing: existing),
  );
}

enum _ActiveField { amount, category, account, remark, person, none }

class AddTransactionSheet extends ConsumerStatefulWidget {
  final DateTime initialDate;
  final Transaction? existing;
  const AddTransactionSheet({super.key, required this.initialDate, this.existing});

  @override
  ConsumerState<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  // Every fixed dimension in the sheet is derived from these, so changing
  // one number rescales the whole modal consistently.
  static const double _fieldHeight = 50;
  static const double _panelHeight = 248;
  static const double _gap = 12;

  EntryKind _kind = EntryKind.expense;
  PeopleType _peopleType = PeopleType.borrowed;
  _ActiveField _activeField = _ActiveField.amount;

  final _amountCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _personCtrl = TextEditingController();

  String? _accountId;
  String? _categoryId;

  /// "Count as a yearly expense" — these are deliberately kept OUT of the
  /// monthly figures (Calendar / Monthly / Total), and surface only in the
  /// Yearly tab and the Statistics screen. Meant for lumpy, once-in-a-while
  /// spends like shoes, a course fee, or annual insurance.
  bool _isYearly = false;

  bool _isRecurring = false;
  String _recurringFrequency = 'monthly'; // weekly | monthly | annually
  int _recurringCount = 12; // used unless _recurringEndDate is set
  DateTime? _recurringEndDate; // when set, overrides _recurringCount

  bool _accountDefaultApplied = false;
  late DateTime _date;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    final existing = widget.existing;
    if (existing != null) {
      _kind = existing.type == 'income' ? EntryKind.income : EntryKind.expense;
      _amountCtrl.text = existing.amount.toStringAsFixed(existing.amount.truncateToDouble() == existing.amount ? 0 : 2);
      _remarkCtrl.text = existing.remark;
      _accountId = existing.accountId;
      _categoryId = existing.categoryId;
      _isYearly = existing.isYearly;
      _accountDefaultApplied = true;
      _activeField = _ActiveField.none;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _remarkCtrl.dispose();
    _personCtrl.dispose();
    super.dispose();
  }

  void _onNumpadKeyPress(String key) {
    String text = _amountCtrl.text;
    if (key == 'BACKSPACE') {
      if (text.isNotEmpty) _amountCtrl.text = text.substring(0, text.length - 1);
    } else if (key == 'CLEAR') {
      _amountCtrl.clear();
    } else if (key == '.') {
      if (!text.contains('.')) _amountCtrl.text = text.isEmpty ? '0.' : '$text.';
    } else {
      _amountCtrl.text = text == '0' ? key : text + key;
    }
    setState(() {});
  }

  DateTime _recurringOccurrence(DateTime start, String frequency, int i) {
    if (frequency == 'weekly') return start.add(Duration(days: 7 * i));
    if (frequency == 'annually') return DateTime(start.year + i, start.month, start.day, start.hour, start.minute);
    // monthly
    final year = start.year + ((start.month - 1 + i) ~/ 12);
    final month = ((start.month - 1 + i) % 12) + 1;
    var day = start.day;
    final maxDays = DateUtils.getDaysInMonth(year, month);
    if (day > maxDays) day = maxDays;
    return DateTime(year, month, day, start.hour, start.minute);
  }

  /// Builds every date in the series: either a fixed number of occurrences,
  /// or every occurrence up to (and including) an end date — whichever the
  /// user chose in the "Repeat range" dialog.
  List<DateTime> _generateRecurringDates(DateTime start, String frequency) {
    final dates = <DateTime>[];
    final endDate = _recurringEndDate;
    if (endDate != null) {
      // Safety cap so a mistaken far-future end date can't hang the app
      // or flood the ledger with thousands of rows.
      for (int i = 0; i < 500; i++) {
        final d = _recurringOccurrence(start, frequency, i);
        if (d.isAfter(endDate)) break;
        dates.add(d);
      }
    } else {
      for (int i = 0; i < _recurringCount; i++) {
        dates.add(_recurringOccurrence(start, frequency, i));
      }
    }
    return dates;
  }

  String get _recurringRangeLabel {
    if (_recurringEndDate != null) {
      return 'until ${_recurringEndDate!.day}/${_recurringEndDate!.month}/${_recurringEndDate!.year}';
    }
    return '$_recurringCount time${_recurringCount == 1 ? '' : 's'}';
  }

  /// Lets the person pick how far a recurring series should run — either
  /// a fixed number of occurrences, or up to a chosen end date.
  Future<void> _configureRecurringRange() async {
    int tempCount = _recurringCount;
    DateTime? tempEnd = _recurringEndDate;
    bool useEndDate = tempEnd != null;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Repeat range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: false,
                groupValue: useEndDate,
                title: const Text('Number of occurrences'),
                onChanged: (v) => setDialogState(() => useEndDate = false),
              ),
              if (!useEndDate)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setDialogState(() => tempCount = (tempCount - 1).clamp(2, 120)),
                      ),
                      Text('$tempCount time${tempCount == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setDialogState(() => tempCount = (tempCount + 1).clamp(2, 120)),
                      ),
                    ],
                  ),
                ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                groupValue: useEndDate,
                title: const Text('Until a date'),
                onChanged: (v) async {
                  final picked = await showDatePicker(
                    context: dialogCtx,
                    initialDate: tempEnd ?? _date.add(const Duration(days: 90)),
                    firstDate: _date,
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() {
                    tempEnd = picked;
                    useEndDate = true;
                  });
                },
              ),
              if (useEndDate)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    tempEnd == null ? 'Pick a date above' : 'Ends ${tempEnd!.day}/${tempEnd!.month}/${tempEnd!.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(
              onPressed: (useEndDate && tempEnd == null)
                  ? null
                  : () {
                      setState(() {
                        if (useEndDate) {
                          _recurringEndDate = tempEnd;
                        } else {
                          _recurringCount = tempCount;
                          _recurringEndDate = null;
                        }
                      });
                      Navigator.pop(dialogCtx);
                    },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    if (_kind == EntryKind.people) {
      await ref.read(peopleRepoProvider).addEntry(
            type: _peopleType == PeopleType.borrowed ? 'borrowed' : 'lent',
            amount: amount,
            date: _date,
            personName: _personCtrl.text.trim(),
            accountId: _accountId,
            remark: _remarkCtrl.text.trim(),
          );
    } else if (_isEditing) {
      await ref.read(transactionRepoProvider).updateTransaction(
            widget.existing!,
            type: _kind == EntryKind.expense ? 'expense' : 'income',
            amount: amount,
            date: _date,
            accountId: _accountId,
            categoryId: _categoryId,
            remark: _remarkCtrl.text.trim(),
            isYearly: _kind == EntryKind.expense && _isYearly,
          );
    } else {
      final repo = ref.read(transactionRepoProvider);
      final type = _kind == EntryKind.expense ? 'expense' : 'income';
      final yearly = _kind == EntryKind.expense && _isYearly;

      final dates = _isRecurring ? _generateRecurringDates(_date, _recurringFrequency) : [_date];
      final groupId = _isRecurring && dates.length > 1 ? _uuid.v4() : null;
      for (final targetDate in dates) {
        await repo.addTransaction(
          type: type,
          amount: amount,
          date: targetDate,
          accountId: _accountId,
          categoryId: _categoryId,
          remark: _remarkCtrl.text.trim(),
          isYearly: yearly,
          recurringGroupId: groupId,
        );
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(transactionRepoProvider).deleteTransaction(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // A draggable sheet gives the taller default height asked for, while
    // still letting the user pull it up or down.
return SafeArea(
  top: false,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 10),

      Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade600,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),

      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
                  if (!_isEditing) ...[
                    _KindToggle(
                      kind: _kind,
                      onChanged: (k) => setState(() {
                        _kind = k;
                        if (k != EntryKind.expense) _isYearly = false;
                      }),
                    ),
                    const SizedBox(height: _gap + 4),
                  ],

                  if (_kind == EntryKind.people) ...[
                    _PeopleTypeToggle(type: _peopleType, onChanged: (t) => setState(() => _peopleType = t)),
                    const SizedBox(height: _gap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: _fieldHeight,
                            child: TextField(
                              controller: _personCtrl,
                              readOnly: true, // custom in-sheet keyboard instead of the OS one
                              decoration: InputDecoration(
                                labelText: 'Person name',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                suffixIcon: _activeField == _ActiveField.person
                                    ? const Icon(Icons.keyboard, size: 18, color: AppColors.accent)
                                    : null,
                              ),
                              onTap: () => setState(() => _activeField = _ActiveField.person),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: _fieldHeight,
                            child: TextField(
                              controller: _remarkCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Remark',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                suffixIcon: _activeField == _ActiveField.remark
                                    ? const Icon(Icons.keyboard, size: 18, color: AppColors.accent)
                                    : null,
                              ),
                              onTap: () => setState(() => _activeField = _ActiveField.remark),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _gap),
                  ],

                  // ---- Amount + Account, equal width and height ----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _amountBox()),
                      const SizedBox(width: 12),
                      Expanded(child: _accountBox()),
                    ],
                  ),
                  const SizedBox(height: _gap),

                  // ---- Category + Remark, equal width and height ----
                              if (_kind != EntryKind.people) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _categoryBox()),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: _fieldHeight+3,
                                        child: TextField(
                                          controller: _remarkCtrl,
                                          readOnly: true,
                                          decoration: InputDecoration(
                                            labelText: 'Remark',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            suffixIcon: _activeField == _ActiveField.remark
                                                ? const Icon(
                                                    Icons.keyboard,
                                                    size: 18,
                                                    color: AppColors.accent,
                                                  )
                                                : null,
                                          ),
                                          onTap: () => setState(
                                            () => _activeField = _ActiveField.remark,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: _gap),
                              ],
                  // ---- Date + recurring ----
                  Container(
                    height: _fieldHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade700),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              setState(() => _activeField = _ActiveField.none);
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _date = picked);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Date', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 3),
                                Text(
                                  '${_date.day}/${_date.month}/${_date.year}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Icon(Icons.calendar_today, size: 17, color: Colors.grey),
                        if (_kind != EntryKind.people) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            tooltip: 'Repeat this entry',
                            icon: Icon(Icons.repeat_rounded, color: _isRecurring ? AppColors.accent : Colors.grey, size: 21),
                            onSelected: (value) {
                              if (value == 'none') {
                                setState(() {
                                  _isRecurring = false;
                                  _recurringEndDate = null;
                                });
                              } else {
                                setState(() {
                                  _isRecurring = true;
                                  _recurringFrequency = value;
                                });
                                _configureRecurringRange();
                              }
                            },
                            itemBuilder: (_) => [
                              _repeatItem('none', 'No repeat', !_isRecurring),
                              _repeatItem('weekly', 'Weekly', _isRecurring && _recurringFrequency == 'weekly'),
                              _repeatItem('monthly', 'Monthly', _isRecurring && _recurringFrequency == 'monthly'),
                              _repeatItem('annually', 'Annually', _isRecurring && _recurringFrequency == 'annually'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ---- Recurring range summary ----
                  if (_isRecurring) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _configureRecurringRange,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_repeat, size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text(
                              'Repeats $_recurringFrequency, $_recurringRangeLabel',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit, size: 12, color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                  ],


                  // ---- Input panel (numpad / category grid / account list / keyboard) ----
                  if (_activeField != _ActiveField.none) ...[
                    const SizedBox(height: _gap),
                    SizedBox(height: _panelHeight, child: _getPanelWidget()),
                  ],
                  // ---- Yearly expense flag ----
                  if (_kind == EntryKind.expense) ...[
                    const SizedBox(height: _gap),
                    InkWell(
                      onTap: () => setState(() => _isYearly = !_isYearly),
                      borderRadius: BorderRadius.circular(8),
                      
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _isYearly,
                                onChanged: (v) => setState(() => _isYearly = v ?? false),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Mark as yearly expense', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 3),
                                  Text(
                                    'Excluded from monthly totals.Visible in Yearly & Statistics tabs.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      
                    ),
                  ],

                  const SizedBox(height: _gap ),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _kind == EntryKind.income ? AppColors.incomeGreen : const Color(0xFFFF5A52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      child: Text(
                        _isEditing ? 'Save changes' : 'Save',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline, color: AppColors.expense),
                        label: const Text('Delete', style: TextStyle(color: AppColors.expense)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

      ],

    )
);
}

  PopupMenuItem<String> _repeatItem(String value, String label, bool selected) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(Icons.check, size: 16, color: selected ? AppColors.accent : Colors.transparent),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _fieldBox({
    required String label,
    required String value,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: _fieldHeight,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? AppColors.accent : Colors.grey.shade700,
            width: active ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            // ---- Floating label ----
            Positioned(
              left: 0,
              top: -1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: AppColors.surface,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: active ? AppColors.accent : Colors.grey,
                    height: 1.1,
                  ),
                ),
              ),
            ),

            // ---- Value ----
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountBox() {
    final raw = _amountCtrl.text.isEmpty ? '0' : _amountCtrl.text;

    return _fieldBox(
      label: 'Amount',
      value: '$kCurrencySymbol $raw',
      active: _activeField == _ActiveField.amount,
      onTap: () => setState(() {
        _activeField = _activeField == _ActiveField.amount
            ? _ActiveField.none
            : _ActiveField.amount;
      }),
    );
  }

  Widget _accountBox() {
    return Consumer(builder: (context, ref, _) {
      final accountsAsync = ref.watch(allAccountsProvider);
      return accountsAsync.when(
        data: (accs) {
          final usable = accs.where((a) => !a.archived).toList();
          if (!_accountDefaultApplied && usable.isNotEmpty) {
            _accountDefaultApplied = true;
            final upi = usable.where((a) => a.type == 'upi');
            final defaultAcc = upi.isNotEmpty ? upi.first : usable.first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _accountId = defaultAcc.id);
            });
          }
          final selected = usable.where((a) => a.id == _accountId);
          return _fieldBox(
            label: 'Account',
            value: selected.isNotEmpty ? selected.first.name : 'Select',
            active: _activeField == _ActiveField.account,
            onTap: () => setState(() {
              _activeField = _activeField == _ActiveField.account
                  ? _ActiveField.none
                  : _ActiveField.account;
            }),
          );
        },
        loading: () => SizedBox(height: _fieldHeight, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => SizedBox(height: _fieldHeight, child: Text('$e', style: const TextStyle(fontSize: 11))),
      );
    });
  }

  Widget _categoryBox() {
    return Consumer(builder: (context, ref, _) {
      final categoriesAsync = ref.watch(_categoriesForKindProvider(_kind == EntryKind.income ? 'income' : 'expense'));
      return categoriesAsync.when(
        data: (cats) {
          final selected = cats.where((c) => c.id == _categoryId);
          return _fieldBox(
            label: 'Category',
            value: selected.isNotEmpty
                ? '${selected.first.icon}  ${selected.first.name}'
                : 'Select category',
            active: _activeField == _ActiveField.category,
            onTap: () => setState(() {
              _activeField = _activeField == _ActiveField.category
                  ? _ActiveField.none
                  : _ActiveField.category;
            }),
          );
        },
        loading: () => SizedBox(height: _fieldHeight, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => SizedBox(height: _fieldHeight, child: Text('$e', style: const TextStyle(fontSize: 11))),
      );
    });
  }

  Widget _getPanelWidget() {
    switch (_activeField) {
      case _ActiveField.amount:
        return _CustomNumpad(onKeyPress: _onNumpadKeyPress);
      case _ActiveField.category:
        return _categoryPanel();
      case _ActiveField.account:
        return _accountPanel();
      case _ActiveField.remark:
        return _CustomTextKeyboard(controller: _remarkCtrl, onChanged: () => setState(() {}));
      case _ActiveField.person:
        return _CustomTextKeyboard(controller: _personCtrl, onChanged: () => setState(() {}));
      case _ActiveField.none:
        return const SizedBox.shrink();
    }
  }

  Widget _panelHeader(String title, {VoidCallback? onEdit}) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: 'Manage categories',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _activeField = _ActiveField.none),
        ),
      ],
    );
  }

  Widget _categoryPanel() {
    return Consumer(builder: (context, ref, _) {
      final kindStr = _kind == EntryKind.income ? 'income' : 'expense';
      final categoriesAsync = ref.watch(_categoriesForKindProvider(kindStr));
      return categoriesAsync.when(
        data: (cats) => Column(
          children: [
            _panelHeader(
              'Category',
              onEdit: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CategoryManagementScreen(kind: kindStr)),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: cats.length,
                itemBuilder: (context, i) {
                  final c = cats[i];
                  final selected = c.id == _categoryId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() {
                      _categoryId = c.id;
                      _activeField = _ActiveField.none;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: selected ? Border.all(color: AppColors.accent) : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(c.icon, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('$e'),
      );
    });
  }

  Widget _accountPanel() {
    return Consumer(builder: (context, ref, _) {
      final accountsAsync = ref.watch(allAccountsProvider);
      return accountsAsync.when(
        data: (all) {
          final accs = all.where((a) => !a.archived).toList();
          return Column(
            children: [
              _panelHeader('Account'),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: accs.length,
                  itemBuilder: (context, i) {
                    final a = accs[i];
                    final selected = a.id == _accountId;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(a.name, style: const TextStyle(fontSize: 13.5)),
                      trailing: selected ? const Icon(Icons.check, color: AppColors.accent, size: 18) : null,
                      onTap: () => setState(() {
                        _accountId = a.id;
                        _activeField = _ActiveField.none;
                      }),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('$e'),
      );
    });
  }
}

class _CustomTextKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _CustomTextKeyboard({required this.controller, required this.onChanged});

  @override
  State<_CustomTextKeyboard> createState() => _CustomTextKeyboardState();
}

class _CustomTextKeyboardState extends State<_CustomTextKeyboard> {
  bool _shift = false;

  void _onKeyTap(String value) {
    final c = widget.controller;
    if (value == 'BACKSPACE') {
      if (c.text.isNotEmpty) c.text = c.text.substring(0, c.text.length - 1);
    } else if (value == 'SHIFT') {
      setState(() => _shift = !_shift);
      return;
    } else {
      c.text += _shift ? value.toUpperCase() : value;
      if (_shift) setState(() => _shift = false);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['SHIFT', 'z', 'x', 'c', 'v', 'b', 'n', 'm', 'BACKSPACE'],
      ['SPACE'],
    ];

    return Column(
      children: rows.map((row) {
        return Expanded(
          child: Row(
            children: row.map((key) {
              final isSpace = key == 'SPACE';
              final isBackspace = key == 'BACKSPACE';
              final isShift = key == 'SHIFT';
              return Expanded(
                flex: isSpace ? 6 : (isBackspace || isShift ? 2 : 1),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: Material(
                    color: isShift && _shift ? AppColors.accent.withOpacity(0.3) : const Color(0xFF2B2D3A),
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: () => _onKeyTap(isSpace ? ' ' : key),
                      child: Center(
                        child: isBackspace
                            ? const Icon(Icons.backspace_outlined, size: 16, color: Colors.white)
                            : isShift
                                ? Icon(Icons.arrow_upward, size: 16, color: _shift ? AppColors.accent : Colors.white)
                                : Text(
                                    isSpace ? 'Space' : (_shift ? key.toUpperCase() : key),
                                    style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _CustomNumpad extends StatelessWidget {
  final ValueChanged<String> onKeyPress;
  const _CustomNumpad({required this.onKeyPress});

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'BACKSPACE'],
    ];

    return Column(
      children: keys.map((row) {
        return Expanded(
          child: Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3.5),
                  child: Material(
                    color: const Color(0xFF2B2D3A),
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onKeyPress(key),
                      child: Center(
                        child: key == 'BACKSPACE'
                            ? const Icon(Icons.backspace_outlined, size: 19, color: Colors.white)
                            : Text(key, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KindToggle extends StatelessWidget {
  final EntryKind kind;
  final ValueChanged<EntryKind> onChanged;
  const _KindToggle({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, EntryKind k, Color color) {
      final selected = kind == k;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(k),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.18) : Colors.transparent,
              border: Border.all(color: selected ? color : Colors.grey.shade700),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: selected ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      seg('Expense', EntryKind.expense, AppColors.expense),
      const SizedBox(width: 9),
      seg('Income', EntryKind.income, AppColors.incomeGreen),
      const SizedBox(width: 9),
      seg('People', EntryKind.people, AppColors.borrowedLent),
    ]);
  }
}

class _PeopleTypeToggle extends StatelessWidget {
  final PeopleType type;
  final ValueChanged<PeopleType> onChanged;
  const _PeopleTypeToggle({required this.type, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PeopleType>(
      segments: const [
        ButtonSegment(value: PeopleType.borrowed, label: Text('Borrowed (+)')),
        ButtonSegment(value: PeopleType.lent, label: Text('Lent (-)')),
      ],
      selected: {type},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

final _categoriesForKindProvider = StreamProvider.family<List<Category>, String>(
  (ref, kind) => ref.watch(categoryRepoProvider).watchByKind(kind),
);
