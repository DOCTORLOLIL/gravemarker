import 'package:flutter/material.dart';

import '../data.dart';
import '../family.dart';
import '../hebcal.dart';
import '../reminders.dart';
import 'detail.dart';

/// "המשפחה שלי" (בטא). הטקסטים בעברית בלבד עד שהפיצ'ר יפורסם.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _recent = {};
  final Map<String, bool> _prefs = {};
  bool _loading = true;

  static const _kinds = [
    ('yz', 'יארצייט (שבוע לפני ויום לפני)'),
    ('damage', 'דיווח נזק במצבה'),
    ('azkara', 'אזכרה שנקבעה'),
    ('photo', 'תמונה חדשה של המצבה'),
  ];

  @override
  void initState() {
    super.initState();
    _load(check: true);
  }

  Future<void> _load({bool check = false}) async {
    if (check) {
      try {
        await Family.check();
      } catch (_) {}
    }
    final l = await Family.list(), r = await Family.recent();
    for (final (k, _) in _kinds) {
      _prefs[k] = await Family.pref(k);
    }
    if (mounted) setState(() {
      _list = l..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      _recent = r;
      _loading = false;
    });
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        margin: const EdgeInsetsDirectional.only(end: 6, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
      );

  List<Widget> _tags(Map<String, dynamic> m) {
    final out = <Widget>[];
    final death = DateTime.tryParse(m['death'] ?? '');
    if (death != null) {
      final y = HebCal.nextYahrzeits(death, count: 1).first;
      final today = DateTime.now();
      final n = DateTime(y.date.year, y.date.month, y.date.day).difference(DateTime(today.year, today.month, today.day)).inDays;
      final h = HebCal.format(y.heb).split(' ');
      final txt = n == 0 ? 'היום' : n == 1 ? 'הערב ומחר' : n <= 30 ? 'בעוד $n ימים' : h.take(h.length - 1).join(' ');
      out.add(_tag('🕯️ יארצייט $txt', const Color(0xFFFFF1D6), const Color(0xFF8A5A00)));
    }
    for (final e in List.from(_recent['${m['id']}'] ?? []).reversed.take(2)) {
      final at = DateTime.tryParse(e['at'] ?? '')?.toLocal();
      final d = at == null ? '' : ' (${at.day}/${at.month})';
      switch (e['kind']) {
        case 'damage':
          out.add(_tag('⚠ דווח נזק$d', const Color(0xFFFDE3DC), const Color(0xFFAA3333)));
        case 'azkara':
          out.add(_tag('📅 נקבעה אזכרה$d', const Color(0xFFE1EFE9), const Color(0xFF1F5B57)));
        case 'photo':
          out.add(_tag('📷 תמונה חדשה$d', const Color(0xFFE8EEF7), const Color(0xFF2A4F80)));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('👨‍👩‍👧 המשפחה שלי')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(check: true),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (_list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('עוד לא הוספתם נפטרים.\nפתחו כרטיס נפטר ולחצו "הוסף ל\'המשפחה שלי\'".',
                        textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                for (final m in _list)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => openFromReminder(Navigator.of(context), m['id'] as int, m['cem'] as String,
                          (d, c) => DetailScreen(deceased: d, cemetery: c)).then((_) => _load()),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m['name']} ז"ל', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if ((m['plot'] ?? '').toString().isNotEmpty)
                            Text('חלקה ${m['plot']}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          Wrap(children: _tags(m)),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      const ListTile(dense: true, title: Text('🔔 מה לקבל', style: TextStyle(fontWeight: FontWeight.bold))),
                      for (final (k, label) in _kinds)
                        SwitchListTile(
                          dense: true,
                          title: Text(label),
                          value: _prefs[k] ?? true,
                          onChanged: (v) async {
                            await Family.setPref(k, v);
                            setState(() => _prefs[k] = v);
                          },
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('בלי הרשמה – הרשימה שמורה במכשיר הזה. ההתראות מגיעות גם כשהאפליקציה סגורה (בדיקה כל חצי שעה בערך).',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
              ]),
            ),
    );
  }
}

/// כפתור בכרטיס הנפטר
class FamilyButton extends StatefulWidget {
  final Deceased deceased;
  const FamilyButton({super.key, required this.deceased});
  @override
  State<FamilyButton> createState() => _FamilyButtonState();
}

class _FamilyButtonState extends State<FamilyButton> {
  bool _beta = false, _in = false, _busy = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    () async {
      final b = await Family.enabled();
      if (!b) return;
      final i = await Family.isIn(widget.deceased.id), c = await Family.count(widget.deceased.id);
      if (mounted) setState(() {
        _beta = true;
        _in = i;
        _count = c;
      });
    }();
  }

  Future<void> _toggle() async {
    final m = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final c = await Family.follow(widget.deceased, !_in);
      setState(() {
        _in = !_in;
        _count = c;
      });
      m.showSnackBar(SnackBar(content: Text(_in ? 'נוסף ל"המשפחה שלי". תקבלו התראות על הנפטר.' : 'הוסר מ"המשפחה שלי".')));
    } catch (_) {
      m.showSnackBar(const SnackBar(content: Text('לא הצלחנו. בדקו חיבור לאינטרנט ונסו שוב.')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_beta) return const SizedBox.shrink();
    final others = _in ? _count - 1 : _count;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _in
            ? FilledButton.tonalIcon(
                onPressed: _busy ? null : _toggle, icon: const Icon(Icons.family_restroom), label: const Text('✓ במשפחה שלי'))
            : FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: plotGold, foregroundColor: const Color(0xFF2B1E00)),
                onPressed: _busy ? null : _toggle,
                icon: const Icon(Icons.family_restroom),
                label: const Text('הוסף ל"המשפחה שלי"', style: TextStyle(fontWeight: FontWeight.bold))),
        if (others > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(others == 1 ? 'עוד בן משפחה אחד מקושר לכרטיס הזה' : 'עוד $others בני משפחה מקושרים לכרטיס הזה',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
