import 'dart:math' as math;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// האפליקציה לא פועלת בשבת: מ-20 דקות לפני השקיעה בערב שבת עד 40 דקות אחרי השקיעה במוצאי שבת (שעון ישראל)
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

  /// שעת צאת השבת (UTC) אם עכשיו שבת, אחרת null
  static DateTime? end([DateTime? at]) {
    final now = (at ?? DateTime.now()).toUtc();
    final x = tz.TZDateTime.from(now, _il);
    if (x.weekday == DateTime.friday) {
      final s = sunset(x.year, x.month, x.day);
      if (!now.isBefore(s.subtract(const Duration(minutes: _before)))) {
        final n = DateTime.utc(x.year, x.month, x.day + 1);
        return sunset(n.year, n.month, n.day).add(const Duration(minutes: _after));
      }
    }
    if (x.weekday == DateTime.saturday) {
      final e = sunset(x.year, x.month, x.day).add(const Duration(minutes: _after));
      if (now.isBefore(e)) return e;
    }
    return null;
  }

  /// שעה בישראל, לתצוגה
  static String hhmm(DateTime utc) {
    final x = tz.TZDateTime.from(utc, _il);
    return '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  }

  /// התראה שנופלת בשבת – מוקדמת ליום ו' בבוקר
  static DateTime avoid(DateTime utc) {
    if (end(utc) == null) return utc;
    final x = tz.TZDateTime.from(utc, _il);
    final back = x.weekday == DateTime.saturday ? 1 : 0;
    return tz.TZDateTime(_il, x.year, x.month, x.day - back, 9).toUtc();
  }
}
