import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../hebcal.dart';
import '../l10n/app_localizations.dart';
import 'detail.dart';
import 'search.dart';

/// פרטי אזכרה – נשמרים כולם בתוך הקישור
class Azkara {
  final String cem;
  final int id;
  final DateTime when;
  final bool atGrave;
  final String note;
  const Azkara(this.cem, this.id, this.when, this.atGrave, this.note);

  String get url => '$webBase/a/?${Uri(queryParameters: {
        'c': cem,
        'd': '$id',
        't': '${when.year}-${_2(when.month)}-${_2(when.day)}T${_2(when.hour)}:${_2(when.minute)}',
        'p': atGrave ? 'g' : 'e',
        if (note.isNotEmpty) 'm': note,
      }).query}';

  static Azkara? fromUri(Uri u) {
    if (!u.path.startsWith('/a')) return null;
    final id = int.tryParse(u.queryParameters['d'] ?? ''), cem = u.queryParameters['c'];
    final when = DateTime.tryParse(u.queryParameters['t'] ?? '');
    if (id == null || cem == null || when == null) return null;
    return Azkara(cem, id, when, u.queryParameters['p'] != 'e', u.queryParameters['m'] ?? '');
  }
}

String _2(int n) => n.toString().padLeft(2, '0');
String hhmm(DateTime d) => '${_2(d.hour)}:${_2(d.minute)}';

String _dows(AppLocalizations t, DateTime d) => [t.dow0, t.dow1, t.dow2, t.dow3, t.dow4, t.dow5, t.dow6][d.weekday % 7];

/// "יום ה' 18/11/2027 · כ"ט חשון"
String dayLine(AppLocalizations t, DateTime d) {
  final h = HebCal.toHeb(d);
  return '${_dows(t, d)} ${dmy(d)} · ${HebCal.gem(h.day)} ${h.month}';
}

String inviteText(AppLocalizations t, Azkara a, Deceased d, Cemetery cem) {
  final place = a.atGrave ? t.azAtGrave : t.azAtEntrance;
  return [
    t.azInviteTitle(d.fullName),
    '${dayLine(t, a.when)}, ${hhmm(a.when)}',
    '📍 $place – ${cem.name}${a.atGrave ? ', ${locLine(t, d)}' : ''}',
    if (a.note.isNotEmpty) a.note,
    a.url,
  ].join('\n');
}

void shareInvite(BuildContext context, String text, String subject) {
  final t = AppLocalizations.of(context);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
          title: Text(t.whatsapp),
          onTap: () {
            Navigator.pop(c);
            launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
          },
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(t.routeEmail),
          onTap: () {
            Navigator.pop(c);
            launchUrl(Uri.parse('mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}'));
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: Text(t.routeOther),
          onTap: () {
            Navigator.pop(c);
            Share.share(text, subject: subject);
          },
        ),
      ]),
    ),
  );
}

/// טופס תיאום אזכרה
class AzkaraFormScreen extends StatefulWidget {
  final Deceased deceased;
  final Cemetery cemetery;
  final DateTime yahrzeit;
  const AzkaraFormScreen({super.key, required this.deceased, required this.cemetery, required this.yahrzeit});
  @override
  State<AzkaraFormScreen> createState() => _AzkaraFormScreenState();
}

class _AzkaraFormScreenState extends State<AzkaraFormScreen> {
  late DateTime _day;
  TimeOfDay _time = const TimeOfDay(hour: 16, minute: 0);
  bool _atGrave = true;
  final _note = TextEditingController();

  DateTime get _yz => DateTime(widget.yahrzeit.year, widget.yahrzeit.month, widget.yahrzeit.day);

  /// אפשרויות: יום השנה (לא בשבת), יום ו' שלפני, יום א' שאחרי
  List<(String, DateTime)> _options(AppLocalizations t) {
    final yz = _yz;
    final fri = yz.subtract(Duration(days: (yz.weekday - DateTime.friday) % 7));
    final sun = yz.add(Duration(days: (DateTime.sunday - yz.weekday) % 7));
    return [
      if (yz.weekday != DateTime.saturday) (t.azYahrzeit, yz),
      if (fri != yz) (t.azFriBefore, fri),
      if (sun != yz) (t.azSunAfter, sun),
    ];
  }

  @override
  void initState() {
    super.initState();
    final yz = _yz;
    _day = yz.weekday == DateTime.saturday ? yz.subtract(const Duration(days: 1)) : yz;
  }

