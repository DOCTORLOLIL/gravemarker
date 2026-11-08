import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../l10n/app_localizations.dart';
import 'detail.dart';
import 'welcome.dart';

String dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String subLine(AppLocalizations t, Deceased d) {
  final p = <String>[
    if ((d.father ?? '').isNotEmpty) t.fatherName(d.father!),
    if ((d.mother ?? '').isNotEmpty) t.motherName(d.mother!),
  ];
  final dates = [
    if ((d.deathHebrew ?? '').isNotEmpty) d.deathHebrew!,
    if (d.death != null) dmy(d.death!),
  ];
  return [p.join(' · '), dates.join(' · ')].where((s) => s.isNotEmpty).join(' | ');
}

String locLine(AppLocalizations t, Deceased d) =>
    d.plot == null ? t.locUnknown : t.locLine(d.plot!, d.row ?? '—', d.grave ?? '—');

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  List<Cemetery> _cems = [];
  Cemetery? _cem;
  List<Deceased>? _res;
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cems = await Repo.cemeteries();
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('cem');
      setState(() {
        _cems = cems;
        _cem = cems.where((c) => c.id == last).firstOrNull ?? cems.firstOrNull;
      });
    } catch (_) {
      if (mounted) setState(() => _msg = AppLocalizations.of(context).loadError);
    }
  }

  Future<void> _search() async {
    final t = AppLocalizations.of(context);
    final raw = _q.text.trim();
    if (raw.isEmpty || _cem == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _msg = t.searching;
      _res = null;
    });
    try {
      final r = await Repo.search(_cem!.id, raw);
      setState(() {
        _res = r;
        _msg = r.isEmpty ? t.noResults : (r.length >= 60 ? t.tooMany : t.resultsCount(r.length));
      });
    } catch (_) {
      setState(() => _msg = t.loadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_cems.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: DropdownButton<String>(
                value: _cem?.id,
                underline: const SizedBox(),
                items: [for (final c in _cems) DropdownMenuItem(value: c.id, child: Text(c.town))],
                onChanged: (id) async {
                  final c = _cems.firstWhere((x) => x.id == id);
                  (await SharedPreferences.getInstance()).setString('cem', c.id);
                  setState(() {
                    _cem = c;
                    _res = null;
                  });
                  if (_q.text.trim().isNotEmpty) _search();
                },
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: t.searchHint,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _search,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(t.search),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(_msg ?? t.searchHelp, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: (_res?.length ?? 0) + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                if (i == (_res?.length ?? 0)) {
                  return TextButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const WelcomeScreen(popOnly: true))),
                    child: Text(t.blessingLink, style: TextStyle(color: cs.onSurfaceVariant)),
                  );
                }
                final d = _res![i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => DetailScreen(deceased: d, cemetery: _cem!))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.fullName + ((d.altName ?? '').isNotEmpty ? ' (${d.altName})' : ''),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(subLine(t, d), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                          child: Text(locLine(t, d),
                              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
