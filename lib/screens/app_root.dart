import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import 'home/home_screen.dart';
import 'statistics/statistics_screen.dart';
import 'accounts/accounts_screen.dart';
import 'more/more_screen.dart';

/// There is no login: the app opens straight into the ledger.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  int _index = 0;
  Key _homeKey = UniqueKey();

  void _onTap(int i) {
    if (i == 0 && _index != 0) {
      // Coming back to "Trans." from another tab -- always land on the
      // Calendar sub-tab, never wherever it was left (e.g. People).
      // Resetting the provider AND remounting HomeScreen (fresh key) is
      // what actually forces its TabController back to index 0, since
      // IndexedStack normally keeps it alive with whatever tab was active.
      ref.read(homeTabIndexProvider.notifier).state = 0;
      setState(() {
        _homeKey = UniqueKey();
        _index = i;
      });
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(key: _homeKey),
      const StatisticsScreen(),
      const AccountsScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Trans.'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Accounts'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
