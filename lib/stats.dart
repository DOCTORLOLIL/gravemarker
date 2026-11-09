import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'update.dart';

/// ספירת התקנות ייחודיות: מזהה אקראי שנשמר בטלפון, דיווח פעם ביום. בלי פרטים מזהים.
Future<void> pingInstall(String lang) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('installId');
    if (id == null) {
      final r = math.Random.secure();
      final b = List<int>.generate(16, (_) => r.nextInt(256));
      b[6] = (b[6] & 0x0f) | 0x40;
      b[8] = (b[8] & 0x3f) | 0x80;
      final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
      await prefs.setString('installId', id);
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString('pingDay') == today) return;
    await db.rpc('ping_install', params: {'p_id': id, 'p_build': appBuild, 'p_lang': lang});
    await prefs.setString('pingDay', today);
  } catch (_) {}
}
