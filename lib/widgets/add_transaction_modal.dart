import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../data/local/app_database.dart';
import '../providers/app_providers.dart';
import '../screens/categories/category_management_screen.dart';
import '../screens/more/more_screen.dart';

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

/// Edits a People (borrowed/lent) entry. Shares AddTransactionSheet with
/// the normal expense/income flow since People already has its own mode
/// there — this just pre-fills it and routes Save to PeopleRepository.updateEntry.
Future<void> showEditPeopleEntryModal(BuildContext context, WidgetRef ref, PeopleEntry existing) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => AddTransactionSheet(initialDate: existing.entryDate, existingPeople: existing),
  );
}

enum _ActiveField { amount, category, account, remark, person, none }

/// How far a "repeat this entry" series reaches — set from the recurring
/// options sheet and used to both build the date list and label the entry.
const Map<String, int> _kRecurringMaxCount = {'weekly': 52, 'monthly': 36, 'annually': 15};
const Map<String, int> _kRecurringDefaultCount = {'weekly': 8, 'monthly': 12, 'annually': 5};

/// Generates the dates for a recurring series: [start], then [count - 1]
/// more spaced by [frequency]. Shared by the save flow and the "ends on"
/// preview in the recurring options sheet, so both always agree.
List<DateTime> generateRecurringDates(DateTime start, String frequency, {required int count}) {
  final dates = <DateTime>[];
  for (int i = 0; i < count; i++) {
    if (frequency == 'weekly') {
      dates.add(start.add(Duration(days: 7 * i)));
    } else if (frequency == 'monthly') {
      final year = start.year + ((start.month - 1 + i) ~/ 12);
      final month = ((start.month - 1 + i) % 12) + 1;
      var day = start.day;
      final maxDays = DateUtils.getDaysInMonth(year, month);
      if (day > maxDays) day = maxDays;
      dates.add(DateTime(year, month, day, start.hour, start.minute));
    } else if (frequency == 'annually') {
      dates.add(DateTime(start.year + i, start.month, start.day, start.hour, start.minute));
    }
  }
  return dates;
}

/// Given a fixed [frequency], finds the smallest occurrence count (>= 2,
/// clamped to that frequency's max) whose last generated date lands on or
/// after [target]. Used to translate a custom "ends on" date the user
/// picks in a calendar back into a count, since a series is still just N
/// evenly-spaced rows sharing one frequency — there's no way to store an
/// arbitrary off-cadence end date directly.
int _countForTargetEndDate(DateTime start, String frequency, DateTime target) {
  final maxCount = _kRecurringMaxCount[frequency]!;
  for (int c = 2; c <= maxCount; c++) {
    final last = generateRecurringDates(start, frequency, count: c).last;
    if (!last.isBefore(target)) return c;
  }
  return maxCount;
}

class AddTransactionSheet extends ConsumerStatefulWidget {
  final DateTime initialDate;
  final Transaction? existing;
  final PeopleEntry? existingPeople;
  const AddTransactionSheet({super.key, required this.initialDate, this.existing, this.existingPeople});

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
  /// monthly figures (Calendar / Monthly / Yearly / Total), and surface
  /// only in the Yearly tab and the Statistics screen. Meant for lumpy,
  /// once-in-a-while spends like shoes, a course fee, or annual insurance.
  bool _isYearly = false;

  bool _isRecurring = false;
  String _recurringFrequency = 'monthly'; // weekly | monthly | annually
  int _recurringCount = _kRecurringDefaultCount['monthly']!; // how many occurrences — the "range"

  bool _accountDefaultApplied = false;
  bool _saving = false;
  late DateTime _date;

  bool get _isEditingTxn => widget.existing != null;
  bool get _isEditingPeople => widget.existingPeople != null;
  bool get _isEditing => _isEditingTxn || _isEditingPeople;

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

