import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n/app_localizations.dart';
import '../offline.dart';
import '../lang.dart';
import '../update.dart';
import '../stats.dart';
import 'contacts.dart';
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
  DateTime? _savedAt;
  int? _saveN;
  (int, String)? _update; // מספר הרשומות שנשמרו עד כה (בזמן שמירה)

  Future<void> _refreshSaved() async {
    final c = _cem;
    if (c == null) return;
    final at = await Offline.savedAt(c.id);
    if (mounted && _cem?.id == c.id) setState(() => _savedAt = at);
    // עדכון אוטומטי של השמירה פעם בשבוע, כדי שנפטרים חדשים יופיעו גם בלי קליטה
    if (at != null && DateTime.now().difference(at).inDays >= 7 && !Repo.offline && _saveN == null) {
      try {
        await Offline.save(c, (_) {});
        final now = await Offline.savedAt(c.id);
        if (mounted && _cem?.id == c.id) setState(() => _savedAt = now);
      } catch (_) {}
    }
  }

  static const _langNames = {'he': 'עברית', 'en': 'English', 'fr': 'Français', 'ru': 'Русский', 'am': 'አማርኛ'};

  void _pickLang() {
    final t = AppLocalizations.of(context);
    final cur = Localizations.localeOf(context).languageCode;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(t.language == 'Language' ? 'Language' : '${t.language} · Language',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          for (final code in langs)
            ListTile(
              title: Text(_langNames[code]!,
                  style: code == cur ? TextStyle(color: cs.primary, fontWeight: FontWeight.bold) : null),
              trailing: code == cur && appLang.value != null ? Icon(Icons.check, color: cs.primary) : null,
              onTap: () {
                Navigator.pop(c);
                setLang(code);
              },
            ),
          ListTile(
            title: Text(t.langPhone, style: TextStyle(color: cs.onSurfaceVariant)),
            trailing: appLang.value == null ? Icon(Icons.check, color: cs.primary) : null,
            onTap: () {
              Navigator.pop(c);
              setLang(null);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _saveOffline() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final c = _cem;
    if (c == null || _saveN != null) return;
    setState(() => _saveN = 0);
    try {
      await Offline.save(c, (n) {
        if (mounted) setState(() => _saveN = n);
      });
      messenger.showSnackBar(SnackBar(content: Text(t.offlineDone)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.offlineFailed)));
    } finally {
      if (mounted) setState(() => _saveN = null);
      _refreshSaved();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) pingInstall(Localizations.localeOf(context).languageCode);
    });
    checkUpdate().then((u) {
      if (u != null && mounted) setState(() => _update = u);
    });
  }

  Future<void> _load() async {
    try {
      final cems = await Repo.cemeteries();
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('cem');
      setState(() {
        _cems = cems;
        _cem = cems.where((c) => c.id == last).firstOrNull ?? cems.firstOrNull;
        if (Repo.offline) _msg = AppLocalizations.of(context).offlineMode;
      });
      _refreshSaved();
    } catch (_) {
      if (mounted) setState(() => _msg = AppLocalizations.of(context).noOfflineData);
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
        _msg = (Repo.offline ? '${t.offlineMode}\n' : '') +
            (r.isEmpty ? t.noResults : (r.length >= 60 ? t.tooMany : t.resultsCount(r.length)));
      });
    } catch (_) {
      setState(() => _msg = _savedAt == null ? t.noOfflineData : t.loadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _intro(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      (Icons.explore_outlined, t.featNav, t.featNavSub),
      (Icons.event_outlined, t.featYz, t.featYzSub),
      (Icons.menu_book_outlined, t.featTef, t.featTefSub),
      (Icons.share_outlined, t.featShare, t.featShareSub),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      if (_cem != null)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(_savedAt == null ? Icons.download_for_offline_outlined : Icons.offline_pin_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.offlineTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    _saveN != null
                        ? t.offlineSaving('$_saveN')
                        : _savedAt == null
                            ? t.offlineBody
                            : t.offlineSaved(_cem!.town, dmy(_savedAt!)),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _saveN != null ? null : _saveOffline,
                child: Text(_savedAt == null ? t.offlineSave : t.offlineUpdate),
              ),
            ]),
          ),
        ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
        children: [
          for (final (icon, title, sub) in items)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Icon(icon, color: cs.primary),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: () => launchUrl(Uri.parse('https://bulu.ltd'), mode: LaunchMode.externalApplication),
          child: Text(t.builtBy, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
      ),
    ]);
  }

  Widget _drawer(BuildContext context, AppLocalizations t) {
    void go(Widget w) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    }

    void web(String url) {
      Navigator.of(context).pop();
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(children: [
          ListTile(
            leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(width: 36, height: 36, color: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.place, color: Colors.white))),
            title: Text(t.appTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(t.tagline),
          ),
          const Divider(),
          if (_cem != null)
            ListTile(leading: const Icon(Icons.contacts_outlined), title: Text(t.contacts), onTap: () => go(ContactsScreen(cemetery: _cem!))),
          ListTile(leading: const Icon(Icons.auto_stories_outlined), title: Text(t.blessingLink), onTap: () => go(const WelcomeScreen(popOnly: true))),
          ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text(t.tefilon), onTap: () => web('$webBase/tefilon/')),
          ListTile(leading: const Icon(Icons.local_florist_outlined), title: Text(t.ashkava), onTap: () => web('$webBase/ashkava/')),
          ListTile(leading: const Icon(Icons.language), title: Text(t.website), onTap: () => web(webBase)),
          const Divider(),
          ListTile(leading: const Icon(Icons.edit_location_alt_outlined), title: Text(t.editors), onTap: () {
                Navigator.of(context).pop();
                // נפתח בתוך האפליקציה; הכניסה לחשבון נשמרת
                launchUrl(Uri.parse('$webBase/marker/'), mode: LaunchMode.inAppBrowserView);
              }),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text('${t.language} · ${t.langName}'),
            onTap: () {
              Navigator.of(context).pop();
              _pickLang();
            },
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(t.feedback),
            onTap: () => launchUrl(Uri.parse('mailto:ceo@bulu.ltd?subject=${Uri.encodeComponent('Grave Marker – ${t.feedback}')}')),
          ),
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t.privacy), onTap: () => web('$webBase/privacy/')),
          ListTile(leading: const Icon(Icons.info_outline), title: Text(t.builtBy), onTap: () => web('https://bulu.ltd')),
          if (appBuild > 0)
            ListTile(
              dense: true,
              leading: const Icon(Icons.system_update_outlined),
              title: Text(t.version('$appBuild')),
              onTap: () => web('$webBase/download/'),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: _drawer(context, t),
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
                    _savedAt = null;
                  });
                  _refreshSaved();
                  if (_q.text.trim().isNotEmpty) _search();
                },
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_update != null)
            // בולט בצבע הזהב של הסיכה, כדי שלא ייבלע בצבעי האפליקציה
            Container(
              color: const Color(0xFFE0A83A),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                const Icon(Icons.system_update, color: Color(0xFF2B1E00), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.updateAvail,
                      style: const TextStyle(color: Color(0xFF2B1E00), fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF2B1E00)),
                  onPressed: () {
                    skipUpdate(_update!.$1);
                    setState(() => _update = null);
                  },
                  child: Text(t.notNowUpdate),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2B1E00), foregroundColor: Colors.white),
                  onPressed: () => launchUrl(Uri.parse(_update!.$2), mode: LaunchMode.externalApplication),
                  child: Text(t.update),
                ),
              ]),
            ),
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
            child: _res == null
                ? _intro(context, t)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _res!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
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
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                                child: Text(locLine(t, d), style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
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
