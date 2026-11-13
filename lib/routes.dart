import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'geo.dart';
import 'l10n/app_localizations.dart';

/// מסלול ביקור: כמה קברים בסדר הליכה
class VisitRoute {
  String id, name, cem;
  List<int> ids;
  Set<int> done;
  bool saved;
  /// true אחרי שהמשתמש שינה את הסדר בגרירה (או מסלול ששותף) – לא מסדרים מחדש אוטומטית
  bool manual;
  VisitRoute(
      {required this.id, required this.name, required this.cem, required this.ids, Set<int>? done, this.saved = false, this.manual = false})
      : done = done ?? {};

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'cem': cem, 'ids': ids, 'done': done.toList(), 'saved': saved, 'manual': manual};
  factory VisitRoute.fromJson(Map<String, dynamic> j) => VisitRoute(
        id: j['id'],
        name: j['name'] ?? '',
        cem: j['cem'],
        ids: List<int>.from(j['ids'] ?? []),
        done: Set<int>.from(j['done'] ?? []),
        saved: j['saved'] ?? false,
        manual: j['manual'] ?? false,
      );

  /// קישור לשיתוף – נפתח באפליקציה (אם מותקנת) או באתר
  String get shareUrl =>
      '$webBase/r/?${Uri(queryParameters: {'c': cem, 'ids': ids.join(','), 'n': name}).query}';

  static VisitRoute? fromUri(Uri u) {
    if (!u.path.startsWith('/r')) return null;
    final ids = (u.queryParameters['ids'] ?? '').split(',').map(int.tryParse).whereType<int>().toList();
    final cem = u.queryParameters['c'];
    if (ids.isEmpty || cem == null) return null;
    return VisitRoute(id: _newId(), name: u.queryParameters['n'] ?? '', cem: cem, ids: ids, manual: true);
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

class RouteStore {
  static Future<List<VisitRoute>> all() async {
    final s = (await SharedPreferences.getInstance()).getString('routes');
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => VisitRoute.fromJson(e)).toList();
  }

  static Future<void> _write(List<VisitRoute> list) async =>
      (await SharedPreferences.getInstance()).setString('routes', jsonEncode(list.map((r) => r.toJson()).toList()));

  /// שמירה (גם אוטומטית אחרי כל שינוי)
  static Future<void> put(VisitRoute r) async {
    final list = await all();
    final i = list.indexWhere((x) => x.id == r.id);
    i >= 0 ? list[i] = r : list.add(r);
    await _write(list);
  }

  static Future<void> remove(String id) async {
    final list = await all()..removeWhere((x) => x.id == id);
    await _write(list);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('activeRoute') == id) await prefs.remove('activeRoute');
  }

  /// המסלול הפעיל (אליו מוסיפים מכרטיס הנפטר)
  static Future<VisitRoute?> active() async {
    final id = (await SharedPreferences.getInstance()).getString('activeRoute');
    if (id == null) return null;
    return (await all()).where((r) => r.id == id).firstOrNull;
  }

  static Future<void> setActive(VisitRoute r) async {
    await put(r);
    (await SharedPreferences.getInstance()).setString('activeRoute', r.id);
  }

  /// הוספה/הסרה מהמסלול הפעיל. מחזיר true אם הקבר במסלול עכשיו
  static Future<bool> toggle(Deceased d) async {
    var r = await active();
    if (r != null && r.cem != d.cemeteryId) r = null; // מסלול של בית עלמין אחר – מתחילים חדש
    r ??= VisitRoute(id: _newId(), name: '', cem: d.cemeteryId, ids: []);
    final inNow = !r.ids.contains(d.id);
    inNow ? r.ids.add(d.id) : r.ids.remove(d.id);
    r.done.remove(d.id);
    await setActive(r);
    return inNow;
  }

  static Future<bool> contains(int id) async => (await active())?.ids.contains(id) ?? false;
}

/// שם מוצע: שם המשפחה הנפוץ במסלול, אחרת "ביקור בבית העלמין <מקום> א'"
Future<String> suggestName(AppLocalizations t, List<Deceased> list, Cemetery cem) async {
  final count = <String, int>{};
  for (final d in list) {
    final n = (d.lastName ?? '').trim();
    if (n.isNotEmpty) count[n] = (count[n] ?? 0) + 1;
  }
  if (count.isNotEmpty) {
    final top = count.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (top.value >= 2 || list.length == 1) return t.routeFamily(top.key);
  }
  final taken = (await RouteStore.all()).where((r) => r.saved).map((r) => r.name).toSet();
  const heb = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט', 'י', 'יא', 'יב', 'יג', 'יד', 'טו', 'טז', 'יז', 'יח', 'יט', 'כ'];
  final he = t.localeName == 'he';
  for (var i = 0; i < 200; i++) {
    final n = t.routeGeneric(cem.town, he && i < heb.length ? "${heb[i]}'" : '${i + 1}');
    if (!taken.contains(n)) return n;
  }
  return t.routeGeneric(cem.town, _newId());
}

/// מיקום של קבר: מדויק אם נשמר, אחרת הערכה לפי שורה וקבר, אחרת מרכז החלקה
Future<LatLng?> gravePosition(Deceased d, List<Plot> plots) async {
  try {
    final g = await Repo.graveLocation(d.id);
    if (g != null) return g;
  } catch (_) {}
  final p = plots.where((p) => p.plot == d.plot && p.gush == (d.gush ?? '1') && p.ring != null).firstOrNull;
  if (p == null) return null;
  final row = int.tryParse(d.row ?? ''), grave = int.tryParse(d.grave ?? '');
  if (row != null && grave != null) {
    try {
      final size = await Repo.plotSize(d);
      if (size != null) return estimateGrave(p.ring!, row, grave, size.$1, size.$2);
    } catch (_) {}
  }
  return centroid(p.ring!);
}

/// סדר הליכה קצר: כל פעם לקבר הקרוב ביותר
List<int> shortestOrder(List<int> ids, Map<int, LatLng?> pos, LatLng? start) {
  final left = [...ids];
  final out = <int>[];
  var cur = start;
  while (left.isNotEmpty) {
    int pick = left.first;
    if (cur != null) {
      var best = double.infinity;
      for (final id in left) {
        final p = pos[id];
        final dist = p == null ? 1e9 : meters(cur, p);
        if (dist < best) {
          best = dist;
          pick = id;
        }
      }
    }
    out.add(pick);
    left.remove(pick);
    cur = pos[pick] ?? cur;
  }
  return out;
}

/// אורך המסלול במטרים
double routeLength(List<int> ids, Map<int, LatLng?> pos) {
  var sum = 0.0;
  LatLng? prev;
  for (final id in ids) {
    final p = pos[id];
    if (p != null && prev != null) sum += meters(prev, p);
    if (p != null) prev = p;
  }
  return sum;
}

int roundMeters(double m) => m < 100 ? (m / 5).round() * 5 : (m / 10).round() * 10;
