import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import 'transaction_repository.dart';

const _uuid = Uuid();

/// Hard ceiling on how many rows one "repeat this entry" action can ever
/// create, so a far-off end date can't silently generate thousands of rows.
const int kMaxRecurringOccurrences = 60;

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
      final maxDays = _daysInMonth(year, month);
      if (day > maxDays) day = maxDays;
      dates.add(DateTime(year, month, day, start.hour, start.minute));
    } else if (frequency == 'annually') {
      dates.add(DateTime(start.year + i, start.month, start.day, start.hour, start.minute));
    }
  }
  return dates;
}

int _daysInMonth(int year, int month) {
  final firstOfNext = month < 12 ? DateTime(year, month + 1, 1) : DateTime(year + 1, 1, 1);
  return firstOfNext.subtract(const Duration(days: 1)).day;
}

/// How many occurrences of [frequency] starting at [start] it takes to
/// reach (but not pass) [target] — used to turn a custom end date the user
/// picks into the count-based range the rest of this file works with.
int occurrenceCountForEndDate(DateTime start, String frequency, DateTime target, {int maxCount = kMaxRecurringOccurrences}) {
  int count = 1;
  while (count < maxCount) {
    final next = generateRecurringDates(start, frequency, count: count + 1).last;
    if (next.isAfter(target)) break;
    count++;
  }
  return count.clamp(2, maxCount);
}

class _Occurrence {
  final String transactionId;
  final DateTime date;
  _Occurrence(this.transactionId, this.date);

  Map<String, dynamic> toJson() => {'id': transactionId, 'date': date.toIso8601String()};
  factory _Occurrence.fromJson(Map<String, dynamic> j) =>
      _Occurrence(j['id'] as String, DateTime.parse(j['date'] as String));
}

class _SeriesRecord {
  final String groupId;
  final String type;
  final String? categoryId;
  final String? accountId;
  final double amount;
  final String remark;
  final String frequency;
  final bool isYearly;
  bool stopped;
  final List<_Occurrence> occurrences;