  Azkara get _az => Azkara(widget.cemetery.id, widget.deceased.id,
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute), _atGrave, _note.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = widget.deceased;
    final opts = _options(t);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.azTitle),
          Text(t.azFor(d.fullName), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t.azDate, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 6),
        for (final (label, day) in opts)
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _sameDay(day, _day) ? cs.primary : Colors.transparent, width: 2)),
            child: ListTile(
              title: Text(dayLine(t, day), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(label),
              trailing: _sameDay(day, _day) ? Icon(Icons.check_circle, color: cs.primary) : null,
              onTap: () => setState(() => _day = day),
            ),
          ),
        if (!opts.any((o) => _sameDay(o.$2, _day)))
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.primary, width: 2)),
            child: ListTile(
                title: Text(dayLine(t, _day), style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Icon(Icons.check_circle, color: cs.primary)),
          ),
        TextButton.icon(
          onPressed: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: _day,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 800)),
            );
            if (p != null) setState(() => _day = p);
          },
          icon: const Icon(Icons.calendar_month),
          label: Text(t.azOtherDate),
        ),
        if (_day.weekday == DateTime.saturday)
          Text(t.azShabbat, style: const TextStyle(color: Color(0xFFB3412F))),
        const SizedBox(height: 10),
        Text(t.azTime, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await showTimePicker(context: context, initialTime: _time);
            if (p != null) setState(() => _time = p);
          },
          icon: const Icon(Icons.schedule),
          label: Text('${_2(_time.hour)}:${_2(_time.minute)}', style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 14),
        Text(t.azPlace, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(t.azAtGrave)),
            ButtonSegment(value: false, label: Text(t.azAtEntrance)),
          ],
          selected: {_atGrave},
          onSelectionChanged: (s) => setState(() => _atGrave = s.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          maxLength: 200,
          maxLines: 2,
          decoration: InputDecoration(labelText: t.azNote, hintText: t.azNoteHint, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _day.weekday == DateTime.saturday ? null : () {
            final text = inviteText(t, _az, d, widget.cemetery);
            launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.chat),
          label: Text(t.azSendWa, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _day.weekday == DateTime.saturday
              ? null
              : () => shareInvite(context, inviteText(t, _az, d, widget.cemetery), t.azInviteTitle(d.fullName)),
          icon: const Icon(Icons.share_outlined),
          label: Text(t.azSendOther),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AzkaraInviteScreen(azkara: _az, deceased: d, cemetery: widget.cemetery))),
          icon: const Icon(Icons.visibility_outlined),
          label: Text(t.azPreview),
        ),
      ]),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

/// ההזמנה כפי שמקבלים אותה
class AzkaraInviteScreen extends StatelessWidget {
  final Azkara azkara;
  final Deceased deceased;
  final Cemetery cemetery;
  const AzkaraInviteScreen({super.key, required this.azkara, required this.deceased, required this.cemetery});

  /// פתיחה מקישור
  static Future<void> open(NavigatorState nav, Azkara a) async {
    try {
      final d = await Repo.deceased(a.id);
      final c = (await Repo.cemeteries()).where((x) => x.id == a.cem).firstOrNull;
      if (d != null && c != null) {
        nav.push(MaterialPageRoute(builder: (_) => AzkaraInviteScreen(azkara: a, deceased: d, cemetery: c)));
      }
    } catch (_) {}
  }

  void _calendar(AppLocalizations t) {
    final s = azkara.when, e = s.add(const Duration(hours: 1));
    String f(DateTime x) => '${x.year}${_2(x.month)}${_2(x.day)}T${_2(x.hour)}${_2(x.minute)}00';
    final u = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': t.azInviteTitle(deceased.fullName),
      'dates': '${f(s)}/${f(e)}',
      'ctz': 'Asia/Jerusalem',
      'details': '${azkara.note}\n${azkara.url}'.trim(),
      'location': '${cemetery.name}, ${locLine(t, deceased)}',
    });
    launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = deceased;
    final past = azkara.when.isBefore(DateTime.now().subtract(const Duration(hours: 3)));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2B1E00),
        foregroundColor: Colors.white,
        title: Text('🕯️ ${t.azInviteTitle(d.fullName)}', overflow: TextOverflow.ellipsis),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${dayLine(t, azkara.when)}, ${hhmm(azkara.when)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if (past) Text(t.azPast, style: const TextStyle(color: Color(0xFFB3412F))),
              const SizedBox(height: 8),
              Text('📍 ${azkara.atGrave ? t.azAtGrave : t.azAtEntrance} – ${cemetery.name}'),
              if (azkara.atGrave) Text(locLine(t, d), style: TextStyle(color: cs.onSurfaceVariant)),
              if (azkara.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(azkara.note, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(deceased: d, cemetery: cemetery))),
          icon: const Icon(Icons.explore),
          label: Text(t.azNavigate, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => _calendar(t), icon: const Icon(Icons.event), label: Text(t.azCalendar))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final q = Uri(queryParameters: {
                  'n': d.firstName ?? '',
                  'p': d.mother ?? d.father ?? '',
                  't': (d.mother ?? '').isNotEmpty ? 'm' : 'f',
                }).query;
                launchUrl(Uri.parse('$webBase/tefilon/?$q'), mode: LaunchMode.inAppBrowserView);
              },
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(t.tefilon),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final c = cemetery.center;
            if (c == null) return;
            launchUrl(Uri.parse('https://waze.com/ul?ll=${c.latitude},${c.longitude}&navigate=yes'),
                mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.directions_car_outlined),
          label: Text(t.drive),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => shareInvite(context, inviteText(t, azkara, d, cemetery), t.azInviteTitle(d.fullName)),
          icon: const Icon(Icons.share_outlined),
          label: Text(t.azForward),
        ),
      ]),
    );
  }
}
