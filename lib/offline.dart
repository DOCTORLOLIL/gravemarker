import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';

/// שמירת בית עלמין בטלפון לשימוש בלי קליטה
class Offline {
  static final Map<String, List<Deceased>> _mem = {};

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<DateTime?> savedAt(String cemId) async {
    final ms = (await SharedPreferences.getInstance()).getInt('off:$cemId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> save(Cemetery cem, void Function(int n) progress) async {
    final all = <Map<String, dynamic>>[];
    for (var from = 0;; from += 1000) {
      final r = await db
          .from('deceased')
          .select(deceasedCols)
          .eq('cemetery_id', cem.id)
          .order('id')
          .range(from, from + 999);
      final rows = List<Map<String, dynamic>>.from(r as List);
      all.addAll(rows);
      progress(all.length);
      if (rows.length < 1000) break;
    }
    await (await _file('deceased_${cem.id}.json')).writeAsString(jsonEncode(all));
    final plots = await db.from('plots').select('gush,plot,boundary').eq('cemetery_id', cem.id);
    await (await _file('plots_${cem.id}.json')).writeAsString(jsonEncode(plots));
    final cems = await db.from('cemeteries').select().order('name');
    await (await _file('cemeteries.json')).writeAsString(jsonEncode(cems));
    if (cem.overlayUrl != null) {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(cem.overlayUrl!));
        final res = await req.close();
        if (res.statusCode == 200) {
          final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
          await (await _file('overlay_${cem.id}.jpg')).writeAsBytes(bytes);
        }
      } finally {
        client.close();
      }
    }
    _mem[cem.id] = all.map(Deceased.fromJson).toList();
    (await SharedPreferences.getInstance()).setInt('off:${cem.id}', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Deceased>?> deceased(String cemId) async {
    if (_mem[cemId] != null) return _mem[cemId];
    final f = await _file('deceased_$cemId.json');
    if (!await f.exists()) return null;
    final list = (jsonDecode(await f.readAsString()) as List).map((e) => Deceased.fromJson(e)).toList();
    return _mem[cemId] = list;
  }

  static Future<List<Plot>?> plots(String cemId) async {
    final f = await _file('plots_$cemId.json');
    if (!await f.exists()) return null;
    return (jsonDecode(await f.readAsString()) as List).map((e) => Plot.fromJson(e)).toList();
  }

  static Future<List<Cemetery>?> cemeteries() async {
    final f = await _file('cemeteries.json');
    if (!await f.exists()) return null;
    return (jsonDecode(await f.readAsString()) as List).map((e) => Cemetery.fromJson(e)).toList();
  }

  static Future<File?> overlay(String cemId) async {
    final f = await _file('overlay_$cemId.jpg');
    return await f.exists() ? f : null;
  }

  static List<Deceased> search(List<Deceased> all, List<String> names, List<String> years) {
    bool has(Deceased d, String w) =>
        [d.lastName, d.firstName, d.altName, d.father, d.mother].any((f) => (f ?? '').contains(w));
    final res = all
        .where((d) =>
            names.every((w) => has(d, w)) && years.every((y) => (d.deathDate ?? '').startsWith(y)))
        .toList()
      ..sort((a, b) {
        final c = (a.lastName ?? '').compareTo(b.lastName ?? '');
        return c != 0 ? c : (a.firstName ?? '').compareTo(b.firstName ?? '');
      });
    return res.take(60).toList();
  }
}
