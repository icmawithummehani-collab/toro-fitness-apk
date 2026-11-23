import 'package:flutter/material.dart';
import '../core.dart';
import 'admin_screens.dart';
import 'member_screens.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? role, error;
  @override
  void initState() { super.initState(); loadRole(); }

  Future<void> loadRole() async {
    try {
      final row = await sb.from('profiles').select('role').eq('id', sb.auth.currentUser!.id).single();
      if (mounted) setState(() => role = row['role'] as String);
    } catch (_) {
      if (mounted) setState(() => error = 'Profile is not provisioned. Contact the owner/admin.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!),
        TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Sign out'))
      ])));
    }
    if (role == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (role == 'owner_admin') return const AdminShell();
    if (role == 'member') return const MemberShell();
    return const Scaffold(body: Center(child: Text('Unknown account role.')));
  }
}
