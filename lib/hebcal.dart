// לוח עברי – חישוב מדויק (Dershowitz–Reingold). אותו אלגוריתם של האתר, שנבדק מול 28 אלף תאריכים.

class HebDate {
  final int year;
  final String month;
  final int day;
  const HebDate(this.year, this.month, this.day);
}

class Yahrzeit {
  final HebDate heb;
  final DateTime date;
  const Yahrzeit(this.heb, this.date);
}

class HebCal {
  static const int _epoch = -1373427;
  static final DateTime _rd1970 = DateTime.utc(1970, 1, 1);
  static const int _rd1970n = 719163;

  static bool leap(int y) => (7 * y + 1) % 19 < 7;

  static int _elapsed(int y) {
    final m = (235 * y - 234) ~/ 19;
    final p = 12084 + 13753 * m;
    final d = 29 * m + p ~/ 25920;
    return (3 * (d + 1)) % 7 < 3 ? d + 1 : d;
  }

  static int _corr(int y) {
    final a = _elapsed(y - 1), b = _elapsed(y), c = _elapsed(y + 1);
    if (c - b == 356) return 2;
    if (b - a == 382) return 1;
    return 0;
  }

  static int _newYear(int y) => _epoch + _elapsed(y) + _corr(y);

  static List<MapEntry<String, int>> months(int y) {
    final len = _newYear(y + 1) - _newYear(y);
    final hes = len % 10 == 5 ? 30 : 29;
    final kis = len % 10 == 3 ? 29 : 30;
    return [
      const MapEntry('תשרי', 30), MapEntry('חשון', hes), MapEntry('כסלו', kis),
      const MapEntry('טבת', 29), const MapEntry('שבט', 30),
      if (leap(y)) ...[const MapEntry('אדר א', 30), const MapEntry('אדר ב', 29)] else const MapEntry('אדר', 29),
      const MapEntry('ניסן', 30), const MapEntry('אייר', 29), const MapEntry('סיון', 30),
      const MapEntry('תמוז', 29), const MapEntry('אב', 30), const MapEntry('אלול', 29),
    ];
  }

  static int _rdOf(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(_rd1970).inDays + _rd1970n;
  static DateTime _dateOf(int rd) {
    final t = _rd1970.add(Duration(days: rd - _rd1970n));
    return DateTime(t.year, t.month, t.day);
  }

  static HebDate toHeb(DateTime d) {
    final rd = _rdOf(d);
    final g = d.year;
    final y = rd >= _newYear(g + 3761) ? g + 3761 : g + 3760;
    var x = rd - _newYear(y);
    for (final m in months(y)) {
      if (x < m.value) return HebDate(y, m.key, x + 1);
      x -= m.value;
    }
    throw StateError('date');
  }

  static int? _toRd(int y, String month, int day) {
    var rd = _newYear(y);
    for (final m in months(y)) {
      if (m.key == month) return rd + day - 1;
      rd += m.value;
    }
    return null;
  }

  static const _v = [
    [400, 'ת'], [300, 'ש'], [200, 'ר'], [100, 'ק'], [90, 'צ'], [80, 'פ'], [70, 'ע'], [60, 'ס'], [50, 'נ'],
    [40, 'מ'], [30, 'ל'], [20, 'כ'], [10, 'י'], [9, 'ט'], [8, 'ח'], [7, 'ז'], [6, 'ו'], [5, 'ה'], [4, 'ד'],
    [3, 'ג'], [2, 'ב'], [1, 'א'],
  ];

  static String gem(int n) {
    var s = '';
    while (n > 0) {
      if (n == 15 || n == 16) {
        s += 'ט${n == 15 ? 'ו' : 'ז'}';
        break;
      }
      for (final e in _v) {
        if ((e[0] as int) <= n) {
          s += e[1] as String;
          n -= e[0] as int;
          break;
        }
      }
    }
    return s.length > 1 ? '${s.substring(0, s.length - 1)}"${s.substring(s.length - 1)}' : "$s'";
  }

  static String format(HebDate h) => '${gem(h.day)} ${h.month} ${gem(h.year % 1000)}';

  /// יום השנה בשנה עברית נתונה (אדר בשנה מעוברת → אדר ב, מנהג ספרד; 30 בחודש של 29 → א' בחודש הבא)
  static HebDate _yahrzeitIn(HebDate h, int y) {
    var m = h.month, d = h.day;
    if (m == 'אדר' && leap(y)) m = 'אדר ב';
    if ((m == 'אדר א' || m == 'אדר ב') && !leap(y)) m = 'אדר';
    final ms = months(y);
    final idx = ms.indexWhere((e) => e.key == m);
    if (d > ms[idx].value) {
      m = ms[idx + 1].key;
      d = 1;
    }
    return HebDate(y, m, d);
  }

  static List<Yahrzeit> nextYahrzeits(DateTime death, {int count = 5, DateTime? from}) {
    final now = from ?? DateTime.now();
    final h = toHeb(death);
    final today = _rdOf(now);
    final out = <Yahrzeit>[];
    var y = toHeb(now).year - 1;
    while (out.length < count) {
      final z = _yahrzeitIn(h, y);
      final rd = _toRd(z.year, z.month, z.day)!;
      if (z.year > h.year && rd >= today) out.add(Yahrzeit(z, _dateOf(rd)));
      y++;
    }
    return out;
  }
}