  _SeriesRecord({
    required this.groupId,
    required this.type,
    this.categoryId,
    this.accountId,
    required this.amount,
    required this.remark,
    required this.frequency,
    required this.isYearly,
    this.stopped = false,
    required this.occurrences,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'type': type,
        'categoryId': categoryId,
        'accountId': accountId,
        'amount': amount,
        'remark': remark,
        'frequency': frequency,
        'isYearly': isYearly,
        'stopped': stopped,
        'occurrences': occurrences.map((o) => o.toJson()).toList(),
      };

  factory _SeriesRecord.fromJson(Map<String, dynamic> j) => _SeriesRecord(
        groupId: j['groupId'] as String,
        type: j['type'] as String,
        categoryId: j['categoryId'] as String?,
        accountId: j['accountId'] as String?,
        amount: (j['amount'] as num).toDouble(),
        remark: j['remark'] as String? ?? '',
        frequency: j['frequency'] as String,
        isYearly: j['isYearly'] as bool? ?? false,
        stopped: j['stopped'] as bool? ?? false,
        occurrences: (j['occurrences'] as List)
            .map((e) => _Occurrence.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Tracks "repeat this entry" series so they can later be reviewed and
/// stopped from More → Recurring Transactions.
///
/// Deliberately NOT part of the SQLite schema: a schema change needs the
/// drift code generator to run before the app can even compile, which this
/// repository has no way to verify from inside the app. Instead, each
/// series is just a small JSON record (its shared settings + the ids and
/// dates of the individual rows it created) kept in a plain file via
/// `path_provider` — a dependency the project already has. The actual
/// transactions are still ordinary rows created through
/// [TransactionRepository.addTransaction]; this file only remembers which
/// ones belong together.
class RecurringRepository {
  final TransactionRepository transactionRepo;
  RecurringRepository(this.transactionRepo);

  final _controller = StreamController<List<RecurringSeriesInfo>>.broadcast();
  bool _seeded = false;
  List<_SeriesRecord>? _cache;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recurring_series.json');
  }

  Future<List<_SeriesRecord>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      if (!await f.exists()) return _cache = [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return _cache = [];
      final list = jsonDecode(raw) as List;
      return _cache = list.map((e) => _SeriesRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // A corrupt or unreadable file shouldn't ever block adding or
      // viewing transactions — treat it as "no series recorded yet".
      return _cache = [];
    }
  }

  Future<void> _save(List<_SeriesRecord> all) async {
    _cache = all;
    final f = await _file();
    await f.writeAsString(jsonEncode(all.map((s) => s.toJson()).toList()));
  }

  List<RecurringSeriesInfo> _toInfoList(List<_SeriesRecord> all) {
    final now = DateTime.now();
    final result = <RecurringSeriesInfo>[];
    for (final s in all) {
      if (s.stopped) continue;
      final future = s.occurrences.where((o) => o.date.isAfter(now)).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (future.isEmpty) continue; // fully in the past — nothing left to show or stop
      result.add(RecurringSeriesInfo(
        groupId: s.groupId,
        type: s.type,
        categoryId: s.categoryId,
        remark: s.remark,
        frequency: s.frequency,
        nextDate: future.first.date,
        remainingCount: future.length,
        totalCount: s.occurrences.length,
        amount: s.amount,
      ));
    }
    result.sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return result;
  }

  /// Every recurring series that still has at least one occurrence ahead of
  /// today. Powers the "Recurring Transactions" card in More.
  Stream<List<RecurringSeriesInfo>> watchActive() {
    if (!_seeded) {
      _seeded = true;
      _load().then((all) => _controller.add(_toInfoList(all)));
    }
    return _controller.stream;
  }

  /// Creates every occurrence as its own transaction (via
  /// [TransactionRepository.addTransaction]) and remembers them as one
  /// series. [count] and [endDate] are alternative ways to say how far the
  /// series reaches — exactly one should be given.
  Future<void> addSeries({
    required String type,
    required double amount,
    required DateTime startDate,
    String? accountId,
    String? categoryId,
    String remark = '',
    bool isYearly = false,
    required String frequency,
    int? count,
    DateTime? endDate,
  }) async {
    final resolvedCount = count ?? occurrenceCountForEndDate(startDate, frequency, endDate!);
    final dates = generateRecurringDates(startDate, frequency, count: resolvedCount);
    if (dates.isEmpty) return;

    final occurrences = <_Occurrence>[];
    for (final d in dates) {
      final id = await transactionRepo.addTransaction(
        type: type,
        amount: amount,
        date: d,
        accountId: accountId,
        categoryId: categoryId,
        remark: remark,
        isYearly: isYearly,
      );
      occurrences.add(_Occurrence(id, d));
    }

    final record = _SeriesRecord(
      groupId: _uuid.v4(),
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      amount: amount,
      remark: remark,
      frequency: frequency,
      isYearly: isYearly,
      occurrences: occurrences,
    );

    final all = await _load();
    all.add(record);
    await _save(all);
    _controller.add(_toInfoList(all));
  }

  /// Cancels every occurrence of series [groupId] dated today or later —
  /// occurrences already in the past stay in the ledger, since they already
  /// happened. Returns how many were cancelled.
  Future<int> stopRecurring(String groupId) async {
    final all = await _load();
    final idx = all.indexWhere((s) => s.groupId == groupId);
    if (idx == -1) return 0;

    final series = all[idx];
    final now = DateTime.now();
    final toCancel = series.occurrences.where((o) => o.date.isAfter(now)).toList();
    for (final o in toCancel) {
      await transactionRepo.deleteTransaction(o.transactionId); // soft-delete + reverse its balance effect
    }
    series.stopped = true;
    await _save(all);
    _controller.add(_toInfoList(all));
    return toCancel.length;
  }
}
