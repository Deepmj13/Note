import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/observability.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/settings_providers.dart';
import 'package:note_v4/providers/sync_notifier.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/screens/home_screen.dart';
import 'package:note_v4/ui/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No-op unless a SENTRY_DSN is provided via --dart-define.
  await initObservability();
  runApp(const ProviderScope(child: NoteApp()));
}

class NoteApp extends ConsumerWidget {
  const NoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final ready = ref.watch(authReadyProvider);
    final user = ref.watch(authControllerProvider);
    // Keep the sync engine's connectivity listener alive for the app lifetime.
    ref.listen(syncNotifierProvider, (_, _) {});

    final home = !ready
        ? const _SplashScreen()
        : user == null
            ? const LoginScreen()
            : const HomeScreen();

    return MaterialApp(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: home,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
