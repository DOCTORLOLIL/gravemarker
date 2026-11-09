import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline.dart';

const supabaseUrl = 'https://vqydrrhgklikhfdsgrwr.supabase.co';
const supabaseKey = 'sb_publishable_w6o5yCjbhBkuJ2FREujpHA_1V8ZcY0C'; // מפתח ציבורי – מותר באפליקציה
const webBase = 'https://gravemarker.bulu.ltd';

SupabaseClient get db => Supabase.instance.client;

class Cemetery {
  final String id, name, town;
  final double? lat, lng;
  final String? overlayUrl;
  final List<LatLng>? overlayCorners; // TL, TR, BL
  Cemetery.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'] ?? '',
        town = j['town'] ?? '',
        lat = (j['center_lat'] as num?)?.toDouble(),
        lng = (j['center_lng'] as num?)?.toDouble(),
        overlayUrl = j['overlay_url'],
        overlayCorners = (j['overlay_corners'] as List?)
            ?.map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList();
  LatLng? get center => lat == null || lng == null ? null : LatLng(lat!, lng!);
}

class Plot {
  final String gush, plot;
  final List<LatLng>? ring;
  Plot.fromJson(Map<String, dynamic> j)
      : gush = (j['gush'] ?? '1').toString(),
        plot = j['plot'].toString(),
        ring = ((j['boundary'] as Map?)?['coordinates'] as List?)?.first is List
            ? ((j['boundary']['coordinates'] as List).first as List)
                .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList()
            : null;
}

class Deceased {
  final int id;
  final String cemeteryId;
  final String? firstName, lastName, altName, father, mother, gush, plot, row, grave, deathDate, deathHebrew;
  Deceased.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        cemeteryId = j['cemetery_id'] ?? '',
        firstName = j['first_name'],
        lastName = j['last_name'],
        altName = j['alt_name'],
        father = j['father_name'],
        mother = j['mother_name'],
        gush = j['gush']?.toString(),
        plot = j['plot']?.toString(),
        row = j['row_no']?.toString(),
        grave = j['grave_no']?.toString(),
        deathDate = j['death_date'],
        deathHebrew = j['death_date_hebrew'];
  String get fullName => [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');
  DateTime? get death => deathDate == null ? null : DateTime.tryParse(deathDate!);
  String get shareUrl => '$webBase/?c=$cemeteryId&d=$id';
}

const deceasedCols =
    'id,cemetery_id,first_name,last_name,alt_name,father_name,mother_name,gush,plot,row_no,grave_no,death_date,death_date_hebrew';

class Repo {
  /// true כשהנתון האחרון הגיע מהשמירה בטלפון
  static bool offline = false;

  static Future<List<Cemetery>> cemeteries() async {
    try {
      final r = await db.from('cemeteries').select().order('name').timeout(const Duration(seconds: 8));
      offline = false;
      return (r as List).map((e) => Cemetery.fromJson(e)).toList();
    } catch (e) {
      final c = await Offline.cemeteries();
      if (c == null) rethrow;
      offline = true;
      return c;
    }
  }

  static Future<List<Plot>> plots(String cemeteryId) async {
    try {
      final r = await db
          .from('plots')
          .select('gush,plot,boundary')
          .eq('cemetery_id', cemeteryId)
          .timeout(const Duration(seconds: 8));
      return (r as List).map((e) => Plot.fromJson(e)).toList();
    } catch (e) {
      final p = await Offline.plots(cemeteryId);
      if (p == null) rethrow;
      return p;
    }
  }