    final existingPeople = widget.existingPeople;
    if (existingPeople != null) {
      _kind = EntryKind.people;
      _peopleType = existingPeople.type == 'borrowed' ? PeopleType.borrowed : PeopleType.lent;
      _amountCtrl.text =
          existingPeople.amount.toStringAsFixed(existingPeople.amount.truncateToDouble() == existingPeople.amount ? 0 : 2);
      _remarkCtrl.text = existingPeople.remark;
      _personCtrl.text = existingPeople.personName;
      _accountId = existingPeople.accountId;
      _accountDefaultApplied = true;
      _categoryId = existingPeople.categoryId;
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

  void _onKindChanged(EntryKind k) {
    setState(() {
      if (k != _kind) {
        // Income and expense have separate category lists, so a category
        // picked for one is meaningless for the other. People shares the
        // expense list, so switching to/from People also needs a reset.
        _categoryId = null;
      }
      _kind = k;
      if (k != EntryKind.expense) _isYearly = false;
      if (k == EntryKind.people) {
        _isRecurring = false;
      }
    });
  }
  // -------------------------------------------------------------------
  // Recurring options: frequency + how many times it repeats (the range).
  // -------------------------------------------------------------------
  Future<void> _openRecurringSheet() async {
    final result = await showModalBottomSheet<_RecurringChoice>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _RecurringOptionsSheet(
        startDate: _date,
        initialFrequency: _recurringFrequency,
        initialCount: _isRecurring ? _recurringCount : _kRecurringDefaultCount[_recurringFrequency]!,
        showStopOption: _isRecurring,
      ),
    );
    if (result == null) return; // dismissed without choosing
    setState(() {
      if (result.stop) {
        _isRecurring = false;
      } else {
        _isRecurring = true;
        _recurringFrequency = result.frequency;
        _recurringCount = result.count;
      }
    });
  }

