import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'data.dart';
import 'hebcal.dart';

/// תזכורות ליום השנה: שבוע לפני, ובצהרי היום שבערבו מתחיל יום השנה
class Reminders {
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// נקרא בלחיצה על התראה: (מזהה נפטר, מזהה בית עלמין)
  static void Function(int id, String cem)? onOpen;
  static (int, String)? launchedFrom;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    }
    await _n.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final p = _parse(r.payload);
        if (p != null) onOpen?.call(p.$1, p.$2);
      },
    );
    final launch = await _n.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) launchedFrom = _parse(launch!.notificationResponse?.payload);
    _ready = true;
  }

  static (int, String)? _parse(String? s) {
    final parts = (s ?? '').split('|');
    final id = int.tryParse(parts.first);
    return id == null || parts.length < 2 ? null : (id, parts[1]);
  }

  static Future<List<Map<String, dynamic>>> _list() async {
    final s = (await SharedPreferences.getInstance()).getString('yzRem');
    return s == null ? [] : List<Map<String, dynamic>>.from(jsonDecode(s));
  }

  static Future<bool> isOn(int id) async => (await _list()).any((x) => x['id'] == id);

  /// הפעלה/כיבוי. מחזיר את המצב החדש, או null אם אין הרשאה להתראות
  static Future<bool?> toggle(Deceased d) async {
    await init();
    final list = await _list();
    final on = list.any((x) => x['id'] == d.id);
    if (on) {
      list.removeWhere((x) => x['id'] == d.id);
    } else {
      final ok = await _n
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          true;
      if (!ok) return null;
      list.add({'id': d.id, 'cem': d.cemeteryId, 'name': d.fullName, 'death': d.deathDate});
    }
    (await SharedPreferences.getInstance()).setString('yzRem', jsonEncode(list));
    await reschedule();
    return !on;
  }

  /// קובע מחדש את כל ההתראות (בכל פתיחה של האפליקציה, כדי שתמיד יהיו השנים הבאות)
  static Future<void> reschedule() async {
    await init();
    await _n.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails('yahrzeit', 'תזכורות ליום השנה',
          channelDescription: 'תזכורת שבוע לפני יום השנה ובערב שבו הוא מתחיל', importance: Importance.high),
    );
    for (final r in await _list()) {
      final death = DateTime.tryParse(r['death'] ?? '');
      if (death == null) continue;
      final id = r['id'] as int, name = r['name'] ?? '';
      var k = 0;
      for (final y in HebCal.nextYahrzeits(death, count: 2)) {
        final heb = HebCal.format(y.heb);
        final eve = y.date.subtract(const Duration(days: 1));
        final week = y.date.subtract(const Duration(days: 7));
        for (final (at, title, body) in [
          (tz.TZDateTime(tz.local, week.year, week.month, week.day, 10), 'בעוד שבוע יום השנה',
              '$name · $heb · מתחיל בערב ${_dmy(eve)}'),
          (tz.TZDateTime(tz.local, eve.year, eve.month, eve.day, 12), 'הערב מתחיל יום השנה', '$name · $heb'),
        ]) {
          final nid = id * 10 + k++;
          if (at.isBefore(now)) continue;
          await _n.zonedSchedule(nid, title, body, at, details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
              payload: '$id|${r['cem']}');
        }
      }
    }
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// פותח את כרטיס הנפטר מהתראה
Future<void> openFromReminder(NavigatorState nav, int id, String cemId, Widget Function(Deceased, Cemetery) page) async {
  try {
    final d = await Repo.deceased(id);
    final c = (await Repo.cemeteries()).where((x) => x.id == cemId).firstOrNull;
    if (d != null && c != null) nav.push(MaterialPageRoute(builder: (_) => page(d, c)));
  } catch (_) {}
}
