import 'dart:math' as math;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'hebcal.dart';

/// האפליקציה לא פועלת בשבת ובחג: מ-20 דקות לפני השקיעה עד 40 דקות אחרי השקיעה במוצאי השבת/החג (שעון ישראל)
class Shabbat {
  static const _lat = 31.3152, _lng = 34.6103, _before = 20, _after = 40;
  static bool _tz = false;

  static tz.Location get _il {
    if (!_tz) {
      tzdata.initializeTimeZones();
      _tz = true;
    }
    return tz.getLocation('Asia/Jerusalem');
  }

  /// שקיעה (UTC) בתאריך אזרחי
  static DateTime sunset(int y, int m, int d) {
    const r = math.pi / 180;
    final n = (275 * m / 9).floor() - ((m + 9) / 12).floor() * (1 + ((y - 4 * (y / 4).floor() + 2) / 3).floor()) + d - 30;
    const lh = _lng / 15;
    final t = n + (18 - lh) / 24;
    final mm = 0.9856 * t - 3.289;
    var l = mm + 1.916 * math.sin(mm * r) + 0.02 * math.sin(2 * mm * r) + 282.634;
    l = (l % 360 + 360) % 360;
    var ra = math.atan(0.91764 * math.tan(l * r)) / r;
    ra = (ra % 360 + 360) % 360;
    ra = (ra + (l / 90).floor() * 90 - (ra / 90).floor() * 90) / 15;
    final sd = 0.39782 * math.sin(l * r), cd = math.cos(math.asin(sd));
    final h = math.acos((math.cos(90.833 * r) - sd * math.sin(_lat * r)) / (cd * math.cos(_lat * r))) / r / 15;
    var ut = h + ra - 0.06571 * t - 6.622 - lh;
    ut = (ut % 24 + 24) % 24;
    return DateTime.utc(y, m, d).add(Duration(milliseconds: (ut * 3600000).round()));
  }

  /// ימים טובים בארץ ישראל: ראש השנה (2 ימים), יום כיפור, סוכות, שמיני עצרת, פסח ראשון ושביעי, שבועות
  static const _yt = {
    'תשרי': [1, 2, 10, 15, 22],
    'ניסן': [15, 21],
    'סיון': [6],
  };

  static bool holiday(DateTime d) {
    final h = HebCal.toHeb(DateTime(d.year, d.month, d.day));
    return _yt[h.month]?.contains(h.day) ?? false;
  }

  static bool _closed(DateTime d) => d.weekday == DateTime.saturday || holiday(d);
  static DateTime _ss(DateTime d) => sunset(d.year, d.month, d.day);
  static DateTime _add(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

  /// (צאת השבת/החג ב-UTC, האם חג) אם עכשיו סגור, אחרת null
  static (DateTime, bool)? state([DateTime? at]) {
    final now = (at ?? DateTime.now()).toUtc();
    final l = tz.TZDateTime.from(now, _il);
    final x = DateTime.utc(l.year, l.month, l.day);
    DateTime? start;
    if (_closed(x) && now.isBefore(_ss(x).add(const Duration(minutes: _after)))) {
      start = x;
    } else if (_closed(_add(x, 1)) && !now.isBefore(_ss(x).subtract(const Duration(minutes: _before)))) {
      start = _add(x, 1);
    }
    if (start == null) return null;
    var e = start;
    var chag = holiday(start);
    while (_closed(_add(e, 1))) {
      e = _add(e, 1);
      chag = chag || holiday(e);
    }
    for (var b = _add(start, -1); _closed(b); b = _add(b, -1)) {
      chag = chag || holiday(b);
    }
    return (_ss(e).add(const Duration(minutes: _after)), chag);
  }

  /// שעת הפתיחה מחדש (UTC) אם עכשיו סגור, אחרת null
  static DateTime? end([DateTime? at]) => state(at)?.$1;

  /// שעה בישראל, לתצוגה
  static String hhmm(DateTime utc) {
    final x = tz.TZDateTime.from(utc, _il);
    return '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  }

  /// התראה שנופלת בשבת או בחג – מוקדמת לבוקר שלפני (9:00)
  static DateTime avoid(DateTime utc) {
    var t = utc;
    for (var i = 0; i < 4 && end(t) != null; i++) {
      final x = tz.TZDateTime.from(t, _il);
      t = tz.TZDateTime(_il, x.year, x.month, x.day - 1, 9).toUtc();
    }
    return t;
  }
}
