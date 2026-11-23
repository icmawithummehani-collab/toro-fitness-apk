import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final identity = TextEditingController();
  final password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;

  Future<void> signIn() async {
    setState(() { busy = true; error = null; });
    try {
      final v = identity.text.trim();
      if (v.isEmpty || password.text.isEmpty) throw const AuthException('Enter email/phone and password.');
      await sb.auth.signInWithPassword(
          email: v.contains('@') ? v : null, phone: v.contains('@') ? null : v, password: password.text);
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Sign-in failed. Check your details.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() { identity.dispose(); password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Icon(Icons.fitness_center, size: 56, color: brand),
                          const SizedBox(height: 14),
                          const Text('TORO FITNESS',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          const SizedBox(height: 32),
                          TextField(
                              controller: identity,
                              decoration: const InputDecoration(
                                  labelText: 'Email or phone (+92...)', prefixIcon: Icon(Icons.person_outline))),
                          const SizedBox(height: 12),
                          TextField(
                              controller: password,
                              obscureText: obscure,
                              decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () => setState(() => obscure = !obscure)))),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
                          const SizedBox(height: 20),
                          FilledButton(
                              onPressed: busy ? null : signIn,
                              style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.all(16)),
                              child: Text(busy ? 'Signing in…' : 'Sign in')),
                          const SizedBox(height: 16),
                          const Text('Member accounts are created by Toro Fitness administration.',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12))
                        ]))))),
      );
}