  /// Opens a plain calendar so the person can pick the exact date the
  /// series should end on, instead of going back through the
  /// frequency/count sheet. The chosen date is translated to the nearest
  /// valid occurrence count for the current frequency (see
  /// [_countForTargetEndDate]).
  Future<void> _pickCustomEndDate() async {
    final currentLast = generateRecurringDates(_date, _recurringFrequency, count: _recurringCount).last;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentLast,
      firstDate: _date,
      lastDate: DateTime(2100),
      helpText: 'Choose when the series ends',
    );
    if (picked == null) return;
    setState(() {
      _isRecurring = true;
      _recurringCount = _countForTargetEndDate(_date, _recurringFrequency, picked);
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    setState(() => _saving = true);
    try {
      if (_kind == EntryKind.people) {
        if (_isEditingPeople) {
          await ref.read(peopleRepoProvider).updateEntry(
                widget.existingPeople!,
                type: _peopleType == PeopleType.borrowed ? 'borrowed' : 'lent',
                amount: amount,
                date: _date,
                personName: _personCtrl.text.trim(),
                accountId: _accountId,
                categoryId: _categoryId, // NEW
                remark: _remarkCtrl.text.trim(),
              );
        } else {
          await ref.read(peopleRepoProvider).addEntry(
                type: _peopleType == PeopleType.borrowed ? 'borrowed' : 'lent',
                amount: amount,
                date: _date,
                personName: _personCtrl.text.trim(),
                accountId: _accountId,
                categoryId: _categoryId, // NEW
                remark: _remarkCtrl.text.trim(),
              );
        }
      } else if (_isEditingTxn) {
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

        final dates = _isRecurring ? generateRecurringDates(_date, _recurringFrequency, count: _recurringCount) : [_date];
        // Every occurrence of one series shares a groupId so it can later be
        // found and stopped as a whole (see More → Recurring Transactions).
        final groupId = dates.length > 1 ? _uuid.v4() : null;
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
            recurringFrequency: groupId == null ? null : _recurringFrequency,
          );
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    if (_isEditingPeople) {
      await ref.read(peopleRepoProvider).deleteEntry(widget.existingPeople!);
    } else if (_isEditingTxn) {
      await ref.read(transactionRepoProvider).deleteTransaction(widget.existing!.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Color get _saveColor {
    switch (_kind) {
      case EntryKind.income:
        return AppColors.incomeGreen;
      case EntryKind.people:
        return AppColors.borrowedLent;
      case EntryKind.expense:
        return const Color(0xFFFF5A52);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  _KindToggle(kind: _kind, onChanged: _onKindChanged),
                  const SizedBox(height: _gap + 4),
                ],

                // ---- People: type toggle, then Name + Remark side by side ----
                if (_kind == EntryKind.people) ...[
                  _PeopleTypeToggle(type: _peopleType, onChanged: (t) => setState(() => _peopleType = t)),
                  const SizedBox(height: _gap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _textFieldBox(label: 'Person name', controller: _personCtrl, field: _ActiveField.person)),
                      const SizedBox(width: 12),
                      Expanded(child: _textFieldBox(label: 'Remark', controller: _remarkCtrl, field: _ActiveField.remark)),
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

                // ---- Category, full width (People only) ----
                                
                if (_kind == EntryKind.people) ...[
                  _categoryBox(),
                  const SizedBox(height: _gap),
                ],

                // ---- Category + Remark, equal width and height ----
                if (_kind != EntryKind.people) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _categoryBox()),
                      const SizedBox(width: 12),
                      Expanded(child: _textFieldBox(label: 'Remark', controller: _remarkCtrl, field: _ActiveField.remark)),
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
                      if (_kind != EntryKind.people && !_isEditing) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: _isRecurring ? 'Edit repeat settings' : 'Repeat this entry',
                          icon: Icon(Icons.repeat_rounded, color: _isRecurring ? AppColors.accent : Colors.grey, size: 21),
                          onPressed: _openRecurringSheet,
                        ),
                      ],
                    ],
                  ),
                ),

                // ---- Recurring summary, when set ----
                // Tapping the text itself opens a calendar to pick a custom
                // end date directly; the chevron still opens the full
                // frequency/count sheet.
                if (_isRecurring) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.repeat_rounded, size: 14, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: _pickCustomEndDate,
                            borderRadius: BorderRadius.circular(6),
                            child: Text(
                              _recurringSummary(),
                              style: const TextStyle(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _openRecurringSheet,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.chevron_right, size: 16, color: AppColors.accent),
                          ),
                        ),
                      ],
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
                                'Excluded from monthly totals. Visible in Yearly & Statistics tabs.',
                                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ---- Link to manage/stop existing recurring series ----
                if (!_isEditing && _kind != EntryKind.people) ...[
                  const SizedBox(height: _gap),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        final navigator = Navigator.of(context, rootNavigator: true);
                        navigator.pop(); // close this sheet
                        navigator.push(MaterialPageRoute(builder: (_) => const MoreScreen()));
                      },
                      icon: const Icon(Icons.event_repeat_outlined, size: 16),
                      label: const Text('Manage or stop repeating entries', style: TextStyle(fontSize: 12.5)),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.grey),
                    ),
                  ),
                ],

                const SizedBox(height: _gap),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _saveColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(
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
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline, color: AppColors.expense),
                      label: const Text('Delete', style: TextStyle(color: AppColors.expense)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _recurringSummary() {
    final dates = generateRecurringDates(_date, _recurringFrequency, count: _recurringCount);
    final freqLabel = const {'weekly': 'week', 'monthly': 'month', 'annually': 'year'}[_recurringFrequency]!;
    return 'Repeats every $freqLabel, $_recurringCount times · ends ${DateFormat('d MMM yyyy').format(dates.last)} · tap to change';
  }

  /// A read-only text field that is filled by the in-sheet keyboard
  /// (the OS keyboard is deliberately never shown). Used for Person name
  /// and Remark so both look and behave identically.
  Widget _textFieldBox({
    required String label,
    required TextEditingController controller,
    required _ActiveField field,
  }) {
    return SizedBox(
      height: _fieldHeight + 3,
      child: TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: _activeField == field ? const Icon(Icons.keyboard, size: 18, color: AppColors.accent) : null,
        ),
        onTap: () => setState(() => _activeField = field),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                padding: const EdgeInsets.only(top: 10),
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
        _activeField = _activeField == _ActiveField.amount ? _ActiveField.none : _ActiveField.amount;
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
              _activeField = _activeField == _ActiveField.account ? _ActiveField.none : _ActiveField.account;
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
            value: selected.isNotEmpty ? '${selected.first.icon}  ${selected.first.name}' : 'Select category',
            active: _activeField == _ActiveField.category,
            onTap: () => setState(() {
              _activeField = _activeField == _ActiveField.category ? _ActiveField.none : _ActiveField.category;
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

/// The result of the recurring-options sheet: either a chosen
/// frequency+count, or a request to turn repeating off entirely.
class _RecurringChoice {
  final String frequency;
  final int count;
  final bool stop;
  const _RecurringChoice({required this.frequency, required this.count, this.stop = false});
}

/// Lets the user pick how often an entry repeats and, crucially, the
/// RANGE — how many times ("Repeat 12 times") — with a live preview of
/// the last occurrence's date, so the end of the series is always visible
/// before saving. Tapping the preview itself opens a calendar to set a
/// custom end date directly.
class _RecurringOptionsSheet extends StatefulWidget {
  final DateTime startDate;
  final String initialFrequency;
  final int initialCount;
  final bool showStopOption;

  const _RecurringOptionsSheet({
    required this.startDate,
    required this.initialFrequency,
    required this.initialCount,
    required this.showStopOption,
  });

  @override
  State<_RecurringOptionsSheet> createState() => _RecurringOptionsSheetState();
}

class _RecurringOptionsSheetState extends State<_RecurringOptionsSheet> {
  late String _frequency = widget.initialFrequency;
  late int _count = widget.initialCount;

  int get _maxCount => _kRecurringMaxCount[_frequency]!;

  void _setFrequency(String f) {
    setState(() {
      _frequency = f;
      // Re-clamp so switching e.g. Monthly(30) -> Annually doesn't leave an
      // out-of-range count silently in place.
      final max = _kRecurringMaxCount[f]!;
      if (_count > max) _count = max;
      if (_count < 2) _count = 2;
    });
  }

  Future<void> _pickCustomEndDate() async {
    final currentLast = generateRecurringDates(widget.startDate, _frequency, count: _count).last;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentLast,
      firstDate: widget.startDate,
      lastDate: DateTime(2100),
      helpText: 'Choose when the series ends',
    );
    if (picked == null) return;
    setState(() => _count = _countForTargetEndDate(widget.startDate, _frequency, picked));
  }

  @override
  Widget build(BuildContext context) {
    final dates = generateRecurringDates(widget.startDate, _frequency, count: _count);
    final freqOptions = const [
      ('weekly', 'Weekly'),
      ('monthly', 'Monthly'),
      ('annually', 'Annually'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
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
              const Text('Repeat this entry', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Starts ${DateFormat('d MMM yyyy').format(widget.startDate)}',
                style: const TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 18),

              const Text('Frequency', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (value, label) in freqOptions) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setFrequency(value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _frequency == value ? AppColors.accent.withOpacity(0.18) : Colors.transparent,
                            border: Border.all(color: _frequency == value ? AppColors.accent : Colors.grey.shade700),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _frequency == value ? AppColors.accent : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (value != 'annually') const SizedBox(width: 8),
                  ],
                ],
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Text('Repeat how many times', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  Text('Up to $_maxCount', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _stepButton(Icons.remove, enabled: _count > 2, onTap: () => setState(() => _count--)),
                  Expanded(
                    child: Column(
                      children: [
                        Text('$_count', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        const Text('times', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  _stepButton(Icons.add, enabled: _count < _maxCount, onTap: () => setState(() => _count++)),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: _count.toDouble(),
                min: 2,
                max: _maxCount.toDouble(),
                divisions: _maxCount - 2 == 0 ? null : _maxCount - 2,
                activeColor: AppColors.accent,
                label: '$_count',
                onChanged: (v) => setState(() => _count = v.round()),
              ),

              const SizedBox(height: 6),
              // Tappable — opens a calendar to set a custom end date, which
              // is translated back into a count for this frequency.
              InkWell(
                onTap: _pickCustomEndDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_outlined, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ends ${DateFormat('d MMM yyyy').format(dates.last)}  ·  last of $_count entries',
                          style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.edit_calendar_outlined, size: 16, color: AppColors.accent),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.showStopOption) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, const _RecurringChoice(frequency: '', count: 0, stop: true)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.expense),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Don't repeat", style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: widget.showStopOption ? 1 : 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _RecurringChoice(frequency: _frequency, count: _count)),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, {required bool enabled, required VoidCallback onTap}) {
    return Material(
      color: enabled ? const Color(0xFF2B2D3A) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: enabled ? Colors.white : Colors.grey.shade700),
        ),
      ),
    );
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