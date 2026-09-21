import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/app_providers.dart';
import 'screens/app_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KhaataApp()));
}

/// Khaata is fully local: there is no sign-in, no server and no network
/// calls. The SQLite database on this device is the single source of
/// truth, and the only way data leaves the device is an explicit
/// export from the More screen.
class KhaataApp extends ConsumerStatefulWidget {
  const KhaataApp({super.key});

  @override
  ConsumerState<KhaataApp> createState() => _KhaataAppState();
}

class _KhaataAppState extends ConsumerState<KhaataApp> {
  late final Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    // On a fresh install (and after "erase all data") the database has no
    // categories or accounts, so seed the defaults before showing the UI.
    _bootstrap = ref.read(appDatabaseProvider).seedDefaultsIfEmpty();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: FutureBuilder<void>(
        future: _bootstrap,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return const AppRoot();
        },
      ),
    );
  }
}
