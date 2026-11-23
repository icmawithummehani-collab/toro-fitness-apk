import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_url.isNotEmpty && _key.isNotEmpty) {
    await Supabase.initialize(url: _url, anonKey: _key);
  }
  runApp(const ToroFitnessApp());
}

class ToroFitnessApp extends StatelessWidget {
  const ToroFitnessApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Toro Fitness',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF101114),
          colorScheme: const ColorScheme.dark(primary: brand, surface: Color(0xFF1B1D22)),
          useMaterial3: true,
        ),
        home: (_url.isNotEmpty && _key.isNotEmpty)
            ? const AuthGate()
            : const Scaffold(
                body: Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('TORO FITNESS\n\nConfigure Supabase URL and public anon key to begin.',
                            textAlign: TextAlign.center)))),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (_, __) => Supabase.instance.client.auth.currentSession == null
            ? const AuthScreen()
            : const HomeShell(),
      );
}
