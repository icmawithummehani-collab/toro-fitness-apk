import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int i = 0;
  static const pages = [DashboardTab(), MembersTab(), PlansTab(), PaymentsTab(), CheckinTab()];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TORO FITNESS • ADMIN'), actions: [
          IconButton(onPressed: () => sb.auth.signOut(), icon: const Icon(Icons.logout))
        ]),
        body: pages[i],
        bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
              NavigationDestination(icon: Icon(Icons.groups), label: 'Members'),
              NavigationDestination(icon: Icon(Icons.card_membership), label: 'Plans'),
              NavigationDestination(icon: Icon(Icons.payments), label: 'Payments'),
              NavigationDestination(icon: Icon(Icons.how_to_reg), label: 'Check-in'),
            ]),
      );
}

// ---------- shared sheets ----------
Future<void> recordPayment(BuildContext context, {String? memberId, VoidCallback? onDone}) async {
  final members = await sb.from('members').select('id,full_name').order('full_name');
  if (!context.mounted) return;
  String? mid = memberId;
  String method = 'cash';
  final amt = TextEditingController();
  await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Record a payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(
                    value: mid,
                    hint: const Text('Member'),
                    items: [for (final m in members) DropdownMenuItem(value: m['id'] as String, child: Text(m['full_name']))],
                    onChanged: (v) => set(() => mid = v)),
                TextField(
                    controller: amt,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (PKR)')),
                DropdownButtonFormField<String>(
                    value: method,
                    items: [for (final m in ['cash', 'bank_transfer', 'card', 'other']) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => set(() => method = v!)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () async {
                      final a = num.tryParse(amt.text);
                      if (mid == null || a == null || a <= 0) return;
                      try {
                        final sub = await sb
                            .from('subscriptions')
                            .select('id')
                            .eq('member_id', mid!)
                            .inFilter('status', ['pending', 'active', 'frozen'])
                            .order('created_at', ascending: false)
                            .limit(1)
                            .maybeSingle();
                        await sb.from('payments').insert(
                            {'member_id': mid, 'subscription_id': sub?['id'], 'amount_pkr': a, 'method': method});
                        if (ctx.mounted) Navigator.pop(ctx);
                        onDone?.call();
                      } catch (e) {
                        if (ctx.mounted) toast(ctx, errText(e));
                      }
                    },
                    child: const Text('Save payment'))
              ]))));
}

Future<void> assignPlan(BuildContext context, String memberId, VoidCallback onDone) async {
  final plans = await sb.from('membership_plans').select().eq('is_active', true).order('price_pkr');
  if (!context.mounted) return;
  await showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Add member to plan', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final p in plans)
              ListTile(
                  title: Text(p['name']),
                  subtitle: Text('${p['duration_days']} days'),
                  trailing: Text(pkr(p['price_pkr'])),
                  onTap: () async {
                    final start = DateTime.now();
                    try {
                      await sb.from('subscriptions').insert({
                        'member_id': memberId,
                        'plan_id': p['id'],
                        'start_date': ymd(start),
                        'end_date': ymd(start.add(Duration(days: p['duration_days'] as int))),
                        'fee_pkr': p['price_pkr'],
                        'status': 'active',
                        'activated_at': start.toIso8601String()
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      onDone();
                    } catch (e) {
                      if (ctx.mounted) toast(ctx, errText(e));
                    }
                  })
          ]));
}

// ---------- Dashboard ----------
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  String period = 'month';
  static const periods = {'today': 'Today', 'week': 'Last 7 days', 'month': 'This month', 'year': 'This year', 'all': 'All time'};

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: FutureBuilder(
          future: sb.rpc('admin_dashboard', params: {'p_period': period}),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text(errText(snap.error!)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final d = Map<String, dynamic>.from(snap.data as Map);
            final exp = d['expiring'] as List;
            return ListView(padding: const EdgeInsets.all(14), children: [
              GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.35,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    _Metric('Active members', '${d['active_members']}'),
                    _Metric('Check-ins today', '${d['checkins_today']}'),
                    _Metric('Revenue', pkr(d['revenue']),
                        extra: DropdownButton<String>(
                            value: period,
                            isDense: true,
                            underline: const SizedBox(),
                            items: [for (final e in periods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                            onChanged: (v) => setState(() => period = v!))),
                    _Metric('Revenue outstanding', pkr(d['outstanding'])),
                  ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: () => recordPayment(context, onDone: () => setState(() {})),
                  icon: const Icon(Icons.add),
                  label: const Text('Record a payment'),
                  style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.all(14))),
              const SizedBox(height: 18),
              Text('Expires in 7 days (${exp.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                  child: Column(children: [
                if (exp.isEmpty) const ListTile(title: Text('None')),
                for (final e in exp) ListTile(dense: true, title: Text(e['name']), trailing: Text(e['end_date']))
              ])),
              const SizedBox(height: 12),
              const Text('Live check-ins', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Card(child: LiveCheckins()),
            ]);
          },
        ),
      );
}

class _Metric extends StatelessWidget {
  final String label, value;
  final Widget? extra;
  const _Metric(this.label, this.value, {this.extra});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: const TextStyle(color: Colors.white60)),
            if (extra != null) extra!,
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))
          ])));
}

// ---------- Members ----------
class MembersTab extends StatefulWidget {
  const MembersTab({super.key});
  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  void refresh() => setState(() {});

