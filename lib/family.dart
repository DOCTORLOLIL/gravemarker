// "המשפחה שלי" (בטא, מוסתר): קישור נפטרים למכשיר בלי הרשמה, והתראות על יארצייט, נזק, אזכרה ותמונה
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'data.dart';
import 'reminders.dart';

const famTask = 'famCheck';

/// רץ ברקע (גם כשהאפליקציה סגורה) – בודק אם יש אירועים חדשים
@pragma('vm:entry-point')
void familyDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Family.check();
    } catch (_) {}
    return true;
  });
}

class Family {
  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  /// מופעל רק במכשיר שהפעילו בו את הבטא (7 הקשות על "גרסה" בתפריט)
  static Future<bool> enabled() async => (await _p).getBool('famBeta') ?? false;
  static Future<bool> toggleBeta() async {
    final p = await _p, v = !(p.getBool('famBeta') ?? false);
    await p.setBool('famBeta', v);
    if (v) await start(); else await Workmanager().cancelByUniqueName(famTask);
    return v;
  }

  static Future<String> device() async {
    final p = await _p;
    var d = p.getString('famDev');
    if (d == null) {
      final r = Random.secure();
      d = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      await p.setString('famDev', d);
    }
    return d;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final s = (await _p).getString('famList');
    return s == null ? [] : List<Map<String, dynamic>>.from(jsonDecode(s));
  }

  static Future<bool> isIn(int id) async => (await list()).any((x) => x['id'] == id);

  // סוגי התראות: yz יארצייט, damage נזק, azkara אזכרה, photo תמונה
  static Future<bool> pref(String k) async => (await _p).getBool('fam_$k') ?? true;
  static Future<void> setPref(String k, bool v) async {
    await (await _p).setBool('fam_$k', v);
    if (k == 'yz') await Reminders.reschedule();
  }

  static Future<dynamic> _rpc(String fn, Map<String, dynamic> args) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final rq = await c.postUrl(Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'));
      rq.headers
        ..set('apikey', supabaseKey)
        ..set('Authorization', 'Bearer $supabaseKey')
        ..contentType = ContentType.json;
      rq.add(utf8.encode(jsonEncode(args)));
      final rs = await rq.close();
      final body = await rs.transform(utf8.decoder).join();
      if (rs.statusCode >= 300) throw Exception(body);
      return body.isEmpty ? null : jsonDecode(body);
    } finally {
      c.close();
    }
  }

  /// הוספה/הסרה. מחזיר כמה מכשירים מקושרים עכשיו לנפטר
  static Future<int> follow(Deceased d, bool on) async {
    final n = await _rpc('family_follow', {'p_dev': await device(), 'p_id': d.id, 'p_on': on});
    final l = await list()..removeWhere((x) => x['id'] == d.id);
    if (on) {
      l.add({'id': d.id, 'cem': d.cemeteryId, 'name': d.fullName, 'death': d.deathDate, 'plot': d.plot});
      await Reminders.askPermission();
    }
    await (await _p).setString('famList', jsonEncode(l));
    await Reminders.reschedule();
    if (l.isNotEmpty) await start();
    return (n as num?)?.toInt() ?? 0;
  }

  static Future<int> count(int id) async {
    try {
      return ((await _rpc('family_count', {'p_id': id})) as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// שולח את פרטי האזכרה לכל המקושרים. מחזיר כמה יקבלו
  static Future<int> sendAzkara(int id, String body) async =>
      ((await _rpc('family_azkara', {'p_id': id, 'p_body': body})) as num?)?.toInt() ?? 0;

  /// אירועים אחרונים (30 יום) לכל נפטר – לתגיות ברשימה
  static Future<Map<String, dynamic>> recent() async {
    final s = (await _p).getString('famRecent');
    return s == null ? {} : Map<String, dynamic>.from(jsonDecode(s));
  }

  static Future<void> _remember(int did, String kind, String body, String at) async {
    final m = await recent();
    final cut = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final l = [...List.from(m['$did'] ?? []), {'kind': kind, 'body': body, 'at': at}]
        .where((x) => (x['at'] as String).compareTo(cut) > 0).toList();
    m['$did'] = l;
    await (await _p).setString('famRecent', jsonEncode(m));
  }

  /// בדיקת רקע כל חצי שעה בערך
  static Future<void> start() async {
    if (!await enabled() || (await list()).isEmpty) return;
    await Workmanager().initialize(familyDispatcher);
    await Workmanager().registerPeriodicTask(famTask, famTask,
        frequency: const Duration(minutes: 30), constraints: Constraints(networkType: NetworkType.connected));
  }

  /// אירועים חדשים → התראה בטלפון
  static Future<void> check() async {
    if (!await enabled()) return;
    final l = await list();
    if (l.isEmpty) return;
    final p = await _p;
    final after = p.getInt('famLast') ?? 0;
    final rows = await _rpc('family_feed', {'p_dev': await device(), 'p_after': after}) as List? ?? [];
    var last = after;
    for (final e in rows.cast<Map<String, dynamic>>()) {
      final id = (e['id'] as num).toInt();
      if (id > last) last = id;
      final kind = e['kind'] as String? ?? '';
      await _remember((e['deceased_id'] as num).toInt(), kind, (e['body'] as String?) ?? '', e['created_at'] as String? ?? '');
      if (!await pref(kind)) continue;
      final did = (e['deceased_id'] as num).toInt();
      final m = l.where((x) => x['id'] == did).firstOrNull;
      if (m == null) continue;
      final name = m['name'] ?? '';
      final body = (e['body'] as String?) ?? '';
      final (title, text) = switch (kind) {
        'azkara' => ('📅 נקבעה אזכרה – $name', body),
        'damage' => ('⚠ דווח נזק במצבה – $name', body.isEmpty ? 'חברה קדישא קיבלה את הדיווח.' : '"$body"\nחברה קדישא קיבלה את הדיווח.'),
        'photo' => ('📷 נוספה תמונה של המצבה – $name', 'לחצו כדי לראות.'),
        _ => ('Grave Marker – $name', body),
      };
      await Reminders.showNow(900000000 + id % 100000000, title, text, '$did|${m['cem']}');
    }
    if (last != after) await p.setInt('famLast', last);
  }
}
