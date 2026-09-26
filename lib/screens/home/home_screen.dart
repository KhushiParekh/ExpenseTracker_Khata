import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/app_providers.dart';
import '../../widgets/add_transaction_modal.dart';
import 'calendar_tab.dart';
import 'monthly_tab.dart';
import 'yearly_tab.dart';
import 'total_tab.dart';
import 'people_tab.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Order per spec: Calendar, Monthly, Yearly, People, Total.
  static const _tabs = ['Calendar', 'Monthly', 'Yearly', 'People', 'Total'];
  static const _pages = [CalendarTab(), MonthlyTab(), YearlyTab(), PeopleTab(), TotalTab()];

  // Monthly(1) and Yearly(2) tabs operate on a whole YEAR at a time;
  // Calendar(0), People(3), Total(4) operate on a single MONTH.
  bool get _isYearGranularity => _tabController.index == 1 || _tabController.index == 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: ref.read(homeTabIndexProvider));
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(homeTabIndexProvider.notifier).state = _tabController.index;
        setState(() {}); // refresh the nav header's granularity
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(focusedMonthProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    // Lets other tabs switch sub-tab (e.g. tapping a month in Monthly opens
    // that month in Calendar) just by setting homeTabIndexProvider.
    ref.listen<int>(homeTabIndexProvider, (previous, next) {
      if (_tabController.index != next) _tabController.animateTo(next);
    });

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: _NavHeader(
          focused: focused,
          isYearGranularity: _isYearGranularity,
          onPrev: () => ref.read(focusedMonthProvider.notifier).state =
              _isYearGranularity ? DateTime(focused.year - 1, focused.month) : DateTime(focused.year, focused.month - 1),
          onNext: () => ref.read(focusedMonthProvider.notifier).state =
              _isYearGranularity ? DateTime(focused.year + 1, focused.month) : DateTime(focused.year, focused.month + 1),
        ),
        centerTitle: false,
        actions: [
          // Global search: spans the whole ledger, not just this month.
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search all transactions',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(controller: _tabController, children: _pages),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddTransactionModal(context, ref, selectedDate),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NavHeader extends StatelessWidget {
  final DateTime focused;
  final bool isYearGranularity;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _NavHeader({required this.focused, required this.isYearGranularity, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final label = isYearGranularity ? '${focused.year}' : DateFormat('MMM yyyy').format(focused);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
