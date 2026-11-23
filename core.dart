import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;
const brand = Color(0xFFD62828);

String pkr(num v) => 'Rs ${NumberFormat.decimalPattern().format(v.round())}';
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
Color statusColor(String s) => switch (s) {
      'active' => Colors.green,
      'frozen' => Colors.orange,
      _ => Colors.redAccent
    };
String errText(Object e) => e is PostgrestException
    ? e.message
    : e is AuthException
        ? e.message
        : 'Something went wrong';

/// Freeze / resume / cancel. Allowed for admin AND member (enforced in the database).
Future<void> changeStatus(BuildContext c, String subId, String status, VoidCallback done) async {
  final label = status == 'active' ? 'Resume' : status == 'frozen' ? 'Freeze' : 'Cancel';
  final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(title: Text('$label membership?'), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes'))
          ]));
  if (ok != true) return;
  try {
    await sb.rpc('set_subscription_status', params: {'p_sub': subId, 'p_status': status});
    done();
  } catch (e) {
    if (c.mounted) toast(c, errText(e));
  }
}

class StatusButtons extends StatelessWidget {
  final String subId, status;
  final VoidCallback onDone;
  const StatusButtons({super.key, required this.subId, required this.status, required this.onDone});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        if (status == 'active')
          OutlinedButton(onPressed: () => changeStatus(context, subId, 'frozen', onDone), child: const Text('Freeze')),
        if (status == 'frozen')
          OutlinedButton(onPressed: () => changeStatus(context, subId, 'active', onDone), child: const Text('Resume')),
        if (status != 'cancelled')
          OutlinedButton(onPressed: () => changeStatus(context, subId, 'cancelled', onDone), child: const Text('Cancel')),
      ]);
}

/// Realtime list of today's check-ins.
class LiveCheckins extends StatelessWidget {
  const LiveCheckins({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('attendance').stream(primaryKey: ['id']).order('checked_in_at', ascending: false).limit(50),
        builder: (_, s) {
          final n = DateTime.now();
          final rows = (s.data ?? []).where((r) {
            final t = DateTime.parse(r['checked_in_at']).toLocal();
            return t.year == n.year && t.month == n.month && t.day == n.day;
          }).toList();
          if (rows.isEmpty) return const ListTile(title: Text('No check-ins yet today'));
          return Column(children: [
            for (final r in rows)
              ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(r['member_name']),
                  trailing: Text(DateFormat.jm().format(DateTime.parse(r['checked_in_at']).toLocal())))
          ]);
        },
      );
}
