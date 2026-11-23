import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core.dart';

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});
  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TORO FITNESS • MEMBER'), actions: [
          IconButton(onPressed: () => sb.auth.signOut(), icon: const Icon(Icons.logout))
        ]),
        body: const [MyPlanTab(), MyCodeTab(), MyPaymentsTab()][i],
        bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.card_membership), label: 'My Plan'),
              NavigationDestination(icon: Icon(Icons.pin), label: 'Check-in'),
              NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Payments'),
            ]),
      );
}

class MyPlanTab extends StatefulWidget {
  const MyPlanTab({super.key});
  @override
  State<MyPlanTab> createState() => _MyPlanTabState();
}

class _MyPlanTabState extends State<MyPlanTab> {
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: sb.from('subscriptions').select('id,status,start_date,end_date,fee_pkr,membership_plans(name)').order('end_date', ascending: false).limit(1),
        builder: (_, snap) {
          if (snap.hasError) return Center(child: Text(errText(snap.error!)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data as List;
          if (rows.isEmpty) return const Center(child: Text('No membership yet. Please contact the gym.'));
          final s = rows.first as Map;
          final st = s['status'] as String;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['membership_plans']['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Status: $st', style: TextStyle(color: statusColor(st), fontWeight: FontWeight.bold)),
                      Text('Valid: ${s['start_date']} → ${s['end_date']}'),
                      Text('Fee: ${pkr(s['fee_pkr'])}'),
                    ]))),
            const SizedBox(height: 8),
            StatusButtons(subId: s['id'], status: st, onDone: () => setState(() {})),
          ]);
        },
      );
}

class MyCodeTab extends StatefulWidget {
  const MyCodeTab({super.key});
  @override
  State<MyCodeTab> createState() => _MyCodeTabState();
}

class _MyCodeTabState extends State<MyCodeTab> {
  String? code;
  Future<void> gen() async {
    try {
      final c = await sb.rpc('generate_checkin_code');
      setState(() => code = c as String);
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Tell this code to the admin at the desk. A new code is created every time and works for 10 minutes, once.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 20),
        Text(code ?? '------',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 10, color: brand)),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: gen,
            style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.all(16)),
            child: const Text('Generate new code')),
      ]));
}

class MyPaymentsTab extends StatelessWidget {
  const MyPaymentsTab({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: sb.from('payments').select('amount_pkr,paid_at,method,receipt_number').order('paid_at', ascending: false),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data as List;
          if (rows.isEmpty) return const Center(child: Text('No payments recorded yet'));
          return ListView(children: [
            for (final p in rows)
              ListTile(
                  title: Text(pkr(p['amount_pkr'])),
                  subtitle: Text('${p['receipt_number']} · ${p['method']}'),
                  trailing: Text(DateFormat.yMMMd().format(DateTime.parse(p['paid_at']).toLocal())))
          ]);
        },
      );
}