  /// חיפוש: המילה הארוכה בשרת, השאר מסוננות במכשיר
  static Future<List<Deceased>> search(String cemeteryId, String raw) async {
    final words = raw
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'''[^֐-׿a-zA-Z0-9\-]'''), ''))
        .where((w) => w.isNotEmpty)
        .take(4)
        .toList();
    if (words.isEmpty) return [];
    final years = words.where((w) => RegExp(r'^\d{4}$').hasMatch(w)).toList();
    final names = words.where((w) => !years.contains(w)).toList()..sort((a, b) => b.length - a.length);
    final local = await Offline.deceased(cemeteryId);
    try {
      return await _searchServer(cemeteryId, names, years).timeout(const Duration(seconds: 8));
    } catch (e) {
      if (local == null) rethrow;
      offline = true;
      return Offline.search(local, names, years);
    }
  }

  static Future<List<Deceased>> _searchServer(String cemeteryId, List<String> names, List<String> years) async {
    var q = db.from('deceased').select(deceasedCols).eq('cemetery_id', cemeteryId);
    if (names.isNotEmpty) {
      final p = '*${names.first}*';
      q = q.or('last_name.ilike.$p,first_name.ilike.$p,alt_name.ilike.$p,father_name.ilike.$p,mother_name.ilike.$p');
    }
    for (final y in years) {
      q = q.gte('death_date', '$y-01-01').lte('death_date', '$y-12-31');
    }
    final r = await q.order('last_name').order('first_name').limit(400);
    final all = (r as List).map((e) => Deceased.fromJson(e)).toList();
    bool has(Deceased d, String w) =>
        [d.lastName, d.firstName, d.altName, d.father, d.mother].any((f) => (f ?? '').contains(w));
    offline = false;
    return all.where((d) => names.skip(1).every((w) => has(d, w))).take(60).toList();
  }

  static Future<Deceased?> deceased(int id) async {
    final r = await db.from('deceased').select(deceasedCols).eq('id', id).maybeSingle();
    return r == null ? null : Deceased.fromJson(r);
  }

  static List<(int, int)> _sizeOf(Iterable<Deceased> list) =>
      list.map((x) => (int.tryParse(x.row ?? '') ?? 0, int.tryParse(x.grave ?? '') ?? 0)).toList();

  /// מספר השורות בחלקה ומספר הקברים בשורה – לחישוב מיקום משוער
  static Future<(int rows, int graves)?> plotSize(Deceased d) async {
    List<(int, int)> pairs;
    try {
      final r = await db
          .from('deceased')
          .select('row_no,grave_no')
          .eq('cemetery_id', d.cemeteryId)
          .eq('gush', d.gush ?? '1')
          .eq('plot', d.plot!)
          .limit(3000)
          .timeout(const Duration(seconds: 8));
      pairs = (r as List)
          .map((x) => (int.tryParse('${x['row_no']}') ?? 0, int.tryParse('${x['grave_no']}') ?? 0))
          .toList();
    } catch (e) {
      final local = await Offline.deceased(d.cemeteryId);
      if (local == null) return null;
      pairs = _sizeOf(local.where((x) => (x.gush ?? '1') == (d.gush ?? '1') && x.plot == d.plot));
    }
    final row = int.tryParse(d.row ?? '');
    var nRows = 0, maxG = 0, maxGRow = 0;
    for (final (a, b) in pairs) {
      if (a > nRows) nRows = a;
      if (b > 0) {
        if (b > maxG) maxG = b;
        if (a == row && b > maxGRow) maxGRow = b;
      }
    }
    final nG = maxGRow > 0 ? maxGRow : maxG;
    return nRows > 0 && nG > 0 ? (nRows, nG) : null;
  }

  /// מיקום מדויק מהשטח: ממוצע משוקלל לפי דיוק
  static Future<LatLng?> graveLocation(int id) async {
    try {
      final r = await db.from('grave_locations').select('lat,lng,accuracy').eq('deceased_id', id);
      double w = 0, la = 0, lo = 0;
      for (final x in r as List) {
        final acc = ((x['accuracy'] as num?)?.toDouble() ?? 10).clamp(2, 100);
        final k = 1 / (acc * acc);
        w += k;
        la += (x['lat'] as num) * k;
        lo += (x['lng'] as num) * k;
      }
      return w > 0 ? LatLng(la / w, lo / w) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveGraveLocation(int id, double lat, double lng, double accuracy) async {
    try {
      await db.from('grave_locations').insert(
          {'deceased_id': id, 'lat': lat, 'lng': lng, 'accuracy': (accuracy * 10).round() / 10});
      return true;
    } catch (_) {
      return false;
    }
  }
}
