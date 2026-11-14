import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'l10n/app_localizations.dart';

/// נקודה שימושית בבית העלמין
class Place {
  final String kind;
  final LatLng pos;
  final String? note;
  Place.fromJson(Map<String, dynamic> j)
      : kind = j['kind'],
        pos = LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        note = j['note'];

  String get icon => const {
        'wash': '🚰',
        'tap': '🪣',
        'wc': '🚻',
        'parking': '🅿️',
        'entrance': '🚪',
        'office': '🏢',
        'shade': '🌳',
      }[kind] ??
      '📍';

  String label(AppLocalizations t) => switch (kind) {
        'wash' => t.placeWash,
        'tap' => t.placeTap,
        'wc' => t.placeWc,
        'parking' => t.placeParking,
        'entrance' => t.placeEntrance,
        'office' => t.placeOffice,
        'shade' => t.placeShade,
        _ => kind,
      };
}

class Places {
  static final Map<String, List<Place>> _mem = {};

  static Future<File> _file(String cem) async => File('${(await getApplicationDocumentsDirectory()).path}/places_$cem.json');

  /// נקודות בית העלמין (נשמרות בטלפון גם לשימוש בלי קליטה)
  static Future<List<Place>> of(String cem) async {
    if (_mem[cem] != null) return _mem[cem]!;
    try {
      final r = await db.from('cemetery_places').select('kind,lat,lng,note').eq('cemetery_id', cem).timeout(const Duration(seconds: 8));
      (await _file(cem)).writeAsString(jsonEncode(r));
      return _mem[cem] = (r as List).map((e) => Place.fromJson(e)).toList();
    } catch (_) {
      try {
        final f = await _file(cem);
        if (await f.exists()) {
          return _mem[cem] = (jsonDecode(await f.readAsString()) as List).map((e) => Place.fromJson(e)).toList();
        }
      } catch (_) {}
      return [];
    }
  }

  /// הנקודה הקרובה ביותר מסוג מסוים: (נקודה, מרחק במטרים)
  static (Place, double)? nearest(List<Place> list, String kind, LatLng from) {
    (Place, double)? best;
    for (final p in list.where((p) => p.kind == kind)) {
      final d = const Distance().as(LengthUnit.Meter, from, p.pos);
      if (best == null || d < best.$2) best = (p, d);
    }
    return best;
  }

  /// שעות פתיחה (טקסט חופשי שהעורכים כתבו)
  static Future<String?> hours(String cem) async {
    try {
      final r = await db.from('cemeteries').select('hours').eq('id', cem).maybeSingle().timeout(const Duration(seconds: 8));
      return r?['hours'] as String?;
    } catch (_) {
      return null;
    }
  }
}