  Future<void> addMember() async {
    final n = TextEditingController(), ph = TextEditingController(), em = TextEditingController(), pw = TextEditingController();
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('New member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(controller: n, decoration: const InputDecoration(labelText: 'Full name')),
              TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (+923001234567)')),
              TextField(controller: em, decoration: const InputDecoration(labelText: 'Email (optional)')),
              TextField(controller: pw, decoration: const InputDecoration(labelText: 'Password (8+ chars)')),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () async {
                    try {
                      final r = await sb.functions.invoke('admin-create-member',
                          body: {'full_name': n.text, 'phone': ph.text, 'email': em.text, 'password': pw.text});
                      final data = r.data as Map;
                      if (data['error'] != null) throw Exception(data['error']);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) await assignPlan(context, data['member_id'], refresh);
                      refresh();
                    } catch (e) {
                      if (ctx.mounted) toast(ctx, e.toString().replaceFirst('Exception: ', ''));
                    }
                  },
                  child: const Text('Create & choose plan'))
            ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: addMember, icon: const Icon(Icons.person_add), label: const Text('Member'), backgroundColor: brand),
        body: FutureBuilder(
          future: sb
              .from('members')
              .select('id,full_name,phone,member_code,subscriptions(id,status,end_date,membership_plans(name))')
              .order('created_at', ascending: false),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text(errText(snap.error!)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data as List;
            if (rows.isEmpty) return const Center(child: Text('No members yet'));
            return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              for (final m in rows) _memberCard(m),
            ]);
          },
        ),
      );

  Widget _memberCard(Map m) {
    final subs = List<Map>.from(m['subscriptions'] as List)..sort((a, b) => b['end_date'].compareTo(a['end_date']));
    final s = subs.isEmpty ? null : subs.first;
    final status = s?['status'] as String?;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${m['full_name']}  •  ${m['member_code']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                if (status != null) Text(status, style: TextStyle(color: statusColor(status)))
              ]),
              Text(s == null ? 'No plan yet' : '${s['membership_plans']['name']} · till ${s['end_date']}',
                  style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton(onPressed: () => assignPlan(context, m['id'], refresh), child: const Text('Add to plan')),
                OutlinedButton(onPressed: () => recordPayment(context, memberId: m['id'], onDone: refresh), child: const Text('Payment')),
                if (s != null) StatusButtons(subId: s['id'], status: status!, onDone: refresh),
              ])
            ])));
  }
}

// ---------- Plans ----------
class PlansTab extends StatefulWidget {
  const PlansTab({super.key});
  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  Future<void> editPrice(Map p) async {
    final c = TextEditingController(text: '${p['price_pkr']}'.replaceAll(RegExp(r'\.0+$'), ''));
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('${p['name']} price'),
                content: TextField(controller: c, keyboardType: TextInputType.number),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))
                ]));
    final v = num.tryParse(c.text);
    if (ok != true || v == null || v < 0) return;
    try {
      await sb.from('membership_plans').update({'price_pkr': v}).eq('id', p['id']);
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: sb.from('membership_plans').select().order('price_pkr'),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final p in snap.data as List)
              Card(
                  child: ListTile(
                      title: Text(p['name']),
                      subtitle: Text('${p['duration_days']} days'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(pkr(p['price_pkr']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => editPrice(p))
                      ])))
          ]);
        },
      );
}

// ---------- Payments (admin only can write) ----------
class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});
  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => recordPayment(context, onDone: () => setState(() {})),
            icon: const Icon(Icons.add),
            label: const Text('Payment'),
            backgroundColor: brand),
        body: FutureBuilder(
          future: sb.from('payments').select('amount_pkr,paid_at,method,receipt_number,members(full_name)').order('paid_at', ascending: false),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text(errText(snap.error!)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data as List;
            if (rows.isEmpty) return const Center(child: Text('No payments yet'));
            return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              for (final p in rows)
                ListTile(
                    title: Text(p['members']['full_name']),
                    subtitle: Text('${p['receipt_number']} · ${p['method']} · ${DateFormat.yMMMd().format(DateTime.parse(p['paid_at']).toLocal())}'),
                    trailing: Text(pkr(p['amount_pkr']), style: const TextStyle(fontWeight: FontWeight.bold)))
            ]);
          },
        ),
      );
}

// ---------- Check-in / attendance ----------
class CheckinTab extends StatefulWidget {
  const CheckinTab({super.key});
  @override
  State<CheckinTab> createState() => _CheckinTabState();
}

class _CheckinTabState extends State<CheckinTab> {
  final code = TextEditingController();
  String msg = '';
  bool ok = false;

  Future<void> mark() async {
    try {
      final r = Map<String, dynamic>.from(await sb.rpc('mark_attendance', params: {'p_code': code.text}) as Map);
      setState(() { msg = r['message']; ok = r['ok'] == true; });
      if (ok) code.clear();
    } catch (e) {
      setState(() { msg = errText(e); ok = false; });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Member tells you the 6-digit code from their app', style: TextStyle(color: Colors.white60)),
        TextField(
            controller: code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Check-in code')),
        FilledButton(
            onPressed: mark,
            style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.all(14)),
            child: const Text('Verify & mark present')),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(10), child: Text(msg, style: TextStyle(color: ok ? Colors.green : Colors.redAccent))),
        const SizedBox(height: 16),
        const Text('Attendance today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Card(child: LiveCheckins()),
      ]);
}
