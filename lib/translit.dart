/// תעתיק של טקסט מנוקד לאותיות לועזיות או קיריליות (כמו translit.js באתר)
library;

const _dag = 'ּ', _sin = 'ׂ', _holam = 'ֹ', _holamV = 'ֺ', _shva = 'ְ';
const _v = {
  'ַ': 'a', 'ָ': 'a', 'ֲ': 'a', 'ֶ': 'e', 'ֵ': 'e', 'ֱ': 'e',
  'ִ': 'i', 'ֹ': 'o', 'ֺ': 'o', 'ֳ': 'o', 'ֻ': 'u', 'ׇ': 'o',
};
const _schemes = {
  'lat': {
    'b': 'b', 'v': 'v', 'g': 'g', 'd': 'd', 'h': 'h', 'z': 'z', 'ch': 'ch', 't': 't', 'y': 'y', 'k': 'k', 'l': 'l',
    'm': 'm', 'n': 'n', 's': 's', 'p': 'p', 'f': 'f', 'ts': 'ts', 'r': 'r', 'sh': 'sh',
    'a': 'a', 'e': 'e', 'i': 'i', 'o': 'o', 'u': 'u', 'adonai': 'Adonai', 'yi': 'i',
  },
  'cyr': {
    'b': 'б', 'v': 'в', 'g': 'г', 'd': 'д', 'h': 'х', 'z': 'з', 'ch': 'х', 't': 'т', 'y': 'й', 'k': 'к', 'l': 'л',
    'm': 'м', 'n': 'н', 's': 'с', 'p': 'п', 'f': 'ф', 'ts': 'ц', 'r': 'р', 'sh': 'ш',
    'a': 'а', 'e': 'е', 'i': 'и', 'o': 'о', 'u': 'у', 'adonai': 'Адонай', 'yi': 'й',
  },
};

bool _isL(String c) => c.compareTo('א') >= 0 && c.compareTo('ת') <= 0;
bool _isMark(String c) => c.compareTo('֑') >= 0 && c.compareTo('ׇ') <= 0;
String? _vowel(String m) {
  for (final ch in m.split('')) {
    if (_v[ch] != null) return _v[ch];
  }
  return null;
}

String _word(String w, Map<String, String> sc) {
  final ls = <String>[], ms = <String>[];
  for (final c in w.split('')) {
    if (_isL(c)) {
      ls.add(c);
      ms.add('');
    } else if (ls.isNotEmpty && _isMark(c)) {
      ms[ms.length - 1] += c;
    }
  }
  if (ls.isEmpty) return w;
  final bare = ls.join(), k = bare.indexOf('יהוה');
  if (k == 0) return sc['adonai']!;
  if (k == 1) return _word(w.substring(0, w.indexOf(ls[1], 1)), sc) + sc['adonai']!;
  final out = StringBuffer();
  for (var i = 0; i < ls.length; i++) {
    final c = ls[i], m = ms[i], last = i == ls.length - 1, dag = m.contains(_dag);
    final vow = _vowel(m);
    final shva = m.contains(_shva);
    var cons = '';
    switch (c) {
      case 'א' || 'ע':
        cons = '';
      case 'ב':
        cons = dag ? 'b' : 'v';
      case 'ג':
        cons = 'g';
      case 'ד':
        cons = 'd';
      case 'ה':
        cons = (last && !dag && vow == null) ? '' : 'h';
      case 'ו':
        final marks = m.replaceAll(RegExp('[֑-ֽ֯׃]'), '');
        if (dag && vow == null && !shva) {
          out.write(sc['u']);
          continue;
        }
        if (vow == 'o' && (marks == _holam || marks == _holamV)) {
          out.write(sc['o']);
          continue;
        }
        cons = 'v';
      case 'ז':
        cons = 'z';
      case 'ח':
        cons = 'ch';
      case 'ט':
        cons = 't';
      case 'י':
        final nextVowVav = i + 1 < ls.length && ls[i + 1] == 'ו' && RegExp('[ֹֺּ]').hasMatch(ms[i + 1]);
        if (vow == null && !shva && !dag && i > 0 && !nextVowVav) {
          final pv = _vowel(ms[i - 1]);
          if (pv == 'i') continue;
          if (pv == 'e') {
            if (ms[i - 1].contains('ֵ')) out.write(sc['yi']);
            continue;
          }
          if (pv == 'a' || pv == 'o' || pv == 'u') {
            out.write(sc['yi']);
            continue;
          }
        }
        cons = 'y';
      case 'כ' || 'ך':
        cons = dag ? 'k' : 'ch';
      case 'ל':
        cons = 'l';
      case 'מ' || 'ם':
        cons = 'm';
      case 'נ' || 'ן':
        cons = 'n';
      case 'ס':
        cons = 's';
      case 'פ' || 'ף':
        cons = dag ? 'p' : 'f';
      case 'צ' || 'ץ':
        cons = 'ts';
      case 'ק':
        cons = 'k';
      case 'ר':
        cons = 'r';
      case 'ש':
        cons = m.contains(_sin) ? 's' : 'sh';
      case 'ת':
        cons = 't';
    }
    if (last && vow == 'a' && (c == 'ח' || c == 'ע' || (c == 'ה' && dag))) {
      out.write(sc['a']);
      if (cons.isNotEmpty) out.write(sc[cons]);
      continue;
    }
    if (cons.isNotEmpty) out.write(sc[cons]);
    if (vow != null) {
      out.write(sc[vow]);
    } else if (shva && i == 0 && cons.isNotEmpty) {
      out.write(sc['e']);
    } else if (shva && i > 0 && ms[i - 1].contains(_shva) && !last) {
      out.write(sc['e']);
    }
  }
  return out.toString();
}

/// scheme: 'lat' (אותיות לועזיות) או 'cyr' (קירילית)
String translit(String text, [String scheme = 'lat']) {
  final sc = _schemes[scheme] ?? _schemes['lat']!;
  final t = text
      .replaceAllMapped(RegExp(r'\s*\([^()]*\)'), (m) => RegExp('[\u05B0-\u05BB\u05C7]').hasMatch(m[0]!) ? m[0]! : '')
      .replaceAll(RegExp("ה['׳](?=[\\s,.:;]|\$)"), 'יהוה')
      .replaceAll('־', ' ')
      .replaceAll(RegExp('[֑-ֽֿ֯׀׃-׆]'), '');
  final res = t.splitMapJoin(RegExp(r'[א-ת֑-ׇ]+'), onMatch: (m) => _word(m[0]!, sc), onNonMatch: (s) => s);
  return res.isEmpty ? res : res[0].toUpperCase() + res.substring(1);
}
